// View — World から「(置き場所, 見せたい物) のリスト」と、その前に描く Pass の計画への投影（純粋）。
//
// ── 画面の層（奥から手前へ）──
// 場面（Layer.Scene）: 一人称の夜のアパート（StageView。Pass の中で 3D の場面とブルームを組み、後処理の面 1 枚で画面へ）。
// 起動の読み込み中の幕（Layer.Loading）: LoadingView。幕の裏で、舞台の部品を 1 コマに 1 つずつ小さな Pass に描いて
//   GPU へ上げ（形と絵の段と面のプログラム）、最後に場面全部を 1 回描く。描いた Pass は誰も読まない。
// 終了の確認の窓（quitPrompt）は Layer.Prompt に置き、場面のどれよりも手前に出る。
mod View {

    use fge::{App, Color, FrameDiagnostics, Mat4, Mesh3d, RawDraw, Render, RenderTarget, Scene3d, SortingLayer, TextDraw, Vec2, Vec3, ZStack}
    use ZOrder.Layer

    /// 描くのに要る値。部品は World でなくこれを読む（lint/rules.flix の view-no-world）。
    pub type alias In = {
        stage = StageView.In,
        loading = Option[LoadingView.In],
        warm = Render.PassPlan,
        theme = ThemeDoc.Doc,
        askingQuit = Bool,
        quitPrompt = String,
        // マウスをキャプチャしているか（画面の真ん中に小さな点を出す）・F3 の診断の行（出さない時は空）。
        looking = Bool,
        diagnostics = List[String],
        // 隅の音量の印と窓（マウスを放している時だけ。動画と静止画では None）。
        volume = Option[VolumeView.In]
    }

