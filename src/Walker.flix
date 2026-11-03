// Walker — 一人称で歩く体の状態と、1 コマ進める規則（純粋: 前の体 + 歩き方 + 遊びの時計 → 次の体）。
//
// 体は足元の点（x・feet・z）と向き（yaw・pitch）と、足の着き方（Footing）で表す。座標は engine の Scene3d と同じ
// （左手系・X 東・Y 上・Z 北）。前へ歩く向きは (sin yaw, 0, cos yaw)。
// 水平の動きは、1 回に進む距離が maxSubstep を超えないよう細かく区切り、区切りごとに壁から押し出す
// （速く走っても薄い壁・手すりを抜けない）。床は Collider.groundBelow で拾う。床が段の高さより下へ消えたら落ちる。
mod Walker {
    use fge::{Clock, Num, Vec2}

    /// このコマの歩き方: 前後（-1..1）・左右（-1..1。正で右）・このコマで向きを変える角（度。正で右へ。マウスの動き）・
    /// 見上げ見下ろしの角（度。正で下を向く）・向きを変え続ける速さ（度/秒。キー）・見上げ見下ろしの速さ（度/秒）・走るか。
    /// 速さの方は遊びの時計の秒を掛けて角にする（実時間で向きが変わらない）。
    pub type alias Drive = { forward = Float64, strafe = Float64, turnDeg = Float64, lookDeg = Float64,
                             turnRate = Float64, lookRate = Float64, sprint = Bool }

    /// 床の面。Flat = 平らな床・Slope = 傾いた板（外階段の段板）。
    pub enum Surface with Eq, ToString {
        case Flat
        case Slope
    }

    /// 足の着き方。Standing = 床に立っている（どの面か）・Falling = 落ちている（落ちる速さ m/秒・上が正）。
    pub enum Footing with Eq, ToString {
        case Standing(Surface)
        case Falling(Float64)
    }

    /// 体の状態。walked = 前の足音から歩いた距離・steps = 足音の数・distance = 歩いた距離の合計（頭の上下が読む）・
    /// running = 今のコマに走っていたか（1 歩の長さが替わる）。
    pub type alias Walker = { x = Float64, feet = Float64, z = Float64, yaw = Float64, pitch = Float64, footing = Footing,
                              walked = Float64, steps = Int32, distance = Float64, running = Bool }

    pub def pi(): Float64 = 3.141592653589793

    def rad(deg: Float64): Float64 = deg * pi() / 180.0

