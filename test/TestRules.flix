// 遊びの規則のテスト: 終了の確認・点滅の形・読み込みの幕・自動の操縦（音の規則は TestSound）。
mod TestRules {
    use fge::{PxSpriteDoc, SortingLayer}

    def res(): Res.Res = Res.build(TestRules.docs())

    /// 舞台の無い Doc の束（規則だけを見る）。
    pub def docs(): Res.Docs =
        { sample = SampleDoc.defaults(), inspect = InspectDoc.defaults(), keys = KeysDoc.defaults(), theme = ThemeDoc.defaults(), sprites = PxSpriteDoc.empty(),
          walk = WalkDoc.defaults(), look = LookDoc.defaults(), lights = LightsDoc.defaults(), sound = SoundDoc.defaults(),
          tour = TourDoc.defaults(), rooms = RoomsDoc.defaults(), people = PeopleDoc.defaults(), prefs = AudioPrefs.defaults(),
          stage = { parts = Nil, boxes = Nil, rooms = Nil, things = Nil }, residents = Nil }

    def w0(): World.World = World.initial(res())

    /// 既定の Doc の点滅する管（点きかけ）。
    def lamp0(): LightsDoc.Lamp = match LightsDoc.rec(LightsDoc.defaults())#lamps {
        case l :: _ => l
        case Nil    => bug!("既定の管が無い")
    }

    def glow(g: Flicker.Glow): (Float64, Float64) = (g#level, g#flash)

    /// Esc・閉じるボタンで確認へ、いいえで遊びへ戻る。はいで終わる。
    @Test
    def testQuitAskThenAnswer(): Unit \ Assert =
        let asked = World.askQuit(w0());
        Assert.assertEq(expected = (true, false, true),
            (World.isAskingQuit(asked), World.isAskingQuit(World.answerQuit(false, asked)), World.isQuitting(World.answerQuit(true, asked))))

    /// 終了の確認の間は遊びの時計が止まる。
    @Test
    def testClockPausesWhileAskingQuit(): Unit \ Assert =
        Assert.assertEq(expected = (false, true), (World.isPaused(w0()), World.isPaused(World.askQuit(w0()))))

    /// 読み込みの幕は「部品の数 + 1」の区切りの後に薄め始める（部品 0 なら 1 区切り）。
    @Test
    def testLoadingStepsArePartsPlusOne(): Unit \ Assert =
        Assert.assertEq(expected = 1, World.loadSteps(res()))

    /// 点滅しない管はいつも明るさ 1・瞬かない。
    @Test
    def testSteadyLampNeverFlickers(): Unit \ Assert =
        let lamp = { flicker = LightsDoc.FlickerKind.Steady | lamp0() };
        Assert.assertEq(expected = ((1.0, 0.0), (1.0, 0.0)), (glow(Flicker.glowOf(0.0, lamp)), glow(Flicker.glowOf(12.5, lamp))))

    /// 点きかけの管は、10 秒の間に少なくとも 1 回は瞬いて点く（flash = 1 のコマがある）。同じ時刻なら同じ明るさ。
    @Test
    def testSputterLampFlashesSometimes(): Unit \ Assert =
        let lamp = lamp0();
        let flashes = List.range(0, 600) |> List.exists(i -> Flicker.glowOf(Int32.toFloat64(i) / 60.0, lamp)#flash == 1.0);
        Assert.assertEq(expected = (true, glow(Flicker.glowOf(3.3, lamp))), (flashes, glow(Flicker.glowOf(3.3, lamp))))

    /// 層の表が奥から手前へ交ざらずに並ぶ。
    @Test
    def testLayersAreStackedBackToFront(): Unit \ Assert =
        Assert.assertEq(expected = true, SortingLayer.isStacked(ZOrder.layers()))
}
