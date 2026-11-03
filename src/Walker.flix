// Walker — 一人称で歩く体の状態と、1 コマ進める規則（純粋: 前の体 + 歩き方 + 遊びの時計 → 次の体）。
//
// 体は足元の点（x・feet・z）と向き（yaw・pitch）と、足の着き方（engine の CharacterBody3d.Footing）で表す。座標は engine の Scene3d と同じ
// （左手系・X 東・Y 上・Z 北）。前へ歩く向きは (sin yaw, 0, cos yaw)。
// 壁から押し出す・段を上がる・床に吸い付く・落ちるは engine の CharacterBody3d.moveAndSlide。ここは向き・足音・頭の上下を持つ。
mod Walker {
    use fge::{
        Camera3d, CharacterBody3d, Clock, CollisionShape3d, CollisionWorld3d, Num, Ray3d, Vec3
    }

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

    /// 体の状態。walked = 前の足音から歩いた距離・steps = 足音の数・distance = 歩いた距離の合計（頭の上下が読む）・
    /// running = 今のコマに走っていたか（1 歩の長さが替わる）。
    pub type alias Walker = { x = Float64, feet = Float64, z = Float64, yaw = Float64, pitch = Float64, footing = CharacterBody3d.Footing,
                              walked = Float64, steps = Int32, distance = Float64, running = Bool }

    def rad(deg: Float64): Float64 = deg * Num.pi() / 180.0

    /// 止まって立っている体（足の着き方は呼ぶ側が settle で床に合わせる）。
    pub def standing(x: Float64, feet: Float64, z: Float64, yawDeg: Float64): Walker =
        { x = x, feet = feet, z = z, yaw = rad(yawDeg), pitch = 0.0, footing = CharacterBody3d.bodyAt(Vec3.v3(x, feet, z))#footing,
          walked = 0.0, steps = 0, distance = 0.0, running = false }

    /// 何もしないコマ。
    pub def idle(): Drive = { forward = 0.0, strafe = 0.0, turnDeg = 0.0, lookDeg = 0.0, turnRate = 0.0, lookRate = 0.0, sprint = false }

