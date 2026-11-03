// テストの共通の道具: 舞台の当たり判定の箱・歩く Doc の既定・決まった刻みの遊びの時計・体の取り出し。
// 箱は Blender の書き出し（assets/apartment/collision.glb）をそのまま読む。
mod TestKit {
    use fge::{Clock, CollisionShape3d, CollisionWorld3d, Gltf, HeadlessLoad, Model3d, PxSpriteDoc}

    /// 書き出しの collision.glb（読めなければテストを止める）。
    pub def model(): Model3d.Model3d \ Fs.FileRead = match Gltf.load("assets/apartment/collision.glb") {
        case Ok(m)    => m
        case Err(why) => bug!("collision.glb が読めない: ${why}")
    }

    /// 書き出しの当たり判定の箱全部（扉は閉じた板のまま）。
    pub def boxes(): List[CollisionShape3d.Box3d] \ Fs.FileRead = Collider.boxesOf(model())

    /// 書き出しの当たり判定の箱全部と歩ける範囲の囲みの集まり（扉は閉じた板のまま）。
    pub def world(): CollisionWorld3d.CollisionWorld3d \ Fs.FileRead = Collider.worldOf(boxes(), walk())

    /// 書き出しの manifest.json の字（読めなければ空）。
    pub def manifest(): String \ Fs.FileRead = Fs.FileRead.read("assets/apartment/manifest.json") |> Result.getWithDefault("")

    /// 2 階の部屋の並びと、扉の板を外した当たり判定のノード。
    pub def layout(): (List[Rooms.Room], List[Model3d.ModelNode]) \ Fs.FileRead = Rooms.layoutOf(manifest(), model())

    /// 扉の板を外した常に効く箱。
    pub def statics(): List[CollisionShape3d.Box3d] \ Fs.FileRead = Collider.boxesOfNodes(snd(layout()))

    /// 番号の部屋（無ければテストを止める）。
    pub def room(id: String): Rooms.Room \ Fs.FileRead =
        match fst(layout()) |> List.find(r -> r#id == id) {
            case Some(r) => r
            case None    => bug!("部屋 ${id} が書き出しに無い")
        }

    /// 歩く・扉を回す規則の動かない物（書き出しの箱と部屋・Doc の既定）。
    pub def env(): PlayStep.Env \ Fs.FileRead =
        let (rooms, nodes) = layout();
        { world = Collider.worldOf(Collider.boxesOfNodes(nodes), walk()), rooms = rooms, walk = walk(), doors = RoomsDoc.rec(RoomsDoc.defaults())#door,
          inspect = InspectDoc.rec(inspectDoc()), things = Inspect.nodeTargets(nodes) }

    /// 調べる物の Doc（書き出しの名前に合わせた assets/inspect.kind.json）。
    pub def inspectDoc(): InspectDoc.Doc \ Fs.FileRead = InspectDoc.load(InspectDoc.path())

    /// 扉の Doc の既定。
    pub def doorDoc(): RoomsDoc.Door = RoomsDoc.rec(RoomsDoc.defaults())#door

    /// 歩く Doc の既定。
    pub def walk(): WalkDoc.Rec = WalkDoc.rec(WalkDoc.defaults())

    /// 1 コマが dt 秒の遊びの時計。
    pub def clockOf(dt: Float64): Clock.Clock[PlayClock.Play] =
        Clock.advance(Clock.paceOf(Clock.Run.Running), dt, Clock.start())

    /// 60 fps の 1 コマ。
    pub def frame(): Clock.Clock[PlayClock.Play] = clockOf(1.0 / 60.0)

    /// 前へ歩く（sprint で走る）。
    pub def forward(sprint: Bool): Walker.Drive = { forward = 1.0, sprint = sprint | Walker.idle() }

    /// 足元 (x, z)・おおよその高さ y に向き yaw（度）で立たせ、床に合わせた体。
    pub def standAt(world: CollisionWorld3d.CollisionWorld3d, x: Float64, y: Float64, z: Float64, yaw: Float64): Walker.Walker =
        Walker.settle(world, walk(), Walker.standing(x, y, z, yaw))

    /// 足元の高さを cm に丸めた値（床の高さを比べる）。
    pub def feetCm(w: Walker.Walker): Int32 = Float64.tryToInt32(Float64.round(w#feet * 100.0)) |> Option.getWithDefault(-1)

    // ── 住人 ──

    /// 書き出しの住人（絵は 64 px まで縮めて読む — 形・骨・動きだけを見るテストを速くする）。
    pub def residents(): List[People.Person] \ Fs.FileRead + IO =
        HeadlessLoad.handle(() -> People.load("assets/apartment", { baseColor = 64, normal = 64 }))

    /// 書き出しの当たり判定の箱・2 階の部屋・住人を持ち、ほかは既定の Doc の描く元（部品の形と絵は読まない）。
    pub def peopleRes(): Res.Res \ Fs.FileRead + IO =
        let (rooms, nodes) = layout();
        Res.build({ sample = SampleDoc.defaults(), inspect = InspectDoc.defaults(), keys = KeysDoc.defaults(), theme = ThemeDoc.defaults(), sprites = PxSpriteDoc.empty(),
                    walk = WalkDoc.defaults(), look = LookDoc.defaults(), lights = LightsDoc.defaults(), sound = SoundDoc.defaults(),
                    tour = TourDoc.defaults(), rooms = RoomsDoc.defaults(), people = PeopleDoc.defaults(), prefs = AudioPrefs.defaults(),
                    stage = { parts = Nil, boxes = Collider.boxesOfNodes(nodes), rooms = rooms, things = Inspect.nodeTargets(nodes) }, residents = residents() })

    /// 名前の住人（無ければテストを止める）。
    pub def person(res: Res.Res, id: String): People.Person =
        match res#residents |> List.find(p -> p#entry#id == id) {
            case Some(p) => p
            case None    => bug!("住人 ${id} が書き出しに無い")
        }

    /// 何もしない入力。
    pub def noInput(): World.Input = { drive = Walker.idle(), actions = Set.empty() }

    /// 階段の人の状態の名前（歩いている秒を落とす）。
    pub def stairsName(s: World.Stairs): String = match s {
        case World.Stairs.Waiting    => "Waiting"
        case World.Stairs.Walking(_) => "Walking"
        case World.Stairs.Gone       => "Gone"
    }
}
