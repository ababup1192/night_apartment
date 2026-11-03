// PostView — 夜の画面の後処理（ブルーム・トーンマップ・ビネット・フィルムの粒・暗部の色調・蛍光灯が消えた時の沈み・FXAA）の
// Pass の並びと、本編の面（純粋）。場面の中身は呼ぶ側（StageView）が渡す。場面から bloomB までは 1 を超える明るさを持つ Pass。
mod PostView {

    use fge::{Color, PostProcess, Render, RenderTarget, ShaderDoc, Vec2}
    use fge::ShaderDoc.{BinOp, Field, Shade, Out, TexChan}

    def wd(): Float64 = World.width()
    def ht(): Float64 = World.height()
    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    def scenePass(): String = "scene"
    def brightPass(): String = "bright"
    def bloomPassA(): String = "bloomA"
    def bloomPassB(): String = "bloomB"

    /// トーンマップ済みの本編の Pass の名前（画面へ写す前の最後の段）。
    /// WhyNot: 縮めた Pass や design の大きさにしない — FXAA は 1 テクセル = 1 画素を前提に縁を探す。
    def postPass(): String = "post"

    /// 後処理の Pass の並び: 場面（窓の画素の HDR）→ 明るい所 → ぼかし 2 回 → 本編の面を窓の画素の Rgba8Unorm へ。
    /// dip = 画面全体に掛ける明るさ（1 = そのまま。近くの蛍光灯がふっと消えた時に下がる）・t = 粒の時刻。
    pub def chain(look: LookDoc.Rec, scene: List[Render.PlacedItem], dip: Float64, t: Float64): Render.PassPlan =
        let black = RenderTarget.LoadOp.Clear(Color.rgb(0.0, 0.0, 0.0));
        let passes =
            { name = scenePass(), clear = RenderTarget.LoadOp.Clear(look#skyColor), items = scene }
                :: { name = brightPass(), clear = black, items = fullFill(brightSpec(look)) :: Nil }
                :: { name = bloomPassA(), clear = black, items = fullFill(blurOf(brightPass(), look#bloomRadius, look#bloomTaps)) :: Nil }
                :: { name = bloomPassB(), clear = black, items = fullFill(blurOf(bloomPassA(), look#bloomRadius * 0.5, look#bloomTaps)) :: Nil }
                :: { name = postPass(), clear = black, items = mainFill(look, dip, t) :: Nil }
                :: Nil;
        let at = s -> RenderTarget.withHdr({ scale = s | RenderTarget.defaultDescriptor() });
        { targets = Map#{ scenePass() => RenderTarget.withMsaa(look#msaaSamples, RenderTarget.withHdr(RenderTarget.windowDescriptor())),
                          brightPass() => at(look#bloomScale),
                          bloomPassA() => at(look#bloomScale * 0.5),
                          bloomPassB() => at(look#bloomScale * 0.5),
                          postPass() => RenderTarget.windowDescriptor() }
          | Render.passPlan(passes) }

    /// 画面へ置く面: post の Pass を FXAA でならして写す。
    pub def fxaaFill(): Render.PlacedItem = fullFill(PostProcess.fxaaSpec(postPass()))

    def fullFill(spec: ShaderDoc.Spec): Render.PlacedItem =
        Render.shaderFill(spec, { position = Vec2.zero(), size = p(wd(), ht()) }, 0.0, 0)

    def k(v: Float64): Field = Field.Const(v)
    def add(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Add, a = a, b = b })
    def sub(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Sub, a = a, b = b })
    def mul(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Mul, a = a, b = b })
    def linear(f: Field): Field = Field.Sampler({ filter = ShaderDoc.FilterMode.Linear, of = f })
    def aspect(): Float64 = wd() / ht()

    /// 本編の面 1 枚。画面の沈み（dip）は面の Param で渡す（Spec はコマごとに変わらない）。
    def mainFill(look: LookDoc.Rec, dip: Float64, t: Float64): Render.PlacedItem =
        Render.shaderFill(mainSpec(look), { position = Vec2.zero(), size = p(wd(), ht()) }, t, 0)
            |> Render.withShaderParams(Map#{ "dip" => dip })

    /// 場面とブルームを足し、沈み・ビネットを掛けてトーンマップし、色調と粒で仕上げる。
    def mainSpec(look: LookDoc.Rec): ShaderDoc.Spec =
        let sharp = chan -> Field.Tex({ name = scenePass(), chan = chan });
        let bloom = chan -> linear(Field.Tex({ name = bloomPassB(), chan = chan }));
        let vig = sub(k(1.0), mul(k(look#vignette),
            Field.Smoothstep({ lo = 0.35, hi = 1.05, of = Field.RadialAspect({ cx = 0.5, cy = 0.5, aspect = aspect() }) })));
        let base = chan -> mul(mul(add(sharp(chan), mul(k(look#bloomStrength), bloom(chan))), Field.Ref("vig")), Field.Param({ name = "dip" }));
        let hdr = { name = "night_post", cycleRate = 0.0,
                    bindings = ("vig", vig) :: ("r0", base(TexChan.R)) :: ("g0", base(TexChan.G)) :: ("b0", base(TexChan.B)) :: Nil,
                    out = Out.Fill({ shade = Shade.Rgb({ r = Field.Ref("r0"), g = Field.Ref("g0"), b = Field.Ref("b0") }), alpha = k(1.0) }) };
        PostProcess.tonemappedWith(PostProcess.Tonemap.AcesFitted, look#exposure, look#whitePoint, finish(look), hdr)

    /// トーンマップの後の 0..1 の色に掛ける色調（暗部を夜の藍へ寄せる・底を持ち上げる・彩度）と、フィルムの粒。
    /// 粒は 1 秒に 24 回選び直す升目ごとの乱数で、暗い所ほど強く見える（明るさに足すだけなので明るい所では埋もれる）。
    /// WhyNot: 重みを bindings に置かない — tonemappedWith の after は Shade しか返せず、トーンマップの後の値から作る重みは式の中に書くしかない。
    def finish(look: LookDoc.Rec): (Field, Field, Field) -> Shade =
        (r, g, b) -> {
            let lum = PostProcess.luma709(r, g, b);
            let dark = Field.Un({ op = ShaderDoc.UnOp.OneMinus, of = Field.Smoothstep({ lo = 0.0, hi = 0.4, of = lum }) });
            let grain = mul(sub(Field.Hash1({ scale = 360.0, seed = 7, bucket = Some(Field.Un({ op = ShaderDoc.UnOp.Floor, of = Field.Time({ scale = 24.0, offset = k(0.0) }) })) }), k(0.5)),
                            k(look#grain * 2.0));
            let graded = (c: Field, shadowC: Float64) -> {
                let toShadow = add(c, mul(mul(dark, k(look#gradeShadowMix)), sub(k(shadowC), c)));
                let lifted = add(k(look#gradeLift), mul(toShadow, k(1.0 - look#gradeLift)));
                add(add(lum, mul(sub(lifted, lum), k(1.0 + look#gradeSaturation))), grain)
            };
            Shade.Rgb({ r = graded(r, look#gradeShadow#r), g = graded(g, look#gradeShadow#g), b = graded(b, look#gradeShadow#b) })
        }

    /// 場面の明るい所だけを残す（しきいは HDR の目盛り。1 を超える所が光る所）。
    def brightSpec(look: LookDoc.Rec): ShaderDoc.Spec =
        let read = chan -> linear(Field.Tex({ name = scenePass(), chan = chan }));
        let luma = PostProcess.luma709(read(TexChan.R), read(TexChan.G), read(TexChan.B));
        let over = Field.Smoothstep({ lo = look#bloomThreshold, hi = look#bloomThreshold + Float64.max(0.01, look#bloomKnee), of = luma });
        let chan = c -> mul(read(c), Field.Ref("over"));
        { name = "night_bright", cycleRate = 0.0, bindings = ("over", over) :: Nil,
          out = Out.Fill({ shade = Shade.Rgb({ r = chan(TexChan.R), g = chan(TexChan.G), b = chan(TexChan.B) }), alpha = k(1.0) }) }

    /// 前の Pass を Linear で読んでぼかし、そのまま写す面（ブルームの 2 段で共用）。
    def blurOf(src: String, radius: Float64, taps: Int32): ShaderDoc.Spec =
        let b = chan -> linear(Field.TexBlur({ name = src, chan = chan, radius = { x = radius / aspect(), y = radius },
                                               taps = ShaderDoc.blurTaps(taps), amount = k(1.0) }));
        { name = "night_blur_${src}", cycleRate = 0.0, bindings = Nil,
          out = Out.Fill({ shade = Shade.Rgb({ r = b(TexChan.R), g = b(TexChan.G), b = b(TexChan.B) }), alpha = k(1.0) }) }
}
