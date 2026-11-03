// PlayStep — 歩いている間の 1 コマ（体・玄関の扉・手の灯り）を進める規則（純粋）。
// 手で歩く時（World）・自動の操縦（Pilot.simulate）・テストが同じ物を通る。
//
// 順番: E を押したら向いている扉を動かす → 扉を回す（体に当たる所では止まる）→ 今の扉の板の箱と常に効く箱の中で体を歩かせる。
// 扉を先に回すのは、回った扉の板で体を押し出さないため（体の動きは今の扉の箱の外へだけ出る）。
mod PlayStep {
    use fge::{Clock, Num, Vec3}

    /// 動かない物: 常に効く当たり判定の箱（扉の板を除く）・部屋の並び・歩く Doc・部屋の Doc。
    pub type alias Env = { boxes = List[Collider.Box], rooms = List[Rooms.Room], walk = WalkDoc.Rec, doors = RoomsDoc.Door }

    /// 手の灯り（懐中電灯）。
    pub enum Flashlight with Eq, ToString {
        case On
        case Off
    }

    pub def flashlightOf(on: Bool): Flashlight = if (on) Flashlight.On else Flashlight.Off

    pub def isOn(f: Flashlight): Bool = f == Flashlight.On

    /// このコマに手の灯りをどうするか。Keep ならそのまま。
    pub enum LightCue with Eq, ToString {
        case TurnOn
        case TurnOff
        case Keep
    }

    /// 灯りの指示を当てた後の灯り。
    pub def applyCue(cue: LightCue, f: Flashlight): Flashlight = match cue {
        case LightCue.TurnOn  => Flashlight.On
        case LightCue.TurnOff => Flashlight.Off
        case LightCue.Keep    => f
    }

    /// 1 コマで動く物: 体・扉の状態（部屋の番号ごと）・手の灯り。
    pub type alias Body = { walker = Walker.Walker, doors = Map[String, Doors.State], light = Flashlight }

    /// このコマの操作: 歩き方・E を押したか（press）・手の灯りをどうするか。
    pub type alias Act = { drive = Walker.Drive, press = Bool, light = LightCue }

    /// 何もしないコマ。
    pub def idle(): Act = { drive = Walker.idle(), press = false, light = LightCue.Keep }

    /// 今の扉の板の箱を足した当たり判定の箱。
    def boxesOf(env: Env, doors: Map[String, Doors.State]): List[Collider.Box] =
        List.append(env#boxes, Doors.leafBoxes(env#rooms, doors))

    /// 1 コマ進める（秒は遊びの時計の今のコマの分）。
    pub def step(env: Env, act: Act, clock: Clock.Clock[PlayClock.Play], b: Body): Body = stepWith(env, Nil, act, clock, b)

    /// step の、動いている物の箱（movers。歩いている人のカプセル）も壁にする版。動いている物の方から体へ食い込んだ時は、
    /// 体が止まっていても押し出す（体の押し出しは体が動いた区切りでしか走らない）。
    pub def stepWith(env: Env, movers: List[Collider.Box], act: Act, clock: Clock.Clock[PlayClock.Play], b: Body): Body =
        let dt = Num.clamp(0.0, 0.05, Clock.dtOf(clock));
        let w = b#walker;
        let used = if (act#press) Doors.target(env#doors, env#rooms, b#doors, w) |> Option.map(id -> Doors.toggleAt(env#doors, env#rooms, id, b#doors)) |> Option.getWithDefault(b#doors)
                   else b#doors;
        let turned = Doors.stepAll(env#doors, env#rooms, Walker.bodyOf(env#walk), Vec3.v3(w#x, w#feet, w#z), dt, used);
        let boxes = List.append(boxesOf(env, turned), movers);
        let walked = Walker.step(boxes, env#walk, act#drive, clock, w);
        { walker = pushedBy(boxes, movers, env#walk, walked), doors = turned,
          light = applyCue(act#light, b#light) }

    /// 動いている物に食い込んだ体を、全部の箱の外へ水平に出した体（食い込んでいなければそのまま）。
    def pushedBy(boxes: List[Collider.Box], movers: List[Collider.Box], walk: WalkDoc.Rec, w: Walker.Walker): Walker.Walker =
        let body = Walker.bodyOf(walk);
        if (Collider.deepestOverlap(movers, body, w#x, w#feet, w#z) <= 0.0) w
        else {
            let (x, z) = Collider.resolve(Collider.near(boxes, w#x, w#z, 1.5), body, w#x, w#feet, w#z);
            { x = x, z = z | w }
        }

    /// 同じ操作を n コマ続けた後の物（テストが「扉を通れるか」を見る）。
    pub def simulate(env: Env, act: Act, clock: Clock.Clock[PlayClock.Play], n: Int32, b: Body): Body =
        List.range(0, n) |> List.foldLeft((acc, _) -> step(env, act, clock, acc), b)
}