    /// 描く元と World から描くのに要る値だけを写す（View の中で World を読むのは入口の frame・passPlan とここだけ）。
    pub def inputOf(res: Res.Res, w: World.World): In =
        let t = World.seconds(w);
        let stage = stageIn(res, w, t);
        let loading = World.loadingOf(w) |> Option.map(l -> {
            let total = Int32.max(1, World.loadSteps(res));
            { t = t, progress = Int32.toFloat64(l#step) / Int32.toFloat64(total),
              alpha = if (l#fade < 0.0) 1.0 else 1.0 - smooth(l#fade / World.fadeSeconds()),
              label = SampleDoc.rec(res#sample)#loadingLabel }
        });
        { stage = stage, loading = loading,
          warm = World.loadingOf(w) |> Option.map(l -> warmPlan(res, stage, l#step - 1)) |> Option.getWithDefault(Render.passPlan(Nil)),
          theme = res#theme, askingQuit = World.isAskingQuit(w), quitPrompt = SampleDoc.rec(res#sample)#quitPrompt,
          looking = World.isLooking(w), diagnostics = World.diagnosticsOf(w) |> Option.map(FrameDiagnostics.summaryLines) |> Option.getWithDefault(Nil),
          volume = if (World.showsVolumeIcon(w)) Some({ prefs = World.prefsOf(w), menu = World.volumeMenuOf(w), theme = res#theme, t = t }) else None }

    /// 動画と静止画に撮る時の値（遊ぶ人のための音量の印は撮らない）。
    pub def inputForCapture(res: Res.Res, w: World.World): In = { volume = None | inputOf(res, w) }

    /// 一人称の場面の値。
    def stageIn(res: Res.Res, w: World.World, t: Float64): StageView.In =
        let walk = WalkDoc.rec(res#walk);
        let body = World.walkerOf(w);
        let eye = Vec3.v3(body#x, Walker.eyeY(walk, body), body#z);
        let rooms = res#stage#rooms;
        let doc = RoomsDoc.rec(res#rooms);
        let drawn = rooms |> List.filter(r -> Rooms.isDrawn(doc#draw, r, eye, body#yaw, World.doorAngle(r, w))) |> List.map(r -> r#id) |> List.toSet;
        let stairsT = World.stairsTime(w);
        let people = res#residents |> List.filterMap(p -> drawnAt(drawn, stairsT, t, p) |> Option.map(at -> (p, at)));
        { t = t, eye = eye, yaw = body#yaw, pitch = body#pitch, fovY = World.fovOf(res, w),
          look = LookDoc.rec(res#look), lights = LightsDoc.rec(res#lights), lightOn = World.isLightOn(w),
          placed = res#placed, drawnRooms = drawn,
          doorMatrices = rooms |> List.map(r -> (r#id, Doors.transformOf(r#door, World.doorAngle(r, w)))) |> List.toMap,
          roomLights = List.append(RoomLights.pointsOf(doc#light, t, drawn, rooms), peopleLights(res, drawn, people)),
          people = people |> List.flatMap(e -> People.instancesAt(fst(e), snd(e))),
          textures = res#textures, atlas = res#atlas,
          colliders = if (World.showsColliders(w))
                          Some({ boxes = res#colliderMesh,
                                 doors = ColliderMesh.boxesMesh(List.flatten(Doors.leafBoxes(rooms, World.doorsOf(w)) :: People.residentBoxes(res#residents |> List.map(p -> p#entry))
                                                                             :: Option.toList(World.stairwalkerBox(res, w)) :: Nil)),
                                 body = res#bodyMesh, feet = Vec3.v3(body#x, body#feet, body#z) })
                      else None }

    /// 住人を描くなら、その動きの秒: 部屋にいる人は部屋を描く時だけ（遊びの時計の秒 t）・階段の人は歩いている間だけ（stairsT）。
    def drawnAt(drawn: Set[String], stairsT: Option[Float64], t: Float64, p: People.Person): Option[Float64] =
        if (not People.isResident(p#entry)) stairsT
        else if (Set.memberOf(p#entry#room, drawn)) Some(t)
        else None

    /// 描く住人を照らす灯り（描く部屋の灯りと同じ名前の物は除く）。
    def peopleLights(res: Res.Res, drawn: Set[String], people: List[(People.Person, Float64)]): List[Scene3d.PointLight] =
        let skip = res#stage#rooms |> List.filter(r -> Set.memberOf(r#id, drawn)) |> List.flatMap(r -> r#lights |> List.map(l -> l#name)) |> List.toSet;
        people |> List.flatMap(e -> People.lightsOf(PeopleDoc.rec(res#people)#light, skip, fst(e)#entry))

    def smooth(x: Float64): Float64 = { let q = Float64.max(0.0, Float64.min(1.0, x)); q * q * (3.0 - 2.0 * q) }

    /// 読み込みの index 番目に GPU へ上げる物を描く Pass: 部品 1 つずつ（正面の少し離れた所から映す）→ 最後に場面全部と住人全部。
    /// WhyNot: 住人を 1 人ずつ別のコマにしない — 新しい形を上げるコマが 30 続くと、engine が「毎コマ形を作り直している」と知らせる。
    def warmPlan(res: Res.Res, stage: StageView.In, index: Int32): Render.PassPlan =
        let n = Res.partCount(res);
        let none = Render.passPlan(Nil);
        if (index < 0) none
        else if (index < n) List.nth(index, res#placed) |> Option.map(g -> warmPart(stage, g#items |> List.map(Stage.instanceOf(Map#{ Stage.gainParam() => 1.0 })))) |> Option.getWithDefault(none)
        else if (index == n) {
            let full = StageView.passPlan(stage);
            let people = warmPart(stage, res#residents |> List.flatMap(p -> People.instancesAt(p, 0.0)));
            { passes = List.append(full#passes, people#passes), targets = Map.union(full#targets, people#targets) }
        }
        else none

    /// 置いた物の束を小さな Pass に、形の囲みの正面から映す。
    def warmPart(stage: StageView.In, placed: List[Scene3d.Instance3d]): Render.PassPlan =
        let bounds = placed |> List.map(i -> { let f = Scene3d.instanceFieldsOf(i); Mesh3d.bounds(f#mesh) |> boundsIn(f#world) });
        let lo = bounds |> List.foldLeft((acc, b) -> Vec3.v3(Float64.min(acc#x, b#min#x), Float64.min(acc#y, b#min#y), Float64.min(acc#z, b#min#z)), Vec3.v3(1.0e9, 1.0e9, 1.0e9));
        let hi = bounds |> List.foldLeft((acc, b) -> Vec3.v3(Float64.max(acc#x, b#max#x), Float64.max(acc#y, b#max#y), Float64.max(acc#z, b#max#z)), Vec3.v3(-1.0e9, -1.0e9, -1.0e9));
        let c = Vec3.mul(Vec3.add(lo, hi), 0.5);
        let size = Float64.max(1.0, Vec3.length(Vec3.sub(hi, lo)));
        let camera = { eye = Vec3.v3(c#x, c#y, hi#z + size), yaw = Walker.pi(), pitch = 0.0, fovY = 1.2, near = 0.1, far = 4.0 * size };
        let scene = { instances = placed, textures = stage#textures
                      | Scene3d.scene(camera, { x = World.width() / 4.0, y = World.height() / 4.0 }) };
        let name = "warmPart";
        { passes = { name = name, clear = RenderTarget.LoadOp.Clear(Color.rgb(0.0, 0.0, 0.0)), items = Render.scene3d(Vec2.zero(), scene) :: Nil } :: Nil,
          targets = Map#{ name => RenderTarget.withHdr({ scale = 0.25 | RenderTarget.defaultDescriptor() }) } }

    /// 形の囲みを行列 m で動かした囲み（真ん中だけを動かす。回る物の囲みは粗くてよい — 映す向きを決めるだけ）。
    def boundsIn(m: Mat4.Mat4, b: { min = Vec3.Vec3, max = Vec3.Vec3 }): { min = Vec3.Vec3, max = Vec3.Vec3 } =
        let c = Mat4.apply(m, Vec3.mul(Vec3.add(b#min, b#max), 0.5));
        let h = Vec3.mul(Vec3.sub(b#max, b#min), 0.5);
        { min = Vec3.sub(c, h), max = Vec3.add(c, h) }

    pub def frame(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        frameOf(ctx, inputOf(res, w))

    /// 本編の描き物（描き出しと動画も同じ物を呼ぶ）。
    pub def frameOf(ctx: App.ViewCtx, w: In): List[Render.PlacedItem] =
        SortingLayer.compose(ctx, layers(ctx, w))

    /// 本編より先に描く Pass の計画（Main の App.withPassPlan と描き出しが呼ぶ）。
    pub def passPlan(res: Res.Res, w: World.World): Render.PassPlan =
        passPlanOf(inputOf(res, w))

    /// 下の場面が幕で隠れているか。
    def hidden(w: In): Bool = w#loading |> Option.exists(LoadingView.covers)

    /// 場面の Pass と、読み込み中は GPU へ上げる Pass を後ろに足す。下の場面が隠れている間は場面の Pass を組まない。
    pub def passPlanOf(w: In): Render.PassPlan =
        let scene = if (hidden(w)) Render.passPlan(Nil) else StageView.passPlan(w#stage);
        { passes = List.append(scene#passes, w#warm#passes), targets = Map.union(scene#targets, w#warm#targets) }

    /// 層ごとの木（絵と押せる物の当たり）。Controls.tapAt も同じ木から押した物を選ぶ。
    pub def layers(ctx: App.ViewCtx, w: In): List[(Layer, ZStack.Tree[Layer, World.Press])] =
        let scene = if (hidden(w)) ZStack.leaf(Nil) else StageView.frameTree(w#stage);
        let loading = w#loading |> Option.map(LoadingView.tree(ctx)) |> Option.getWithDefault(ZStack.leaf(Nil));
        (Layer.Scene, scene) :: (Layer.Loading, loading) :: (Layer.Hud, ZStack.leaf(hud(ctx, w)))
            :: (Layer.Volume, w#volume |> Option.map(VolumeView.tree) |> Option.getWithDefault(ZStack.leaf(Nil))) :: (Layer.Prompt, quitPrompt(ctx, w)) :: Nil

    // ── 画面の上の小さな印（Layer.Hud） ──

    /// マウスをキャプチャしている間だけ、画面の真ん中に 2 px の目立たない点（向いている所を指す）と、F3 の診断の行（左上）。
    pub def hud(ctx: App.ViewCtx, w: In): List[Render.PlacedItem] =
        let theme = ThemeDoc.rec(w#theme);
        let dot = if (w#looking and not w#askingQuit)
                      RawDraw.circleAt({ x = World.width() / 2.0, y = World.height() / 2.0 }, 1.0, Color.mix(theme#bg, theme#accent, 0.45), 0) :: Nil
                  else Nil;
        let lines = w#diagnostics |> List.zipWithIndex |> List.map(e -> {
            let (i, line) = e;
            let size = 8.0;
            TextDraw.centered({ text = line, atlas = ctx#atlas, size = size, color = theme#accent, z = 1,
                                centerX = 4.0 + TextDraw.width(line, ctx#atlas, size) / 2.0, y = 4.0 + Int32.toFloat64(i) * (size + 2.0) })
        });
        List.append(dot, lines)

    // ── 終了の確認の窓（Layer.Prompt） ──

    /// Esc か閉じるボタンで出る確認。場面を薄く沈める幕・窓・文言（文言は sample.kind.json の quitPrompt）。
    /// 窓の中を押すと QuitYes・外を押すと QuitNo（blocking が奥の当たりを塞ぐ）。
    def quitPrompt(ctx: App.ViewCtx, w: In): ZStack.Tree[Layer, World.Press] =
        if (not w#askingQuit) ZStack.leaf(Nil)
        else {
            let theme = ThemeDoc.rec(w#theme);
            let size = { x = World.width() * 0.6, y = 48.0 };
            let at = { x = (World.width() - size#x) / 2.0, y = (World.height() - size#y) / 2.0 };
            let window =
                { at = Vec2.zero(), item = RawDraw.box({ x = World.width(), y = World.height() }, theme#bg, 0) |> Render.fade(0.6) }
                    :: { at = at, item = RawDraw.box(size, Color.darken(theme#bg, 0.2), 1) }
                    :: TextDraw.centeredAt({ text = w#quitPrompt, atlas = ctx#atlas, size = 16.0, color = theme#accent, z = 2,
                                             center = { x = World.width() / 2.0, y = World.height() / 2.0 } })
                    :: Nil;
            ZStack.blocking(Some(World.Press.QuitNo),
                ZStack.of(ZStack.leaf(window) :: ZStack.hit(World.Press.QuitYes, { position = at, size = size }) :: Nil))
        }
}