    /// 体の寸法と動き方（WalkDoc から。吸い付く深さ・区切りの長さは engine の既定）。
    pub def settingsOf(walk: WalkDoc.Rec): CharacterBody3d.Settings =
        { stepHeight = walk#stepHeight, gravity = walk#gravity, floorMaxAngleDeg = walk#floorMaxAngleDeg | CharacterBody3d.settings(walk#radius, walk#height) }

    /// engine の体（足元の点と足の着き方）。
    def bodyOf(w: Walker): CharacterBody3d.Body = { feet = Vec3.v3(w#x, w#feet, w#z), footing = w#footing }

    /// engine の体の位置と足の着き方を写した体。
    def withBody(b: CharacterBody3d.Body, w: Walker): Walker = { x = b#feet#x, feet = b#feet#y, z = b#feet#z, footing = b#footing | w }

    /// 床に立っているか。
    pub def isGrounded(w: Walker): Bool = CharacterBody3d.isOnFloor(bodyOf(w))

    /// 立っている床の面（落ちている間は None）。
    pub def surfaceOf(w: Walker): Option[Surface] = match w#footing {
        case CharacterBody3d.Footing.OnFloor(f)  => Some(if (f#sloped) Surface.Slope else Surface.Flat)
        case CharacterBody3d.Footing.Airborne(_) => None
    }

    /// 足の着き方の字（Standing(Flat)・Standing(Slope)・Falling）。記録の指紋とテストが比べる。
    pub def footingName(w: Walker): String = match surfaceOf(w) {
        case Some(s) => "Standing(${s})"
        case None    => "Falling"
    }

    /// 足元を床に合わせた体（足元の高さから段の高さより上を探し始め、下へ 20 m まで。床が無ければそのまま）。
    /// 始まりと置き直しで使う。上の階に立たせる時は feet にその階のおおよその高さを入れておく。
    pub def settle(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, w: Walker): Walker =
        withBody(CharacterBody3d.snapToFloor(world, Nil, settingsOf(walk), bodyOf(w)), w)

    /// 歩く向き（前と右を足した水平の向き。長さは 1 以下）。
    def heading(yaw: Float64, d: Drive): (Float64, Float64) =
        let (s, c) = (Num.sin(yaw), Num.cos(yaw));
        let x = d#forward * s + d#strafe * c;
        let z = d#forward * c - d#strafe * s;
        let len = Num.sqrt(x * x + z * z);
        if (len > 1.0) (x / len, z / len) else (x, z)

    /// 1 コマ進める（秒は遊びの時計の今のコマの分）。world = 動かない箱・moving = このコマの動く箱（扉の板・歩いている人）。
    pub def step(world: CollisionWorld3d.CollisionWorld3d, moving: List[CollisionShape3d.Box3d], walk: WalkDoc.Rec, d: Drive,
                 clock: Clock.Clock[PlayClock.Play], w: Walker): Walker =
        stepSeconds(world, moving, walk, d, Num.clamp(0.0, 0.05, Clock.dtOf(clock)), w)

    /// step の本体: 向き → engine の体を動かす → 足音を数える。
    def stepSeconds(world: CollisionWorld3d.CollisionWorld3d, moving: List[CollisionShape3d.Box3d], walk: WalkDoc.Rec, d: Drive,
                    dt: Float64, w: Walker): Walker =
        let limit = rad(walk#pitchLimit);
        let yaw = w#yaw + rad(d#turnDeg + d#turnRate * dt);
        let pitch = Num.clamp(0.0 - limit, limit, w#pitch + rad(d#lookDeg + d#lookRate * dt));
        let speed = if (d#sprint) walk#runSpeed else walk#walkSpeed;
        let (hx, hz) = heading(yaw, d);
        let body = CharacterBody3d.moveAndSlide(world, moving, settingsOf(walk), Vec3.v3(hx * speed, 0.0, hz * speed), dt, bodyOf(w));
        let moved = withBody(body, w);
        let flat = Num.sqrt((moved#x - w#x) * (moved#x - w#x) + (moved#z - w#z) * (moved#z - w#z));
        let stride = if (d#sprint) walk#runStride else walk#stride;
        let walked = if (isGrounded(moved)) w#walked + flat else w#walked;
        let stepped = walked >= stride;
        { yaw = yaw, pitch = pitch, walked = if (stepped) walked - stride else walked,
          steps = if (stepped) w#steps + 1 else w#steps, distance = w#distance + flat, running = d#sprint | moved }

    /// 同じ歩き方と同じ時計の刻みで n コマ進めた体の列（1 コマ目の後から n コマ目の後まで）。
    /// テストと、操作を記録した手順から挟まった所を探す時に使う。
    pub def simulate(world: CollisionWorld3d.CollisionWorld3d, walk: WalkDoc.Rec, d: Drive, clock: Clock.Clock[PlayClock.Play], n: Int32, w: Walker): List[Walker] =
        List.range(0, n) |> List.foldLeft((acc, _) -> {
            let (cur, out) = acc;
            let next = step(world, Nil, walk, d, clock, cur);
            (next, next :: out)
        }, (w, Nil)) |> snd |> List.reverse

    /// 体が箱に食い込んでいる一番深い所（m。0 なら食い込んでいない）。
    pub def overlapDepth(world: CollisionWorld3d.CollisionWorld3d, moving: List[CollisionShape3d.Box3d], walk: WalkDoc.Rec, w: Walker): Float64 =
        CharacterBody3d.overlapDepth(world, moving, settingsOf(walk), bodyOf(w))

    /// 目の位置（足元の真上・目の高さ + 歩く上下）。
    pub def eyeOf(walk: WalkDoc.Rec, w: Walker): Vec3.Vec3 = Vec3.v3(w#x, eyeY(walk, w), w#z)

    /// 目から見ている向きへ伸びるレイ（画面の真ん中の点の先）。
    pub def forwardRay(walk: WalkDoc.Rec, w: Walker): Ray3d.Ray3d =
        Camera3d.forwardRay({ eye = eyeOf(walk, w), yaw = w#yaw, pitch = w#pitch, fovY = rad(walk#fovY), near = 0.05, far = 100.0 })

    /// 目の位置の高さ（足元 + 目の高さ + 歩く上下）。
    pub def eyeY(walk: WalkDoc.Rec, w: Walker): Float64 =
        let stride = Float64.max(0.1, if (w#running) walk#runStride else walk#stride);
        w#feet + walk#eyeHeight + walk#bobHeight * Float64.abs(Num.sin(Num.pi() * w#distance / stride))
}