    /// 1 回の押し出しで進む水平の距離の上限（m）。体の半径の半分と 5 cm の小さい方（押し出しは食い込みの浅い側へ出すので、1 回で体の半分より深く入ると反対側へ抜けうる）。
    def maxSubstep(walk: WalkDoc.Rec): Float64 = Float64.min(0.05, walk#radius * 0.5)

    /// 止まって立っている体（足元の高さは呼ぶ側が床に合わせる）。
    pub def standing(x: Float64, feet: Float64, z: Float64, yawDeg: Float64): Walker =
        { x = x, feet = feet, z = z, yaw = rad(yawDeg), pitch = 0.0, footing = Footing.Standing(Surface.Flat),
          walked = 0.0, steps = 0, distance = 0.0, running = false }

    /// 何もしないコマ。
    pub def idle(): Drive = { forward = 0.0, strafe = 0.0, turnDeg = 0.0, lookDeg = 0.0, turnRate = 0.0, lookRate = 0.0, sprint = false }

    /// 体の寸法（WalkDoc から）。
    pub def bodyOf(walk: WalkDoc.Rec): Collider.Body =
        { radius = walk#radius, height = walk#height, stepHeight = walk#stepHeight }

    def surfaceOf(g: Collider.Ground): Surface = if (g#slope) Surface.Slope else Surface.Flat

    /// 足元の下の床: 箱の上の面と、箱の無い所の地面（WalkDoc の groundY。側溝など、当たり判定の箱の隙間で落ちない）の高い方。
    def groundAt(boxes: List[Collider.Box], walk: WalkDoc.Rec, x: Float64, feet: Float64, z: Float64, drop: Float64): Option[Collider.Ground] =
        let plane = if (walk#groundY <= feet + walk#stepHeight and walk#groundY >= feet - drop) Some({ y = walk#groundY, slope = false }) else None;
        match (Collider.groundBelow(boxes, bodyOf(walk), x, feet, z, drop), plane) {
            case (Some(g), Some(p)) => Some(if (g#y >= p#y) g else p)
            case (Some(g), None)    => Some(g)
            case (None, other)      => other
        }

    /// 床に立っているか。
    pub def isGrounded(w: Walker): Bool = match w#footing {
        case Footing.Standing(_) => true
        case Footing.Falling(_)  => false
    }

    /// 足元を床に合わせた体（足元の高さから段の高さより上を探し始め、下へ 20 m まで。床が無ければそのまま）。
    /// 始まりと置き直しで使う。上の階に立たせる時は feet にその階のおおよその高さを入れておく。
    pub def settle(boxes: List[Collider.Box], walk: WalkDoc.Rec, w: Walker): Walker =
        match groundAt(boxes, walk, w#x, w#feet, w#z, 20.0) {
            case Some(g) => { feet = g#y, footing = Footing.Standing(surfaceOf(g)) | w }
            case None    => w
        }

    /// 歩く向き（前と右を足した水平の向き。長さは 1 以下）。
    def heading(yaw: Float64, d: Drive): (Float64, Float64) =
        let (s, c) = (Vec2.sin(yaw), Vec2.cos(yaw));
        let x = d#forward * s + d#strafe * c;
        let z = d#forward * c - d#strafe * s;
        let len = Vec2.sqrt(x * x + z * z);
        if (len > 1.0) (x / len, z / len) else (x, z)

    /// 1 コマ進める（秒は遊びの時計の今のコマの分）。
    pub def step(boxes: List[Collider.Box], walk: WalkDoc.Rec, d: Drive, clock: Clock.Clock[PlayClock.Play], w: Walker): Walker =
        stepSeconds(boxes, walk, d, Num.clamp(0.0, 0.05, Clock.dtOf(clock)), w)

    /// step の本体: 向き → 区切って水平に動く（区切りごとに壁から出して床に乗る）→ 足音を数える。
    def stepSeconds(boxes: List[Collider.Box], walk: WalkDoc.Rec, d: Drive, dt: Float64, w: Walker): Walker =
        let limit = rad(walk#pitchLimit);
        let yaw = w#yaw + rad(d#turnDeg + d#turnRate * dt);
        let pitch = Num.clamp(0.0 - limit, limit, w#pitch + rad(d#lookDeg + d#lookRate * dt));
        let speed = if (d#sprint) walk#runSpeed else walk#walkSpeed;
        let (hx, hz) = heading(yaw, d);
        let travel = speed * dt * Vec2.sqrt(hx * hx + hz * hz);
        let n = Int32.max(1, Float64.tryToInt32(Float64.ceil(travel / maxSubstep(walk))) |> Option.getWithDefault(1));
        let near = Collider.near(boxes, w#x, w#z, travel + 1.5);
        let sub = dt / Int32.toFloat64(n);
        let moved = List.range(0, n) |> List.foldLeft((acc, _) -> substep(near, walk, hx * speed * sub, hz * speed * sub, sub, acc), w);
        let flat = Vec2.sqrt((moved#x - w#x) * (moved#x - w#x) + (moved#z - w#z) * (moved#z - w#z));
        let stride = if (d#sprint) walk#runStride else walk#stride;
        let walked = if (isGrounded(moved)) w#walked + flat else w#walked;
        let stepped = walked >= stride;
        { yaw = yaw, pitch = pitch, walked = if (stepped) walked - stride else walked,
          steps = if (stepped) w#steps + 1 else w#steps, distance = w#distance + flat, running = d#sprint | moved }

    /// 区切り 1 つ: 水平に (dx, dz) 動いて壁から出し、歩ける範囲に収め、床に乗るか落ちる。
    /// 動かない区切り（立ち止まっている）は押し出しも床合わせもしない（止まっている時に位置が震えない）。
    def substep(near: List[Collider.Box], walk: WalkDoc.Rec, dx: Float64, dz: Float64, dt: Float64, w: Walker): Walker =
        let still = dx == 0.0 and dz == 0.0 and isGrounded(w);
        if (still) w
        else {
            let body = bodyOf(walk);
            // 歩ける範囲に収めてから壁の外へ出す（出した後に収めると、範囲の端の壁へ押し戻しうる）。
            let b = walk#bounds;
            let (nx, nz) = Collider.resolve(near, body, Num.clamp(b#minX, b#maxX, w#x + dx), w#feet, Num.clamp(b#minZ, b#maxZ, w#z + dz));
            let (feet, footing) = fall(near, walk, nx, nz, dt, w);
            let moved = { x = nx, z = nz, feet = feet, footing = footing | w };
            // 押し出しと床合わせの後でも箱に食い込む動き（下から段板の低い端へ潜り込んで上に乗る・角で押し合う）は、
            // 前より深くなるなら水平に動かない（落ちる・立つの縦だけ残す）。
            let before = Collider.deepestOverlap(near, body, w#x, w#feet, w#z);
            let after = Collider.deepestOverlap(near, body, nx, feet, nz);
            if (after > Float64.max(0.005, before)) { feet = fallOnly(near, walk, dt, w) | w } else moved
        }

    /// 水平に動かない時の足元の高さ（落ちている間は落ち続ける・立っていればそのまま）。
    def fallOnly(near: List[Collider.Box], walk: WalkDoc.Rec, dt: Float64, w: Walker): Float64 =
        match w#footing {
            case Footing.Standing(_) => w#feet
            case Footing.Falling(_)  => fst(fall(near, walk, w#x, w#z, dt, w))
        }

    /// 足元の高さと足の着き方の次の値。立っている間は段の高さの中で床に吸い付き（階段を下りても浮かない）、
    /// 床が無くなったら落ち始め、落ちている間は下の床に着いた所で止まる。
    def fall(near: List[Collider.Box], walk: WalkDoc.Rec, x: Float64, z: Float64, dt: Float64, w: Walker): (Float64, Footing) =
        match w#footing {
            case Footing.Standing(_) =>
                match groundAt(near, walk, x, w#feet, z, 0.45) {
                    case Some(g) => (g#y, Footing.Standing(surfaceOf(g)))
                    case None    => (w#feet, Footing.Falling(0.0))
                }
            case Footing.Falling(vy0) =>
                let vy = vy0 - walk#gravity * dt;
                let next = w#feet + vy * dt;
                match groundAt(near, walk, x, w#feet, z, w#feet - next + 0.02) {
                    case Some(g) if g#y >= next => (g#y, Footing.Standing(surfaceOf(g)))
                    case _                      => (next, Footing.Falling(vy))
                }
        }

    /// 同じ歩き方と同じ時計の刻みで n コマ進めた体の列（1 コマ目の後から n コマ目の後まで）。
    /// テストと、操作を記録した手順から挟まった所を探す時に使う。
    pub def simulate(boxes: List[Collider.Box], walk: WalkDoc.Rec, d: Drive, clock: Clock.Clock[PlayClock.Play], n: Int32, w: Walker): List[Walker] =
        List.range(0, n) |> List.foldLeft((acc, _) -> {
            let (cur, out) = acc;
            let next = step(boxes, walk, d, clock, cur);
            (next, next :: out)
        }, (w, Nil)) |> snd |> List.reverse

    /// 目の位置の高さ（足元 + 目の高さ + 歩く上下）。
    pub def eyeY(walk: WalkDoc.Rec, w: Walker): Float64 =
        let stride = Float64.max(0.1, if (w#running) walk#runStride else walk#stride);
        w#feet + walk#eyeHeight + walk#bobHeight * Float64.abs(Vec2.sin(pi() * w#distance / stride))
}
