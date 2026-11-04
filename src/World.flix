// World — 遊びの状態そのものと、次の状態を作る規則（すべて純粋）。
// Doc と舞台（形・絵・当たり判定）は Res が持ち、World は持たない（読む口は res を受ける）。
//
// ── 場面 ──
// Loading = 読み込みの幕（幕の裏で舞台の部品を 1 コマに 1 つずつ GPU へ上げる。済んだら幕を薄めて遊びへ）。
// Play    = 一人称で歩いている。道筋の自動の操縦（Pilot）が付いていれば、キーの代わりにそれが歩く。
// 体・玄関の扉・手の灯りの 1 コマは PlayStep（自動の操縦とテストも同じ物を通る）。
// 歩く中身（Session）は両方の場面が持つ（幕の裏で描く場面も、歩き始める所から見る）。
mod World {

    use fge::{Clock, CollisionShape3d, Num}

    /// 押した瞬間に効く操作（同じコマに幾つでも重なる）。
    pub enum Action with Eq, Order, ToString {
        case ToggleLight       // 手の灯りを点け消しする
        case ToggleColliders   // 当たり判定の表示を切り替える
        case Interact          // 見ている玄関の扉を開け閉めする・見ている物を調べる（E）
    }

    /// このフレームの入力: 歩き方（Walker.Drive）と、このコマに押した操作。
    pub type alias Input = { drive = Walker.Drive, actions = Set[Action] }

