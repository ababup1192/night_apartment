// PlayStep — 歩いている間の 1 コマ（体・玄関の扉・手の灯り）を進める規則（純粋）。
// 手で歩く時（World）・自動の操縦（Pilot.simulate）・テストが同じ物を通る。
//
// 順番: E を押したら見ている扉を動かすか物を調べる → 扉を回す（体に当たる所では止まる）→ 今の扉の板を動く箱にして体を歩かせる。
// 扉を先に回すのは、体を歩かせる時に今の角の板を壁にするため（回る扉が体に食い込む所では Doors が回さない）。
mod PlayStep {
    use fge::{Clock, CollisionShape3d, CollisionWorld3d, Num, Ray3d, Vec3}

    /// 動かない物: 常に効く当たり判定の集まり（扉の板を除き、歩ける範囲の囲みを含む）・部屋の並び・歩く Doc・部屋の Doc・
    /// E で調べる物の Doc と、扉の板を除く当たり判定のノードの的。
    pub type alias Env = { world = CollisionWorld3d.CollisionWorld3d, rooms = List[Rooms.Room], walk = WalkDoc.Rec, doors = RoomsDoc.Door,
                           inspect = InspectDoc.Rec, things = List[(Inspect.Key, Ray3d.RayTarget)] }

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

    /// 1 コマで動く物: 体・扉の状態（部屋の番号ごと）・手の灯り・最後に E で調べた物の文言。
    pub type alias Body = { walker = Walker.Walker, doors = Map[String, Doors.State], light = Flashlight, seen = Option[Inspect.Seen] }

    /// このコマの操作: 歩き方・E を押したか（press）・手の灯りをどうするか。
    pub type alias Act = { drive = Walker.Drive, press = Bool, light = LightCue }

    /// 何もしないコマ。
    pub def idle(): Act = { drive = Walker.idle(), press = false, light = LightCue.Keep }

    /// 1 コマ進める（秒は遊びの時計の今のコマの分）。
    pub def step(env: Env, act: Act, clock: Clock.Clock[PlayClock.Play], b: Body): Body = stepWith(env, Nil, act, clock, b)

    /// step の、動いている物の箱（movers。歩いている人のカプセル）も壁にする版。扉の板と動いている物の方から体へ食い込んだ時は、
    /// 体が止まっていても押し出す（CharacterBody3d.moveAndSlide の動く箱）。
    pub def stepWith(env: Env, movers: List[CollisionShape3d.Box3d], act: Act, clock: Clock.Clock[PlayClock.Play], b: Body): Body =
        let dt = Num.clamp(0.0, 0.05, Clock.dtOf(clock));
        let w = b#walker;
        let pick = if (act#press) pressed(env, b) else Inspect.Pick.Nothing;
        let used = match pick {
            case Inspect.Pick.Door(id) => Doors.toggleAt(env#doors, env#rooms, id, b#doors)
            case _                     => b#doors
        };
        let seen = match pick {
            case Inspect.Pick.Thing(text) => Some({ text = text, at = Clock.nowOf(clock) })
            case _                        => b#seen
        };
        let turned = Doors.stepAll(env#doors, env#rooms, Walker.settingsOf(env#walk), Vec3.v3(w#x, w#feet, w#z), dt, used);
        let moving = List.append(Doors.leafBoxes(env#rooms, turned), movers);
        { walker = Walker.step(env#world, moving, env#walk, act#drive, clock, w), doors = turned,
          light = applyCue(act#light, b#light), seen = seen }

    /// E を押した時に引く物: 目の向きのレイが最初に当たる扉の板（扉の届く所 Doors.isInReach の物だけ）か調べる物。
    /// どちらでもなければ（壁・床・何も無い・届かない扉）向いている扉（Doors.target）。
    /// WhyNot: レイが壁に当たった時に扉を諦めない — 扉の横の壁を見て押しても開くのが今までの手触りで、自動の操縦の押し方もそれに頼る。
    pub def pressed(env: Env, b: Body): Inspect.Pick =
        let w = b#walker;
        let facing = () -> Doors.target(env#doors, env#rooms, b#doors, w) |> Option.map(Inspect.Pick.Door) |> Option.getWithDefault(Inspect.Pick.Nothing);
        let reachable = (id: String) -> List.exists(r -> r#id == id and Doors.isInReach(env#doors, b#doors, r, w), env#rooms);
        match Inspect.pick(env#inspect, List.append(Inspect.doorTargets(env#rooms, b#doors), env#things), Walker.forwardRay(env#walk, w)) {
            case Inspect.Pick.Door(id) if not reachable(id) => facing()
            case Inspect.Pick.Nothing                         => facing()
            case other                                        => other
        }

    /// 同じ操作を n コマ続けた後の物（テストが「扉を通れるか」を見る）。
    pub def simulate(env: Env, act: Act, clock: Clock.Clock[PlayClock.Play], n: Int32, b: Body): Body =
        List.range(0, n) |> List.foldLeft((acc, _) -> step(env, act, clock, acc), b)
}
