// E2e — e2e/<名前>.flow の語彙（App.withFlow の表と指紋）と、画面なしで流す入口。
// flow の書き方は engine の engine_world/src/Flow.flix 冒頭。名前の一覧は流すたびに e2e/vocab.json へ書き出す。
//   make flow FLOW=e2e/walk.flow   画面なしで最後まで流す
mod E2e {
    use fge::{App, Flow, InputMap, LoadProgress, Resources}
    use fge::GameEngine.Key

    /// make flow（bin/fge flow run|check）が流す入口。
    pub def play(): Unit \ IO = App.Headless.exitWith(playJob(App.Headless.requestFromProcess()))

    def playJob(req: App.Headless.Request): Int32 \ IO =
        run { Flow.Cli.mainOf(Game.app(LoadProgress.runNoop(Controls.loadDocs)), App.Headless.envOf(req)) } with Fs.FileRead.runWithIO with Fs.FileWrite.runWithIO

    /// 語彙 e2e/vocab.json だけを書く入口（bin/headless-run が jar を作った時に流す・make flow-vocab）。
    pub def vocab(): Unit \ IO = App.Headless.exitWith(vocabJob(App.Headless.requestFromProcess()))

    def vocabJob(req: App.Headless.Request): Int32 \ IO =
        run { Flow.Cli.vocabMainOf(Game.app(LoadProgress.runNoop(Controls.loadDocs)), App.Headless.envOf(req)) } with Fs.FileRead.runWithIO with Fs.FileWrite.runWithIO

    /// 常駐（App.Headless.serveJobs）が /run で流す E2e の入口の束。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.job("E2e", "play", req -> playJob(req)) ::
        App.Headless.job("E2e", "vocab", req -> vocabJob(req)) :: Nil

    /// 役の名前 → キー（表の先頭のキーを押す。player.keys.json の既定と同じ）。
    def roles(): InputMap.Table[String] =
        (Key.W, "forward") :: (Key.S, "back") :: (Key.A, "left") :: (Key.D, "right") ::
        (Key.Left, "turnleft") :: (Key.Right, "turnright") :: (Key.LeftShift, "run") :: (Key.F, "light") :: (Key.E, "door") ::
        (Key.C, "colliders") :: (Key.Enter, "confirm") :: (Key.Escape, "cancel") :: Nil

    def walkerNum(pick: Walker.Walker -> Float64, w: World.World): Float64 = pick(World.walkerOf(w))

    /// flow の表: 役と問い。
    pub def table(): Flow.Table[Resources.With[Res.Res, World.World]] =
        { roles = _ -> roles(),
          probes =
              { name = "x", doc = "足元の x（m）", read = Flow.Probe.Num(Resources.read((_, w) -> walkerNum(b -> b#x, w))) } ::
              { name = "z", doc = "足元の z（m）", read = Flow.Probe.Num(Resources.read((_, w) -> walkerNum(b -> b#z, w))) } ::
              { name = "feet", doc = "足元の高さ（m。1 階の外廊下 0.3・2 階 3.1）", read = Flow.Probe.Num(Resources.read((_, w) -> walkerNum(b -> b#feet, w))) } ::
              { name = "toured", doc = "自動の操縦が道筋を歩き終えたか", read = Flow.Probe.Flag(Resources.read((res, w) -> World.isTourDone(res, w))) } ::
              { name = "point", doc = "自動の操縦が向かっている道筋の点の名前（歩き終えたら空）", read = Flow.Probe.Text(Resources.read((res, w) -> World.pilotPoint(res, w))) } ::
              { name = "opendoors", doc = "閉じていない玄関の扉の数", read = Flow.Probe.Num(Resources.read((_, w) -> Int32.toFloat64(Map.count((_, s) -> not Doors.isClosed(s), World.doorsOf(w))))) } ::
              { name = "stairs", doc = "階段ですれ違う人（Waiting・Walking・Gone）", read = Flow.Probe.Text(Resources.read((_, w) -> stairsName(World.stairsOf(w)))) } ::
              { name = "looking", doc = "マウスをキャプチャして視点を回しているか", read = Flow.Probe.Flag(Resources.read((_, w) -> World.isLooking(w))) } ::
              { name = "loading", doc = "読み込みの幕が出ているか", read = Flow.Probe.Flag(Resources.read((_, w) -> Option.nonEmpty(World.loadingOf(w)))) } ::
              { name = "quit", doc = "終了の確認（Playing・Asking・Confirmed）", read = Flow.Probe.Text(Resources.read((_, w) -> "${w#quit}")) } :: Nil
          | Flow.emptyTable() }

    /// 階段の人の状態の名前（歩いている秒は落とす。flow の until が名前だけで待てる）。
    def stairsName(s: World.Stairs): String = match s {
        case World.Stairs.Waiting    => "Waiting"
        case World.Stairs.Walking(_) => "Walking"
        case World.Stairs.Gone       => "Gone"
    }

    /// 指紋の元（記録の再生が比べる）: 足元を cm に丸めた位置・足の着き方・終了の確認。
    pub def fingerprint(_res: Res.Res, w: World.World): String =
        let b = World.walkerOf(w);
        let cm = (v: Float64) -> Int32.toString(Float64.tryToInt32(Float64.round(v * 100.0)) |> Option.getWithDefault(0));
        "at=${cm(b#x)},${cm(b#feet)},${cm(b#z)}|${b#footing}|quit=${w#quit}"
}
