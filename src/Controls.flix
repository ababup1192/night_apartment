// Controls — キーとマウスを World.Input へ写し、World.step で 1 歩進める（純粋）。
// どのキーがどの操作かは KeysDoc（player.keys.json）が決める。マウスは窓を押すと窓にキャプチャし（App.withMouseCapture）、
// 動いた量（frame#mouseDelta）で視点を回す。Esc で放し、放している時の Esc で終了の確認を出す。
// Doc と舞台の読み込み（loadDocs）と、保存即反映（watchFile）・F1 一括リロードの読み直しもここに置く。
mod Controls {

    use fge::{App, DocTable, GameEngine, LoadProgress, PxSpriteDoc, Resources, SortingLayer, Vec2}

    /// マウスの動いた量（design px）を、このコマに回す角（度。yaw, pitch）へ。キャプチャしていない・窓にフォーカスが無い時は回さない。
    /// 上下は invertY で逆にする（pitch は正で下を向く）。
    pub def lookOf(walk: WalkDoc.Rec, looking: Bool, focused: Bool, delta: Vec2.Vec2): (Float64, Float64) =
        if (not looking or not focused) (0.0, 0.0)
        else (delta#x * walk#mouseSensitivity, delta#y * walk#mouseSensitivity * (if (walk#invertY) -1.0 else 1.0))

    /// このフレームのキーとマウスを World.Input へ（逆向きが同時なら打ち消して 0）。
    /// キーは向きを変える速さ（turnSpeed 度/秒）・マウスはこのコマの角（mouseSensitivity × px）で渡す。
    def inputOf(frame: App.Frame, res: Res.Res, w: World.World): World.Input =
        let k = KeysDoc.rec(res#keys);
        let walk = WalkDoc.rec(res#walk);
        let held = ks -> List.exists(key -> App.isDown(key, frame), ks);
        let pressed = ks -> List.exists(key -> App.justPressed(key, frame), ks);
        let axis = (neg, pos) -> (if (held(pos)) 1.0 else 0.0) - (if (held(neg)) 1.0 else 0.0);
        let (mdx, mdy) = lookOf(walk, World.isLooking(w), frame#windowFocused, frame#mouseDelta);
        { drive = { forward = axis(k#back, k#forward), strafe = axis(k#left, k#right),
                    turnDeg = mdx, lookDeg = mdy,
                    turnRate = axis(k#turnLeft, k#turnRight) * walk#turnSpeed,
                    lookRate = axis(k#lookUp, k#lookDown) * walk#turnSpeed * 0.6, sprint = held(k#sprint) },
          actions = actionsOf(pressed, k) }

    /// このコマに押した操作（割り当てのキーのどれかを押した物）。
    def actionsOf(pressed: List[GameEngine.Key] -> Bool, k: KeysDoc.Rec): Set[World.Action] =
        ((World.Action.ToggleLight, k#light) :: (World.Action.ToggleColliders, k#colliders) :: (World.Action.Interact, k#door) :: Nil)
            |> List.filter(e -> pressed(snd(e))) |> List.map(fst) |> List.toSet

    /// 毎フレームのシステム。終了の確認の窓が出ている間は Enter で終わる・Esc で戻る（マウスは tapAt）。
    /// 遊んでいる間は、窓を押すとマウスをキャプチャし、Esc でキャプチャを放す。放している時の Esc で終了の確認を出す。
    /// マウスを放している間は隅の音量の印を押す（か volume のキー）と音量の窓が開き、開いている間は Esc か窓の外を押すと閉じる。
    /// Esc・Enter・F3（診断の表示）は OS とゲームの慣習に合わせた固定のキー（割り当ての Doc には載せない）。
    pub def step(frame: App.Frame, res: Res.Res, w: World.World): World.World =
        let pressed = key -> App.justPressed(key, frame);
        let w1 =
            if (World.isAskingQuit(w))
                (if (pressed(GameEngine.Key.Enter)) World.answerQuit(true, w)
                 else if (pressed(GameEngine.Key.Escape)) World.answerQuit(false, w)
                 else w)
            else if (pressed(GameEngine.Key.Escape) and World.isVolumeOpen(w)) World.closeVolume(w)
            else if (pressed(GameEngine.Key.Escape) and World.isLooking(w)) World.setLooking(false, w)
            else if (pressed(GameEngine.Key.Escape)) World.askQuit(w)
            else if (frame#mouseClicked and not World.isLooking(w)) pressAt(res, frame#cursor, w)
            else volumeKeys(frame, res, w);
        let w2 = if (frame#mouseClicked and World.isAskingQuit(w1)) tapAt(res, frame#cursor, w1) else w1;
        let w3 = if (pressed(GameEngine.Key.F3)) World.toggleDiagnostics(w2) else w2;
        World.step(res, inputOf(frame, res, w3) |> quietWhile(World.isVolumeOpen(w3)), w3)

    /// 音量の窓が開いている間は歩かない（↑↓←→ を窓が使う）。
    def quietWhile(open: Bool, input: World.Input): World.Input =
        if (open) { drive = Walker.idle(), actions = Set.empty() } else input

    /// volume のキーで窓を開け閉めし、開いている間は ↑↓ で行・←→ で音量を動かす（窓の矢印は固定のキー）。
    def volumeKeys(frame: App.Frame, res: Res.Res, w: World.World): World.World =
        let pressed = key -> App.justPressed(key, frame);
        if (List.exists(pressed, KeysDoc.rec(res#keys)#volume)) World.toggleVolume(w)
        else if (not World.isVolumeOpen(w)) w
        else if (pressed(GameEngine.Key.Up)) World.moveVolumeFocus(-1, w)
        else if (pressed(GameEngine.Key.Down)) World.moveVolumeFocus(1, w)
        else if (pressed(GameEngine.Key.Left)) World.nudgeVolume(0.0 - AudioPrefs.stepSize(), w)
        else if (pressed(GameEngine.Key.Right)) World.nudgeVolume(AudioPrefs.stepSize(), w)
        else w

    /// マウスを放している時に cursor を押した: 音量の印・窓の物を押したらそれを、何も無い所ならキャプチャを始める。
    def pressAt(res: Res.Res, cursor: Vec2.Vec2, w: World.World): World.World =
        match pickAt(res, cursor, w) {
            case Some(World.Press.VolumeIcon)    => World.toggleVolume(w)
            case Some(World.Press.VolumeBar(c))  => World.setVolume(c, VolumeView.valueAt(cursor), w)
            case Some(World.Press.VolumePanel)   => w
            case Some(World.Press.VolumeOutside) => World.closeVolume(w)
            case _                               => World.setLooking(true, w)
        }

    /// cursor の下の押せる物。絵と同じ木（View.layers）から描く順の手前で選ぶ —— 窓の奥には届かない。
    def pickAt(res: Res.Res, cursor: Vec2.Vec2, w: World.World): Option[World.Press] =
        let ctx = App.pickCtx({ x = World.width(), y = World.height() });
        SortingLayer.pickFrom(cursor, View.layers(ctx, View.inputOf(res, w)))

    /// 終了の確認の窓が出ている時に cursor を押した。
    def tapAt(res: Res.Res, cursor: Vec2.Vec2, w: World.World): World.World =
        match pickAt(res, cursor, w) {
            case Some(World.Press.QuitYes) => World.answerQuit(true, w)
            case Some(World.Press.QuitNo)  => World.answerQuit(false, w)
            case _                         => w
        }

    // ── Doc の読み込み・読み直し（watchFile / F1） ──

    /// 起動時と描き出しが同じ形で読む Doc の束と舞台。区切りごとに進み具合を知らせる
    /// （実機は起動画面が進む・描き出しとテストは LoadProgress.runNoop で捨てる）。
    pub def loadDocs(): Res.Docs \ Fs.FileRead + IO + LoadProgress =
        LoadProgress.report("reading docs...", 0, 0);
        let stage = StageDoc.load(StageDoc.path());
        let people = PeopleDoc.load(PeopleDoc.path());
        let limits = { baseColor = PeopleDoc.rec(people)#textureMax#baseColor, normal = PeopleDoc.rec(people)#textureMax#normal };
        { sample = SampleDoc.load(SampleDoc.path()), inspect = InspectDoc.load(InspectDoc.path()), keys = KeysDoc.load(KeysDoc.path()),
          theme = ThemeDoc.load(ThemeDoc.path()), sprites = PxSpriteDoc.load(World.spritePath()),
          walk = WalkDoc.load(WalkDoc.path()), look = LookDoc.load(LookDoc.path()), lights = LightsDoc.load(LightsDoc.path()),
          sound = SoundDoc.load(SoundDoc.path()), tour = TourDoc.load(TourDoc.path()), rooms = RoomsDoc.load(RoomsDoc.path()),
          people = people, stage = Stage.load(stage), residents = People.load(StageDoc.rec(stage)#dir, limits),
          prefs = AudioPrefs.load(AudioPrefs.path()) }

    def reloadSample(res: Res.Res): Res.Res \ Fs.FileRead = Res.withSample(SampleDoc.load(SampleDoc.path()), res)

    def reloadInspect(res: Res.Res): Res.Res \ Fs.FileRead = Res.withInspect(InspectDoc.load(InspectDoc.path()), res)

    def reloadKeys(res: Res.Res): Res.Res \ Fs.FileRead = Res.withKeys(KeysDoc.load(KeysDoc.path()), res)

    def reloadTheme(res: Res.Res): Res.Res \ Fs.FileRead =
        Res.withTheme(ThemeDoc.load(ThemeDoc.path()), PxSpriteDoc.load(World.spritePath()), res)

    def reloadSprites(res: Res.Res): Res.Res \ Fs.FileRead = Res.withSprites(PxSpriteDoc.load(World.spritePath()), res)

    def reloadWalk(res: Res.Res): Res.Res \ Fs.FileRead = Res.withWalk(WalkDoc.load(WalkDoc.path()), res)

    def reloadLook(res: Res.Res): Res.Res \ Fs.FileRead = Res.withLook(LookDoc.load(LookDoc.path()), res)

    def reloadLights(res: Res.Res): Res.Res \ Fs.FileRead = Res.withLights(LightsDoc.load(LightsDoc.path()), res)

    def reloadSound(res: Res.Res): Res.Res \ Fs.FileRead = Res.withSound(SoundDoc.load(SoundDoc.path()), res)

    def reloadTour(res: Res.Res): Res.Res \ Fs.FileRead = Res.withTour(TourDoc.load(TourDoc.path()), res)

    def reloadRooms(res: Res.Res): Res.Res \ Fs.FileRead = Res.withRooms(RoomsDoc.load(RoomsDoc.path()), res)

    def reloadPeople(res: Res.Res): Res.Res \ Fs.FileRead = Res.withPeople(PeopleDoc.load(PeopleDoc.path()), res)

    /// Doc の一覧表(DocTable)。watchFile(保存即反映)・F1 の一括リロード・Studio へ名乗る「表示中」の 3 つは、どれもこの 1 枚から導出する。
    /// docId は project.json の editor.resources[] の id と同じ物。舞台の読み方（stage.kind.json）は IO が要るので載せない（起動の時だけ読む）。
    pub def docTable(): List[DocTable.Entry[Resources.With[Res.Res, World.World]]] =
        let unchanged = (_, w) -> w;
        Resources.reloadRow("sample", SampleDoc.path(), reloadSample, unchanged)
            :: Resources.reloadRow("inspect", InspectDoc.path(), reloadInspect, unchanged)
            :: Resources.reloadRow("keys", KeysDoc.path(), reloadKeys, unchanged)
            :: Resources.reloadRow("theme", ThemeDoc.path(), reloadTheme, unchanged)
            :: Resources.reloadRow("sprite", World.spritePath(), reloadSprites, unchanged)
            :: Resources.reloadRow("walk", WalkDoc.path(), reloadWalk, unchanged)
            :: Resources.reloadRow("look", LookDoc.path(), reloadLook, unchanged)
            :: Resources.reloadRow("lights", LightsDoc.path(), reloadLights, unchanged)
            :: Resources.reloadRow("sound", SoundDoc.path(), reloadSound, unchanged)
            :: Resources.reloadRow("tour", TourDoc.path(), reloadTour, unchanged)
            :: Resources.reloadRow("rooms", RoomsDoc.path(), reloadRooms, unchanged)
            :: Resources.reloadRow("people", PeopleDoc.path(), reloadPeople, unchanged)
            :: Nil
}
