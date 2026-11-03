// StageView — 夜のアパートを一人称で描く（純粋）。
//
// ── 組み方 ──
// 舞台の部品（Blender でベイクした光 = lightmap つき）を engine の Scene3d 1 つで描く。毎コマ替わるのは:
//   自分で光る絵の Param（倍率・点滅する管の明るさ・点きかけの管が瞬いた光）
//   動く光: 手の灯り（スポット 1 本・法線マップが効く）と、点きかけの管が瞬いた時の点光源
//   羽虫: 点いた管のまわりを回る小さな粒（光とかすみを当てないビルボード）
//   霧: 距離で夜の藍へ沈む（Scene3d の DistanceFog）
// ベイクに入っている蛍光灯・自販機・防犯灯の光は動く光に入れない（同じ光で二重に照らす）。
// 場面は窓の画素の HDR の Pass に描き、PostView がブルーム・トーンマップ・ビネット・粒・色調を掛けて画面へ写す。
// 当たり判定の表示（C キー）は箱の辺と体の形を、場面に重ねて描く。
// 2 階の部屋は、描くと決めた部屋（drawnRooms。Rooms.isDrawn）の部品だけを置き、玄関の扉は扉ごとの角の行列で回して置く。
// 部屋の灯りは描く部屋の物だけを足す。点滅の光・部屋の灯り・住人を照らす灯りは全部 pointLights に入れる
// （engine が目に近い Scene3d.maxPointLights() 本を選ぶ）。
// 住人（骨つきの形）は lightmap を持たないので、動く光と環境光だけで照らされる（環境光は lightmap つきの舞台には足されない）。
mod StageView {
    use fge::{App, Color, Hash01, Mat4, Mesh3d, Num, PxSpriteAtlas, Render, Scene3d, ShaderDoc, SortingLayer, Texture3d, Vec2, Vec3, ZStack}
    use fge::ShaderDoc.{Field, Shade, Out}
    use ZOrder.Layer

    /// 描くのに要る値。
    pub type alias In = {
        t = Float64,
        // 目の位置と向き（ラジアン）・縦の画角（度）。
        eye = Vec3.Vec3,
        yaw = Float64,
        pitch = Float64,
        fovY = Float64,
        look = LookDoc.Rec,
        lights = LightsDoc.Rec,
        // 手の灯りが点いているか。
        lightOn = Bool,
        placed = List[Stage.Group],
        // 描く部屋の番号・玄関の扉を今の角へ回す行列（部屋の番号ごと）・描く部屋の灯り。
        drawnRooms = Set[String],
        doorMatrices = Map[String, Mat4.Mat4],
        roomLights = List[Scene3d.PointLight],
        // 描く住人（今の姿勢で置いた形）。
        people = List[Scene3d.Instance3d],
        textures = List[Texture3d.Texture3d],
        atlas = PxSpriteAtlas.Baked,
        // 当たり判定の表示（None なら描かない）: 箱の辺の形・今の角の扉の板と住人のカプセルの箱の辺の形・体の形・足元。
        colliders = Option[{ boxes = Mesh3d.Mesh3d, doors = Mesh3d.Mesh3d, body = Mesh3d.Mesh3d, feet = Vec3.Vec3 }]
    }

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    def wd(): Float64 = World.width()
    def ht(): Float64 = World.height()
    def rad(d: Float64): Float64 = d * Walker.pi() / 180.0

    // ── 入口 ──

