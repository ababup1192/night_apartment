// 歩く規則のテスト: 床の高さ・階段の上り下り・止まっている時に震えない・壁と手すりを抜けない。
// 箱は書き出しの collision.glb。床の高さの期待値は Blender の寸法（1 階の床 0.3 m・階高 2.8 m・踊り場は半分の 1.4 m 上）。
mod TestWalk {

    def b(): List[Collider.Box] \ Fs.FileRead = TestKit.boxes()

    def last(ws: List[Walker.Walker], fallback: Walker.Walker): Walker.Walker = List.last(ws) |> Option.getWithDefault(fallback)

    // ── 床の高さ ──

    /// 道路・敷地・1 階の外廊下・2 階の外廊下に立つと、それぞれの床の高さに着く（cm）。
    /// 道路は -0.01 m の面・敷地は -0.005 m・1 階の外廊下は基礎の上 0.3 m・2 階はスラブの上 3.1 m。
    @Test
    def testStandingSnapsToEachFloor(): Unit \ {Assert, Fs.FileRead} =
        let bx = b();
        Assert.assertEq(expected = (-1, 0, 30, 310),
            (TestKit.feetCm(TestKit.standAt(bx, 0.0, 0.0, 9.5, 0.0)), TestKit.feetCm(TestKit.standAt(bx, -6.0, 0.0, 3.5, 0.0)),
             TestKit.feetCm(TestKit.standAt(bx, -6.0, 0.1, 0.8, 0.0)), TestKit.feetCm(TestKit.standAt(bx, -6.0, 3.0, 0.8, 0.0))))

    // ── 階段 ──

    /// 1 階の踊り場から段板 A を 3 秒上ると、中間の踊り場（0.3 + 1.4 = 1.7 m）に着く。
    @Test
    def testFlightAClimbsToMidLanding(): Unit \ {Assert, Fs.FileRead} =
        let bx = b();
        let start = TestKit.standAt(bx, -17.68, 0.3, 0.75, 180.0);
        Assert.assertEq(expected = 170, TestKit.feetCm(last(Walker.simulate(bx, TestKit.walk(), TestKit.forward(false), TestKit.frame(), 180, start), start)))

    /// 中間の踊り場から段板 B を上ると、2 階の踊り場（3.1 m）に着く。
    @Test
    def testFlightBClimbsToSecondFloor(): Unit \ {Assert, Fs.FileRead} =
        let bx = b();
        let start = Walker.settle(bx, TestKit.walk(), Walker.standing(-18.85, 1.8, -2.0, 0.0));
        Assert.assertEq(expected = 310, TestKit.feetCm(last(Walker.simulate(bx, TestKit.walk(), TestKit.forward(false), TestKit.frame(), 200, start), start)))

    /// 2 階の踊り場から段板 B を走って下りると、中間の踊り場（1.7 m）に着く（途中で浮いて落ちない）。
    @Test
    def testRunningDownFlightBStaysOnTheSlope(): Unit \ {Assert, Fs.FileRead} =
        let bx = b();
        let start = Walker.settle(bx, TestKit.walk(), Walker.standing(-18.85, 3.2, 0.6, 180.0));
        let path = Walker.simulate(bx, TestKit.walk(), TestKit.forward(true), TestKit.frame(), 90, start);
        Assert.assertEq(expected = (170, true),
            (TestKit.feetCm(last(path, start)), List.forAll(Walker.isGrounded, path)))

    // ── 止まっている時 ──

    /// 段板の坂の途中と平らな床で 1 秒止まっていると、位置も高さも 1 bit も動かない。
    @Test
    def testStandingStillDoesNotJitter(): Unit \ {Assert, Fs.FileRead} =
        let bx = b();
        let slope = Walker.settle(bx, TestKit.walk(), Walker.standing(-17.68, 1.2, -0.75, 180.0));
        let flat = TestKit.standAt(bx, -6.0, 0.3, 0.8, 90.0);
        let still = (w: Walker.Walker) -> Walker.simulate(bx, TestKit.walk(), Walker.idle(), TestKit.frame(), 60, w)
            |> List.map(p -> (p#x, p#feet, p#z));
        Assert.assertEq(expected = (List.repeat(60, (slope#x, slope#feet, slope#z)), List.repeat(60, (flat#x, flat#feet, flat#z))),
            (still(slope), still(flat)))

    /// 段板の坂の途中に立つと、足の着き方は「坂」になる（平らな床とは別の case）。
    @Test
    def testFootingOnFlightIsSlope(): Unit \ {Assert, Fs.FileRead} =
        let bx = b();
        Assert.assertEq(expected = Walker.Footing.Standing(Walker.Surface.Slope),
            Walker.settle(bx, TestKit.walk(), Walker.standing(-17.68, 1.2, -0.75, 180.0))#footing)

    // ── 区切って進む ──

    /// 1 コマ 0.05 秒で走って（1 コマ 16 cm）2 階の腰壁へまっすぐ当たっても、腰壁の内側（z 1.05 − 半径 0.22 = 0.83）で止まる。
    @Test
    def testFastRunStopsAtParapet(): Unit \ {Assert, Fs.FileRead} =
        let bx = b();
        let start = TestKit.standAt(bx, -8.0, 3.1, 0.6, 0.0);
        let end = last(Walker.simulate(bx, TestKit.walk(), TestKit.forward(true), TestKit.clockOf(0.05), 20, start), start);
        Assert.assertEq(expected = 83, Float64.tryToInt32(Float64.round(end#z * 100.0)) |> Option.getWithDefault(-1))
}
