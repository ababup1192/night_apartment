// SceneRender — ゲーム画面を画面なしで PNG に生成する（スナップショットと、静止画の目標との見比べ用）。
// 実行: make render-all → gallery/*.png
//       make render SHOT=wide → debug/wide.png（1 枚だけ）
// 3D の場面と後処理の Pass は SoftRaster が CPU で塗る（実機の GPU と同じ式。GPU の絵は make stills）。
mod SceneRender {
    use fge::{
        App, Clock, Color, FontAtlas, GameEngine, HeadlessFont, HeadlessLoad, HeadlessRender,
        PxSpriteAtlas, Render, Vec2
    }

    import java.io.File

    pub def design(): Vec2.Vec2 = { x = World.width(), y = World.height() }

    pub def ttf(): String = "assets/Xolonium-Regular.ttf"

    pub def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): HeadlessRender.RenderConfig =
        { design = design(), scale = 2, background = bg,
          fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 960, frameH = 540 | HeadlessRender.defaults() }

    /// 描く元（実機の起動と同じ Controls.loadDocs から組む）。
    def loadRes(): Res.Res \ IO =
        Res.build(run { HeadlessLoad.handle(Controls.loadDocs) } with Fs.FileRead.runWithIO)

    /// 生成するときの遊びの時計の時刻（秒）。固定値なので、点滅も羽虫もこの時刻だけで決まる。
    def renderClock(): Clock.Clock[PlayClock.Play] = Clock.startAt(3.0)

    pub def all(): Unit \ IO = App.Headless.exitWith(allJob(App.Headless.requestFromProcess()))

    def allJob(_req: App.Headless.Request): Int32 \ IO =
        discard allShots();
        0

    /// 常駐（App.Headless.serveJobs）が /run で流す入口の束。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.job("SceneRender", "one", req -> oneJob(req)) ::
        App.Headless.job("SceneRender", "all", req -> allJob(req)) :: Nil

    /// 静止画の構図（Blender の静止画のカメラを engine の座標へ写した物）: 足元 x・おおよその高さ y・z・向き・見下ろす角（度）・縦の画角（度）。
    pub type alias Shot = { x = Float64, y = Float64, z = Float64, yaw = Float64, pitch = Float64, fovY = Float64 }

    /// 静止画の目標（renders/CAM_*_final.png）と同じ構図。
    def shotOf(name: String): Option[Shot] = match name {
        case "wide"     => Some({ x = 4.5, y = 0.0, z = 12.5, yaw = 228.5, pitch = -9.0, fovY = 58.7 })
        case "vending"  => Some({ x = -0.75, y = 0.0, z = 8.9, yaw = 211.9, pitch = 2.0, fovY = 35.0 })
        case "corridor" => Some({ x = -16.6, y = 3.1, z = 0.7, yaw = 91.5, pitch = -6.0, fovY = 53.7 })
        case "stairs"   => Some({ x = -17.8, y = 0.3, z = 0.7, yaw = 199.2, pitch = -22.0, fovY = 53.7 })
        case "inspect"  => Some({ x = -2.3, y = 0.0, z = 7.6, yaw = 195.0, pitch = 8.0, fovY = 58.0 })
        case _          => None
    }

    /// 描き出せる場面の名前（この並びが source of truth。Makefile の SHOTS と assets/*.scenes.json もそろえる）。
    def shotNames(): List[String] = "wide" :: "vending" :: "corridor" :: "stairs" :: "inspect" :: "loading" :: "quit" :: "volume" :: Nil

    def sceneOf(res: Res.Res, name: String, w0: World.World): Option[World.World] =
        let at = (s: Shot) -> World.placeWalker(res, { x = s#x, y = s#y, z = s#z }, s#yaw, s#pitch, w0);
        match name {
            case "loading" => Some({ screen = World.loading(res)#screen | w0 })
            case "inspect" => shotOf(name) |> Option.map(at) |> Option.map(World.step(res, { drive = Walker.idle(), actions = Set#{ World.Action.Interact } }))
                                  |> Option.map(World.stepTimes(res, { drive = Walker.idle(), actions = Set.empty() }, 1.0 / 60.0, captionFrames(res)))
            case "quit"    => shotOf("vending") |> Option.map(at) |> Option.map(World.askQuit)
            case "volume"  => shotOf("corridor") |> Option.map(at) |> Option.map(World.toggleVolume)
                                  |> Option.map(World.setVolume(AudioPrefs.Channel.Effects, 0.0))
                                  |> Option.map(World.setVolume(AudioPrefs.Channel.Ambience, 0.45))
            case _         => shotOf(name) |> Option.map(at)
        }

    /// 調べた文言が出そろってから、消え始める前のコマ（60 コマ/秒）: 一番長い文言を出し切る秒 + 0.3 秒（出しておく秒の 6 割まで）。
    def captionFrames(res: Res.Res): Int32 =
        let doc = InspectDoc.rec(res#inspect);
        let longest = doc#things |> List.map(t -> String.length(t#text)) |> List.foldLeft(Int32.max, 0);
        let seconds = Float64.min(doc#showSeconds * 0.6, Int32.toFloat64(longest) / Float64.max(1.0, doc#charsPerSecond) + 0.3);
        Float64.tryToInt32(Float64.ceil(seconds * 60.0)) |> Option.getWithDefault(1)

    pub def allShots(): List[String] \ IO = shotsInto("gallery", _ -> true)

    pub def one(): Unit \ IO = App.Headless.exitWith(oneJob(App.Headless.requestFromProcess()))

    def oneJob(req: App.Headless.Request): Int32 \ IO =
        let wanted = Map.getWithDefault("SHOT", "", App.Headless.envOf(req)) |> String.splitOn(substr = " ")
            |> List.map(String.trim) |> List.filter(n -> not String.isEmpty(n));
        let known = List.toSet(shotNames());
        let unknown = wanted |> List.filter(n -> not Set.memberOf(n, known));
        if (List.isEmpty(wanted) or not List.isEmpty(unknown)) {
            println("[render] 描けない名前です: ${List.join(" ", unknown)}");
            println("[render] SHOT=<場面> に使えるのは: ${List.join(" ", shotNames())}");
            1
        } else {
            let picked = List.toSet(wanted);
            discard shotsInto("debug", n -> Set.memberOf(n, picked));
            0
        }

    def shotsInto(outDir: String, keep: String -> Bool): List[String] \ IO =
        discard (new File(outDir)).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let res = loadRes();
        let (cfg, texInfo) = withAtlasOf(cfgOf(outDir, atlas, ThemeDoc.rec(res#theme)#bg), res);
        let ctx = App.viewCtxOf(atlas, design());
        shotNames() |> List.filter(keep) |> List.filterMap(name ->
            sceneOf(res, name, { play = renderClock() | World.initial(res) }) |> Option.map(w -> shoot(cfg, texInfo, ctx, res, w, name)))

    /// 実機が GPU へ上げるのと同じアトラスの画素を PNG に落とし、そこから貼れる cfg と texInfo を返す。
    pub def withAtlasOf(cfg: HeadlessRender.RenderConfig, res: Res.Res):
            (HeadlessRender.RenderConfig, String -> Option[GameEngine.TextureInfo]) \ IO =
        let images = PxSpriteAtlas.asImages({ texture = Res.atlasName(), baked = res#atlas } :: Nil);
        ({ texturePath = HeadlessRender.imagePngs("debug", images) | cfg }, HeadlessRender.imageTextureInfo(images))

    /// 1 場面を PNG に生成する（構図の画角があれば場面の画角を替える）。
    def shoot(cfg: HeadlessRender.RenderConfig, texInfo: String -> Option[GameEngine.TextureInfo],
              ctx: App.ViewCtx, res: Res.Res, w: World.World, name: String): String \ IO =
        // 音量の窓の場面だけは、遊ぶ人に見える印と窓を描く（ほかの場面は動画と同じく印を撮らない）。
        let input0 = if (name == "volume") View.inputOf(res, w) else View.inputForCapture(res, w);
        let input = shotOf(name) |> Option.map(s -> { stage = { fovY = s#fovY | input0#stage } | input0 }) |> Option.getWithDefault(input0);
        let prepared = Render.passSpecsOf(texInfo, View.passPlanOf(input));
        prepared#issues |> List.forEach(i -> println("[render] Pass の計画: ${i}"));
        let items = View.frameOf(ctx, input);
        let surfaces = Render.shaderSurfaces(items);
        let (drawables, polygons) = Render.drawWith(texInfo, Render.withoutShaders(items));
        HeadlessRender.renderPngWithPasses(cfg, prepared#specs, drawables, polygons, surfaces, name);
        let path = "${cfg#outDir}/${name}.png";
        println("rendered: ${path}");
        path
}