    /// 本編より先に描く Pass の計画（場面 → ブルーム → 後処理）。
    pub def passPlan(w: In): Render.PassPlan =
        let stack = SortingLayer.stack(App.pickCtx(p(wd(), ht())), Layer.Scene);
        PostView.chain(w#look, stack(ZStack.of(ZStack.leaf(sky(w) :: Nil) :: ZStack.leaf(scene(w) :: Nil) :: Nil)), screenDip(w), w#t)

    /// 本編の木: トーンマップ済みの後処理の Pass を FXAA でならした面 1 枚。
    pub def frameTree(_w: In): ZStack.Tree[Layer, World.Press] = ZStack.leaf(PostView.fxaaFill() :: Nil)

    // ── 光 ──

    /// 自分で光る絵の Param: 倍率と、点滅する管ごとの明るさ・瞬いた光。
    def emissionParams(w: In): Map[String, Float64] =
        Flicker.flickering(w#lights#lamps) |> List.foldLeft((acc, e) -> {
            let (i, lamp) = e;
            let g = Flicker.glowOf(w#t, lamp);
            acc |> Map.insert(Flicker.levelParam(i), g#level) |> Map.insert(Flicker.glowParam(i), g#flash)
        }, Map#{ Stage.gainParam() => w#look#emissiveGain })

    def forwardOf(w: In): Vec3.Vec3 =
        Vec3.v3(Vec2.sin(w#yaw) * Vec2.cos(w#pitch), 0.0 - Vec2.sin(w#pitch), Vec2.cos(w#yaw) * Vec2.cos(w#pitch))

    /// 手の灯り: 目の少し前・下・右から、見ている向きへ。
    def flashlight(w: In): List[Scene3d.SpotLight] =
        if (not w#lightOn) Nil
        else {
            let f = w#lights#flashlight;
            let fwd = forwardOf(w);
            let right = Vec3.v3(Vec2.cos(w#yaw), 0.0, 0.0 - Vec2.sin(w#yaw));
            let at = Vec3.add(w#eye, Vec3.add(Vec3.mul(fwd, f#forward), Vec3.add(Vec3.mul(right, f#right), Vec3.v3(0.0, 0.0 - f#down, 0.0))));
            { color = f#color, intensity = f#intensity, range = f#range, innerFovY = Some(rad(f#innerConeDeg)),
              shadow = if (f#shadow) Some({ mapSize = 1024, bias = 0.0015, pcfRadius = 1, strength = 0.85 }) else None
              | Scene3d.spotLight(at, Vec3.add(at, Vec3.mul(fwd, 10.0)), rad(f#coneDeg)) } :: Nil
        }

    /// 点きかけの管が瞬いた時の光（管の少し下に置く点光源）。
    def flashLights(w: In): List[Scene3d.PointLight] =
        let fa = w#lights#flash;
        Flicker.flickering(w#lights#lamps) |> List.filterMap(e -> {
            let (_, lamp) = e;
            let g = Flicker.glowOf(w#t, lamp);
            if (g#flash <= 0.0) None
            else Some({ position = Vec3.v3(lamp#x, lamp#y - 0.15, lamp#z), color = fa#color, intensity = fa#intensity * g#flash, range = fa#range })
        })

    /// 画面全体の明るさ: 目の近くの Dip の管が消えている間、近さに応じて沈める。
    def screenDip(w: In): Float64 =
        let fa = w#lights#flash;
        let loss = Flicker.flickering(w#lights#lamps) |> List.foldLeft((acc, e) -> {
            let (_, lamp) = e;
            if (lamp#flicker != LightsDoc.FlickerKind.Dip) acc
            else {
                let d = Vec3.length(Vec3.sub(Vec3.v3(lamp#x, lamp#y, lamp#z), w#eye));
                let near = Num.clamp(0.0, 1.0, 1.0 - d / Float64.max(0.1, fa#dipRange));
                acc + (1.0 - Flicker.glowOf(w#t, lamp)#level) * near * fa#screenDip
            }
        }, 0.0);
        Num.clamp(0.2, 1.0, 1.0 - loss)

    // ── 羽虫 ──

    /// 状態ごとの羽虫の多さ（点いた管ほど多い・消えた管には来ない）。
    def fliesShare(s: LightsDoc.LampState): Float64 = match s {
        case LightsDoc.LampState.On    => 1.0
        case LightsDoc.LampState.Dim   => 0.45
        case LightsDoc.LampState.Dying => 0.3
        case LightsDoc.LampState.Dead  => 0.0
    }

    /// 目から drawRange の中の管のまわりの羽虫。管の長さの向き（x）に長く、縦と奥へ平たい殻の中を、
    /// 1 匹ずつ違う速さと傾きで回る（管に近いほど多い）。
    def flies(w: In): List[Scene3d.Billboard3d] =
        let fl = w#lights#flies;
        match PxSpriteAtlas.regionOf(w#atlas, "fly", "a") {
            case None => Nil
            case Some(rect) =>
                w#lights#lamps |> List.zipWithIndex |> List.flatMap(e -> {
                    let (li, lamp) = e;
                    let center = Vec3.v3(lamp#x, lamp#y - 0.06, lamp#z);
                    let n = Float64.tryToInt32(Float64.round(Int32.toFloat64(fl#perLamp) * fliesShare(lamp#state))) |> Option.getWithDefault(0);
                    if (n == 0 or Vec3.length(Vec3.sub(center, w#eye)) > fl#drawRange) Nil
                    else List.range(0, n) |> List.map(i -> {
                        let seed = li * 97 + i;
                        let h = Hash01.at(seed, 31);
                        let r = fl#spread * (0.12 + 0.88 * h * h);
                        let speed = fl#speed * (1.5 + 2.5 * Hash01.at(seed, 32)) / Float64.max(0.15, r);
                        let a = Hash01.at(seed, 33) * 6.283 + w#t * speed;
                        let b = Hash01.at(seed, 34) * 6.283 + w#t * speed * 0.73;
                        let jitter = 0.03 * Vec2.sin(w#t * 23.0 + Int32.toFloat64(seed));
                        let at = Vec3.add(center, Vec3.v3(Vec2.cos(a) * r * 1.4, Vec2.sin(b) * r * 0.45 - 0.04 + jitter, Vec2.sin(a) * r * 0.7));
                        Scene3d.billboard(Res.atlasName(), rect, at, p(fl#size, fl#size))
                            |> Scene3d.withAnchor(p(0.5, 0.5)) |> Scene3d.withBillboardTint(fl#color) |> Scene3d.unlit
                    })
                })
        }

    // ── 当たり判定の表示 ──

    def glowMaterial(c: Color): Scene3d.Material3d =
        let spec = { name = "night_debug_line", cycleRate = 0.0, bindings = Nil,
                     out = Out.Fill({ shade = Shade.Rgb({ r = Field.VertexColor({ chan = ShaderDoc.TexChan.R }), g = Field.VertexColor({ chan = ShaderDoc.TexChan.G }), b = Field.VertexColor({ chan = ShaderDoc.TexChan.B }) }), alpha = Field.Const(1.0) }) };
        Scene3d.material(spec) |> Scene3d.withEmission(Shade.Solid(c))

    def colliderInstances(w: In): List[Scene3d.Instance3d] = match w#colliders {
        case None => Nil
        case Some(c) =>
            Scene3d.meshInstance(c#boxes, Mat4.identity()) |> Scene3d.withMaterial(glowMaterial(Color.rgb(0.1, 0.5, 0.2)))
                :: (Scene3d.meshInstance(c#doors, Mat4.identity()) |> Scene3d.withMaterial(glowMaterial(Color.rgb(0.1, 0.5, 0.2))))
                :: (Scene3d.meshInstance(c#body, Mat4.translate(c#feet)) |> Scene3d.withMaterial(glowMaterial(Color.rgb(0.6, 0.1, 0.1))))
                :: Nil
    }

    // ── 1 コマの場面 ──

    // ── 空 ──

    /// 空の面: 天頂の色から地平の色へ、縦になめらかに移る（地平の位置は見上げる角と画角から毎コマ Param で渡す）。
    /// 3D の場面は背景を塗らずにこの上へ描く。
    def sky(w: In): Render.PlacedItem =
        let lk = w#look;
        let v = Field.Uv({ axis = ShaderDoc.Axis.V });
        let t = Field.Smoothstep({ lo = 0.0, hi = 1.0, of = Field.Bin({ op = ShaderDoc.BinOp.Div,
                    a = Field.Bin({ op = ShaderDoc.BinOp.Sub, a = v, b = Field.Param({ name = "h0" }) }), b = Field.Const(Float64.max(0.01, lk#horizonSpan)) }) });
        let spec = { name = "night_sky", cycleRate = 0.0, bindings = Nil,
                     out = Out.Fill({ shade = Shade.Ramp({ lo = lk#skyColor, hi = lk#horizonColor, field = t }), alpha = Field.Const(1.0) }) };
        let half = rad(w#fovY) / 2.0;
        let horizon = 0.5 - 0.5 * (Vec2.sin(w#pitch) / Vec2.cos(w#pitch)) / (Vec2.sin(half) / Vec2.cos(half));
        Render.shaderFill(spec, { position = Vec2.zero(), size = p(wd(), ht()) }, w#t, 0)
            |> Render.withShaderParams(Map#{ "h0" => horizon - lk#horizonSpan })

    /// 置く物: いつも描く部品・描く部屋の部品・今の角へ回した玄関の扉。
    def stageInstances(w: In, params: Map[String, Float64]): List[Scene3d.Instance3d] =
        w#placed |> List.flatMap(g -> match g#role {
            case Stage.Role.Always   => g#items |> List.map(Stage.instanceOf(params))
            case Stage.Role.Room(id) => if (Set.memberOf(id, w#drawnRooms)) g#items |> List.map(Stage.instanceOf(params)) else Nil
            case Stage.Role.Door(id) => g#items |> List.map(Stage.instanceAt(params, Map.getWithDefault(id, Mat4.identity(), w#doorMatrices)))
        })

    /// 舞台全部を engine の Scene3d 1 つで描く。
    def scene(w: In): Render.PlacedItem =
        let params = emissionParams(w);
        let camera = { eye = w#eye, yaw = w#yaw, pitch = w#pitch, fovY = rad(w#fovY), near = 0.05, far = 400.0 };
        let base = Scene3d.scene(camera, p(wd(), ht()));
        let lk = w#look;
        Render.scene3d(Vec2.zero(), { instances = List.flatten(stageInstances(w, params) :: w#people :: colliderInstances(w) :: Nil),
                                      textures = w#textures, billboards = flies(w),
                                      pointLights = List.append(flashLights(w), w#roomLights),
                                      spotLights = flashlight(w),
                                      environment = { ambient = lk#ambient, hemisphere = 0.0, toonSteps = 0,
                                                      fog = Some({ color = lk#fogColor, near = lk#fogNear, far = lk#fogFar }),
                                                      background = None },
                                      time = w#t | base })
}