    /// このコマに a を押したか。
    def isPressed(a: Action, input: Input): Bool = Set.memberOf(a, input#actions)

    /// 当たり判定の箱を重ねて描くか。
    pub enum ColliderView with Eq, ToString {
        case Shown
        case Hidden
    }

    /// マウスの視点。Captured = マウスを窓にキャプチャして視点を回している。
    pub enum Look with Eq, ToString {
        case Captured
        case Released
    }

    /// F3 の診断の表示。
    pub enum DiagnosticsView with Eq, ToString {
        case Shown
        case Hidden
    }

    /// 階段ですれ違う人。Waiting = まだ歩き出していない・Walking(origin) = 歩いている（動きの秒 = 遊びの時計の秒 − origin）・
    /// Gone = 歩き去って消えた（もう出ない）。
    pub enum Stairs with Eq, ToString {
        case Waiting
        case Walking(Float64)
        case Gone
    }

    /// 終了の確認。Esc か窓の閉じるボタンで Asking（確認の窓を出し、歩けない）、
    /// はいで Confirmed（Main の App.quitWhen がこれを見て閉じる）、いいえで Playing へ戻る。
    pub enum Quit with Eq, ToString {
        case Playing
        case Asking
        case Confirmed
    }

    /// マウスで押せる物（View が描く木に ZStack.hit で積み、Controls が SortingLayer.pickFrom で引く）。
    pub enum Press with Eq, ToString {
        case QuitYes   // 終了の確認の窓の中（Enter と同じ）
        case QuitNo    // 窓の外（Esc と同じ）
        case VolumeIcon                      // 隅のスピーカーの印（音量の窓を開け閉めする）
        case VolumeBar(AudioPrefs.Channel)   // 音量の窓の中のバー（押した所の値にする）
        case VolumePanel                     // 音量の窓の中の、バーの無い所（何もしない）
        case VolumeOutside                   // 音量の窓の外（窓を閉じる）
    }

    /// 歩いている間の中身: 体・手の灯り・当たり判定の箱を重ねて描くか・自動の操縦（None なら手で歩く）・
    /// 階段の人・マウスの視点・F3 の診断を出すかと、前のコマの診断。
    pub type alias SessionRec = {
        walker = Walker.Walker,
        // 玄関の扉の状態（部屋の番号ごと）。
        doors = Map[String, Doors.State],
        light = PlayStep.Flashlight,
        colliders = ColliderView,
        // 縦の画角を WalkDoc から替える時（静止画の構図を撮る時。None なら WalkDoc の fovY）。
        fov = Option[Float64],
        pilot = Option[Pilot.State],
        stairs = Stairs,
        look = Look,
        diagnosticsView = DiagnosticsView,
        // 遊ぶ人が決めた音量と、それを変える窓。
        audio = AudioPrefs.Prefs,
        volume = AudioPrefs.Menu,
        // 最後に E で調べた物の文言と時刻（出しておく秒は InspectDoc）。
        seen = Option[Inspect.Seen]
    }

    /// 歩いている間の中身。作るのは World の中だけ。読む口は sessionOf・書く口は mapSession。
    enum SessionOf(SessionRec)

    pub type alias Session = SessionOf

    /// 読み込みの幕: 何番目の部品まで GPU へ上げたか（1 から数える）と、済んでから薄めた秒（負 = まだ済んでいない）。
    pub type alias LoadRec = { step = Int32, fade = Float64 }

    /// どの画面か。その画面だけが持つ値を payload に持つ。
    pub enum Screen {
        case Loading(LoadRec, Session)
        case Play(Session)
    }

    /// 遊びの状態。play = 遊びの時計（歩く・点滅・羽虫・粒がこれを見る。終了の確認の間は止まる）。
    pub type alias World = {
        play = Clock.Clock[PlayClock.Play],
        screen = Screen,
        quit = Quit
    }

    // ── 盤の寸法（design 480×270。project.json と同じ値） ──

    pub def width(): Float64 = 480.0
    pub def height(): Float64 = 270.0

    pub def spritePath(): String = "assets/night_apartment.sprite.json"

    /// 幕を薄める秒。
    pub def fadeSeconds(): Float64 = 0.8

    /// 歩き始める体（WalkDoc の start に立ち、足元を床に合わせる）。
    def startWalker(res: Res.Res): Walker.Walker =
        let walk = WalkDoc.rec(res#walk);
        Walker.settle(res#collision, walk, Walker.standing(walk#start#x, 0.0, walk#start#z, walk#start#yaw))

    def freshSession(res: Res.Res): Session =
        SessionOf.SessionOf({ walker = startWalker(res), doors = Doors.initialAll(res#stage#rooms), light = PlayStep.flashlightOf(LightsDoc.rec(res#lights)#flashlight#startOn),
                              colliders = ColliderView.Hidden, fov = None, pilot = None,
                              stairs = Stairs.Waiting, look = Look.Released, diagnosticsView = DiagnosticsView.Hidden,
                              audio = res#prefs, volume = AudioPrefs.closedMenu(), seen = None })

    /// 遊びから始める状態（描き出し・テスト・flow）。
    pub def initial(res: Res.Res): World =
        { play = Clock.start(), screen = Screen.Play(freshSession(res)), quit = Quit.Playing }

    /// 読み込みの幕から始める状態（実機の起動）。
    pub def loading(res: Res.Res): World =
        { play = Clock.start(), screen = Screen.Loading({ step = 0, fade = -1.0 }, freshSession(res)), quit = Quit.Playing }

    def rec(s: Session): SessionRec = match s { case SessionOf.SessionOf(r) => r }

    /// 歩いている間の中身。
    def sessionOf(w: World): SessionRec = match w#screen {
        case Screen.Loading(_, s) => rec(s)
        case Screen.Play(s)       => rec(s)
    }

    def mapSession(f: SessionRec -> SessionRec, w: World): World = match w#screen {
        case Screen.Loading(l, s) => { screen = Screen.Loading(l, SessionOf.SessionOf(f(rec(s)))) | w }
        case Screen.Play(s)       => { screen = Screen.Play(SessionOf.SessionOf(f(rec(s)))) | w }
    }

    /// 読み込みの幕（遊んでいる間は None）。
    pub def loadingOf(w: World): Option[LoadRec] = match w#screen {
        case Screen.Loading(l, _) => Some(l)
        case Screen.Play(_)       => None
    }

    /// 読み込みの幕の区切りの数: 部品ごとに 1 つ＋場面全部と住人全部を 1 回。
    pub def loadSteps(res: Res.Res): Int32 = Res.partCount(res) + 1

    /// 今の体。
    pub def walkerOf(w: World): Walker.Walker = sessionOf(w)#walker

    /// 体を置き直す（始まり・描き出しの場面）。足元は、高さ y の近く（段の高さより上から下へ）の床に合わせる。
    pub def placeWalker(res: Res.Res, at: { x = Float64, y = Float64, z = Float64 }, yawDeg: Float64, pitchDeg: Float64, w: World): World =
        let walk = WalkDoc.rec(res#walk);
        let placed = Walker.settle(res#collision, walk, Walker.standing(at#x, at#y, at#z, yawDeg));
        mapSession(s -> { walker = { pitch = pitchDeg * Num.pi() / 180.0 | placed } | s }, w)

    /// 縦の画角を替える（静止画の構図。None で WalkDoc の fovY に戻す）。
    pub def withFov(fov: Option[Float64], w: World): World = mapSession(s -> { fov = fov | s }, w)

    /// 縦の画角（度）。
    pub def fovOf(res: Res.Res, w: World): Float64 = sessionOf(w)#fov |> Option.getWithDefault(WalkDoc.rec(res#walk)#fovY)

    /// 道筋の自動の操縦を付けて、道筋の始まりに立たせる。
    pub def withPilot(res: Res.Res, w: World): World =
        let tour = TourDoc.rec(res#tour);
        placeWalker(res, { x = tour#startX, y = 0.0, z = tour#startZ }, tour#startYaw, 0.0, w) |> mapSession(s -> { pilot = Some(Pilot.start()) | s })

    /// 道筋の名前の点に立たせ、その次の点から自動の操縦で歩かせる（y = その点のおおよその高さ）。名前が無ければ Err。
    pub def withPilotAfter(res: Res.Res, name: String, y: Float64, w: World): Result[String, World] =
        let tour = TourDoc.rec(res#tour);
        let point = tour#points |> List.find(p -> p#name == name);
        match (point, Pilot.startAfter(tour, name)) {
            case (Some(p), Some(state)) =>
                Ok(placeWalker(res, { x = p#x, y = y, z = p#z }, p#lookYaw |> Option.getWithDefault(0.0), p#lookPitch, w)
                    |> mapSession(s -> { pilot = Some(state), light = PlayStep.applyCue(p#light, s#light) | s }))
            case _ => Err("道筋に ${name} という点が無い")
        }

    /// 自動の操縦が向かっている点の名前（付いていない・歩き終えたら空）。
    pub def pilotPoint(res: Res.Res, w: World): String =
        sessionOf(w)#pilot |> Option.map(Pilot.pointName(TourDoc.rec(res#tour))) |> Option.getWithDefault("")

    /// 玄関の扉の状態（部屋の番号ごと）。
    pub def doorsOf(w: World): Map[String, Doors.State] = sessionOf(w)#doors

    /// 部屋の扉の今の角（度）。
    pub def doorAngle(room: Rooms.Room, w: World): Float64 = Doors.angleOf(doorsOf(w), room)

    /// 自動の操縦が道筋を歩き終えたか（付いていなければ false）。
    pub def isTourDone(res: Res.Res, w: World): Bool =
        sessionOf(w)#pilot |> Option.exists(Pilot.isDone(TourDoc.rec(res#tour)))

    /// 今出しておく、E で調べた物の文言と、出してからの秒（出しておく秒を過ぎたら None）。
    pub def captionOf(res: Res.Res, w: World): Option[(String, Float64)] =
        Inspect.showing(InspectDoc.rec(res#inspect), Clock.nowOf(w#play), sessionOf(w)#seen)

    /// 手の灯りが点いているか。
    pub def isLightOn(w: World): Bool = PlayStep.isOn(sessionOf(w)#light)

    /// マウスを窓にキャプチャして視点を回しているか（App.withMouseCapture がこれを見て当てる）。
    pub def isLooking(w: World): Bool = sessionOf(w)#look == Look.Captured

    /// キャプチャを始める・放す。終了の確認の窓が出ている間はキャプチャしない（窓の中を押せない）。
    /// キャプチャを始めると音量の窓は閉じる（視点を回している間は隅の印ごと出さない）。
    pub def setLooking(on: Bool, w: World): World =
        mapSession(s -> { look = if (on and w#quit == Quit.Playing) Look.Captured else Look.Released, volume = if (on) { open = false | s#volume } else s#volume | s }, w)

    // ── 音量 ──

    /// 遊ぶ人が決めた音量。
    pub def prefsOf(w: World): AudioPrefs.Prefs = sessionOf(w)#audio

    /// 音量の窓。
    pub def volumeMenuOf(w: World): AudioPrefs.Menu = sessionOf(w)#volume

    /// 隅のスピーカーの印を出すか: 遊んでいて、マウスを放していて、終了の確認が出ていない時だけ。
    pub def showsVolumeIcon(w: World): Bool =
        Option.isEmpty(loadingOf(w)) and not isLooking(w) and w#quit == Quit.Playing

    /// 音量の窓が開いているか（印を出していない時は閉じている扱い）。
    pub def isVolumeOpen(w: World): Bool = showsVolumeIcon(w) and volumeMenuOf(w)#open

    /// 音量の窓を開け閉めする（印を出していない時は何もしない）。
    pub def toggleVolume(w: World): World =
        if (not showsVolumeIcon(w)) w else mapSession(s -> { volume = { open = not s#volume#open | s#volume } | s }, w)

    pub def closeVolume(w: World): World = mapSession(s -> { volume = { open = false | s#volume } | s }, w)

    /// 音量を v に（窓のバーを押した時）。キーで動かす行もその行へ。
    pub def setVolume(c: AudioPrefs.Channel, v: Float64, w: World): World =
        mapSession(s -> { audio = AudioPrefs.set(c, v, s#audio), volume = { focus = c | s#volume } | s }, w)

    /// キーで選んでいる行の音量を d だけ動かす。
    pub def nudgeVolume(d: Float64, w: World): World =
        mapSession(s -> { audio = AudioPrefs.nudge(s#volume#focus, d, s#audio) | s }, w)

    /// キーで動かす行を上下に。
    pub def moveVolumeFocus(d: Int32, w: World): World = mapSession(s -> { volume = AudioPrefs.moveFocus(d, s#volume) | s }, w)

    /// F3 の診断の表示を切り替える。
    pub def toggleDiagnostics(w: World): World = mapSession(s -> { diagnosticsView = toggledDiagnostics(s#diagnosticsView) | s }, w)

    def toggledDiagnostics(d: DiagnosticsView): DiagnosticsView = match d {
        case DiagnosticsView.Shown  => DiagnosticsView.Hidden
        case DiagnosticsView.Hidden => DiagnosticsView.Shown
    }

    /// F3 の診断を出しているか。
    pub def showsDiagnostics(w: World): Bool = sessionOf(w)#diagnosticsView == DiagnosticsView.Shown

    /// 階段の人。
    pub def stairsOf(w: World): Stairs = sessionOf(w)#stairs

    /// 階段の人の動きの秒（歩いていなければ None）。
    pub def stairsTime(w: World): Option[Float64] = match sessionOf(w)#stairs {
        case Stairs.Walking(origin) => Some(seconds(w) - origin)
        case _                      => None
    }

    /// 階段の人を動きの秒 t の所から歩かせる（描き出しの場面・見比べの絵）。
    pub def withStairsAt(t: Float64, w: World): World = mapSession(s -> { stairs = Stairs.Walking(seconds(w) - t) | s }, w)

    /// 遊びの時計を秒 t だけ進めた状態（描き出しの場面で、住人の動きを決まった秒にそろえる）。
    pub def advancedBy(t: Float64, w: World): World =
        { play = Clock.advance(Clock.paceOf(Clock.Run.Running), t, w#play) | w }

    /// 遊びの時計の今（秒。点滅・羽虫・粒の周期の関数に渡す）。
    pub def seconds(w: World): Float64 = Clock.secondsOf(Clock.nowOf(w#play))

    /// 遊びの時計の進み方: 終了の確認の窓が出ている間は止める（App.addClock が毎フレーム 1 回だけ進める）。
    pub def paceOf(w: World): Clock.Pace[PlayClock.Play, PlayClock.Halt] =
        Clock.paceOf(if (isPaused(w)) Clock.Run.Paused(PlayClock.Halt.AskingQuit) else Clock.Run.Running)

    /// 遊びの時計を止めているか（終了の確認の窓が出ている間）。
    pub def isPaused(w: World): Bool = w#quit == Quit.Asking

    /// 入力から次の状態を作る（秒は遊びの時計がこのコマに進んだ分）。
    /// 終了の確認の窓が出ている間と読み込みの幕の間は歩かない。
    pub def step(res: Res.Res, input: Input, w: World): World =
        match w#screen {
            case Screen.Loading(l, s) => { screen = stepLoading(res, Clock.dtOf(w#play), l, s) | w }
            case Screen.Play(_) =>
                if (w#quit != Quit.Playing) w
                else mapSession(stepSession(res, input, w#play), w)
        }

    /// 遊びの時計を dt 秒ずつ進めながら、同じ入力で n コマ進めた状態（テストが階段の人とカプセルを見る）。
    pub def stepTimes(res: Res.Res, input: Input, dt: Float64, n: Int32, w: World): World =
        List.range(0, n) |> List.foldLeft((acc, _) -> step(res, input, advancedBy(dt, acc)), w)

    /// 幕の区切りを 1 つ進める（済んだら薄め、薄め切ったら遊びへ）。
    def stepLoading(res: Res.Res, dt: Float64, l: LoadRec, s: Session): Screen =
        if (l#step < loadSteps(res)) Screen.Loading({ step = l#step + 1 | l }, s)
        else if (l#fade < 0.0) Screen.Loading({ fade = 0.0 | l }, s)
        else if (l#fade + dt >= fadeSeconds()) Screen.Play(s)
        else Screen.Loading({ fade = l#fade + dt | l }, s)

    /// 歩く中身を 1 コマ進める（自動の操縦が付いていればそれが歩く）。
    def stepSession(res: Res.Res, input: Input, clock: Clock.Clock[PlayClock.Play], s: SessionRec): SessionRec =
        let (act, pilot) = match s#pilot {
            case Some(p) =>
                let (a, next) = Pilot.drive(TourDoc.rec(res#tour), s#walker, clock, p);
                (a, Some(next))
            case None => ({ drive = input#drive, press = isPressed(Action.Interact, input), light = toggleCue(isPressed(Action.ToggleLight, input), s#light) }, None)
        };
        let now = Clock.secondsOf(Clock.nowOf(clock));
        let body = PlayStep.stepWith(Res.playEnv(res), moversOf(res, now, s#stairs), act, clock, { walker = s#walker, doors = s#doors, light = s#light, seen = s#seen });
        { walker = body#walker, doors = body#doors, light = body#light, seen = body#seen, pilot = pilot,
          stairs = nextStairs(res, now, body#walker, s#stairs),
          colliders = if (isPressed(Action.ToggleColliders, input)) toggledColliders(s#colliders) else s#colliders | s }

    /// 手の灯りを点け消しするキーを押したコマは今の逆を指示し、押していなければそのまま。
    def toggleCue(pressed: Bool, f: PlayStep.Flashlight): PlayStep.LightCue =
        if (not pressed) PlayStep.LightCue.Keep
        else if (PlayStep.isOn(f)) PlayStep.LightCue.TurnOff
        else PlayStep.LightCue.TurnOn

    def toggledColliders(c: ColliderView): ColliderView = match c {
        case ColliderView.Shown  => ColliderView.Hidden
        case ColliderView.Hidden => ColliderView.Shown
    }

    /// 階段の人（manifest の root motion の人。書き出しに居なければ None）。
    def stairwalkerOf(res: Res.Res): Option[People.Entry] =
        res#residents |> List.map(p -> p#entry) |> List.find(e -> not People.isResident(e))

    /// 歩いている階段の人のカプセルの箱（歩いていなければ None。当たり判定の表示とテストが読む）。
    pub def stairwalkerBox(res: Res.Res, w: World): Option[CollisionShape3d.Box3d] =
        moversOf(res, seconds(w), sessionOf(w)#stairs) |> List.head

    /// 動いている物のカプセルの箱（歩いている階段の人）。
    def moversOf(res: Res.Res, now: Float64, stairs: Stairs): List[CollisionShape3d.Box3d] = match stairs {
        case Stairs.Walking(origin) => stairwalkerOf(res) |> Option.map(e -> People.capsuleBox(e, People.pathAt(e, now - origin))) |> Option.toList
        case _                      => Nil
    }

    /// 階段の人の次の状態: 足元が歩き出す範囲に入ったら PeopleDoc の startS の所から歩き出し、動きの長さを過ぎたら消える。
    def nextStairs(res: Res.Res, now: Float64, w: Walker.Walker, stairs: Stairs): Stairs =
        let doc = PeopleDoc.rec(res#people)#stairs;
        match (stairs, stairwalkerOf(res)) {
            case (Stairs.Waiting, Some(_)) if People.isInTrigger(doc#trigger, w#x, w#feet, w#z) => Stairs.Walking(now - doc#startS)
            case (Stairs.Walking(origin), Some(e)) if now - origin >= e#duration => Stairs.Gone
            case _ => stairs
        }

    /// 当たり判定の箱を重ねて描くか。
    pub def showsColliders(w: World): Bool = sessionOf(w)#colliders == ColliderView.Shown

    // ── 終了の確認 ──

    /// Esc・閉じるボタン: 遊んでいる間なら確認の窓を出す。
    pub def askQuit(w: World): World =
        if (w#quit == Quit.Playing) mapSession(s -> { look = Look.Released | s }, { quit = Quit.Asking | w }) else w

    /// 確認の窓への答え（yes なら終わる・no なら遊びへ戻る）。窓が出ていないときは何もしない。
    pub def answerQuit(yes: Bool, w: World): World =
        if (w#quit != Quit.Asking) w
        else if (yes) { quit = Quit.Confirmed | w }
        else { quit = Quit.Playing | w }

    pub def isAskingQuit(w: World): Bool = w#quit == Quit.Asking

    pub def isQuitting(w: World): Bool = w#quit == Quit.Confirmed
}
