// マウスの視点のテスト: 動いた量 × 感度で回る・上下の反転・キャプチャしていない時と窓にフォーカスが無い時は回らない・見上げの上限・
// 窓を押すとキャプチャし Esc で放し、放している時の Esc で終了の確認・画面の真ん中の点はキャプチャしている間だけ。
// 感度と見上げの上限は walk.kind.json の既定（WalkDoc.defaults）から。
mod TestLook {
    use fge::{App, GameEngine, Vec2}

    def walk(): WalkDoc.Rec = TestKit.walk()

    def res(): Res.Res = Res.build(TestRules.docs())

    def screen(): Vec2.Vec2 = { x = World.width(), y = World.height() }

    /// キーの何も押されていないフレーム（click なら窓を押した拍）。
    def frameOf(keys: Set[GameEngine.Key], click: Bool): App.Frame =
        App.frameOf({ prev = Set.empty() }, { current = keys }, 1.0 / 60.0, screen(),
                    { prevCursor = None, cursor = { x = 240.0, y = 135.0 } }, { prevDown = false, down = click, wheel = 0.0 })

    // ── 回る角 ──

    /// キャプチャ中に (10, 5) px 動かすと、(10 × 感度, 5 × 感度) 度回る。上下を逆にすると縦だけ符号が替わる。
    @Test
    def testLookFollowsSensitivityAndInvert(): Unit \ Assert =
        let s = walk()#mouseSensitivity;
        Assert.assertEq(expected = ((10.0 * s, 5.0 * s), (10.0 * s, -5.0 * s)),
            (Controls.lookOf(walk(), true, true, { x = 10.0, y = 5.0 }), Controls.lookOf({ invertY = true | walk() }, true, true, { x = 10.0, y = 5.0 })))

    /// キャプチャしていない時と、窓にフォーカスが無い時は、動かしても回らない。
    @Test
    def testNoLookWithoutCaptureOrFocus(): Unit \ Assert =
        Assert.assertEq(expected = ((0.0, 0.0), (0.0, 0.0)),
            (Controls.lookOf(walk(), false, true, { x = 10.0, y = 5.0 }), Controls.lookOf(walk(), true, false, { x = 10.0, y = 5.0 })))

    /// どれだけ大きく見下ろしても、見上げ見下ろしの角は pitchLimit で止まる。
    @Test
    def testPitchStopsAtLimit(): Unit \ Assert =
        let w = Walker.simulate(Nil, walk(), { lookDeg = 1000.0 | Walker.idle() }, TestKit.frame(), 1, Walker.standing(0.0, 0.0, 0.0, 0.0));
        Assert.assertEq(expected = Some(true), List.head(w) |> Option.map(b -> Float64.abs(b#pitch - walk()#pitchLimit * Walker.pi() / 180.0) < 0.0001))

    // ── キャプチャの切り替え ──

    /// 窓を押すとキャプチャ → Esc で放す（終了の確認は出ない）→ 放している時の Esc で終了の確認が出る。
    @Test
    def testClickCapturesAndEscReleasesThenAsks(): Unit \ Assert =
        let r = res();
        let clicked = Controls.step(frameOf(Set.empty(), true), r, World.initial(r));
        let released = Controls.step(frameOf(Set#{GameEngine.Key.Escape}, false), r, clicked);
        let asked = Controls.step(frameOf(Set#{GameEngine.Key.Escape}, false), r, released);
        Assert.assertEq(expected = (true, false, false, true),
            (World.isLooking(clicked), World.isLooking(released), World.isAskingQuit(released), World.isAskingQuit(asked)))

    // ── 画面の真ん中の点 ──

    /// 画面の上の印は、キャプチャしていない時は何も無く、キャプチャしている間だけ真ん中の点が 1 つ出る。
    @Test
    def testCrosshairOnlyWhileCapturing(): Unit \ Assert =
        let r = res();
        let ctx = App.pickCtx(screen());
        let w = World.initial(r);
        Assert.assertEq(expected = (0, 1),
            (List.length(View.hud(ctx, View.inputOf(r, w))), List.length(View.hud(ctx, View.inputOf(r, World.setLooking(true, w))))))
}
