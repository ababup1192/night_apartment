// 当たり判定と歩く規則を、手で組んだ小さな箱で確かめる（書き出しに依らない形）。
// 箱は軸に沿った 1 つか 2 つ。体は WalkDoc の既定（半径 0.22・段の高さ 0.35）。
mod TestCollider {
    use fge::Vec3

    /// 真ん中 (cx, cy, cz)・半分の大きさ (hx, hy, hz) の、軸に沿った箱。
    def box(cx: Float64, cy: Float64, cz: Float64, hx: Float64, hy: Float64, hz: Float64): Collider.Box =
        { center = Vec3.v3(cx, cy, cz), ax = Vec3.v3(1.0, 0.0, 0.0), ay = Vec3.v3(0.0, 1.0, 0.0), az = Vec3.v3(0.0, 0.0, 1.0), half = Vec3.v3(hx, hy, hz) }

    /// 床（上の面が 0）。
    def floor(): Collider.Box = box(0.0, -0.5, 0.0, 20.0, 0.5, 20.0)

    def walk(): WalkDoc.Rec = TestKit.walk()

    def lastOf(ws: List[Walker.Walker], w: Walker.Walker): Walker.Walker = List.last(ws) |> Option.getWithDefault(w)

    /// 1 秒 +X へ歩く（yaw 90 度）。
    def east(bx: List[Collider.Box], x: Float64): Walker.Walker =
        let start = Walker.settle(bx, walk(), Walker.standing(x, 0.0, 0.0, 90.0));
        lastOf(Walker.simulate(bx, walk(), TestKit.forward(false), TestKit.frame(), 60, start), start)

    /// x = 1 の厚さ 10 cm の壁へ向かって 1 秒歩くと、体の半径だけ手前で止まる（0.95 − 0.22 = 0.73 m）。
    @Test
    def testWallStopsAtRadius(): Unit \ Assert =
        let w = east(floor() :: box(1.0, 1.0, 0.0, 0.05, 1.0, 5.0) :: Nil, 0.0);
        Assert.assertEq(expected = 73, Float64.tryToInt32(Float64.round(w#x * 100.0)) |> Option.getWithDefault(-1))

    /// 高さ 0.30 m の段（段の高さ 0.35 より低い）は上がれ、0.40 m の段は上がれず手前で止まる
    /// （体は球の列なので、0.40 m の段の縁の手前 sqrt(0.22² − 0.17²) ≒ 0.14 m で止まる）。
    @Test
    def testStepHeightLimit(): Unit \ Assert =
        let low = east(floor() :: box(2.0, 0.15, 0.0, 1.0, 0.15, 5.0) :: Nil, 0.0);
        let high = east(floor() :: box(2.0, 0.2, 0.0, 1.0, 0.2, 5.0) :: Nil, 0.0);
        Assert.assertEq(expected = ((30, true), (0, true)),
            ((TestKit.feetCm(low), low#x > 1.0), (TestKit.feetCm(high), high#x < 1.0)))

    /// 2 m の高さの台の縁から歩き出すと落ち、下の床（0）に着いて立つ。
    @Test
    def testFallsAndLands(): Unit \ Assert =
        let bx = floor() :: box(-1.0, 1.0, 0.0, 1.0, 1.0, 5.0) :: Nil;
        let start = Walker.settle(bx, walk(), Walker.standing(-0.1, 2.0, 0.0, 90.0));
        let path = Walker.simulate(bx, walk(), TestKit.forward(false), TestKit.frame(), 90, start);
        Assert.assertEq(expected = (200, true, 0, Walker.Footing.Standing(Walker.Surface.Flat)),
            (TestKit.feetCm(start), List.exists(w -> not Walker.isGrounded(w), path), TestKit.feetCm(lastOf(path, start)), lastOf(path, start)#footing))

    /// 段の高さを少し超える台（0.38 m）の真上に体の真ん中がある時、1 回の押し出しは半径（0.22 m）を超えない（大きな台でも飛ばない）。
    @Test
    def testPushFromAboveIsCapped(): Unit \ Assert =
        let b = box(0.0, 0.19, 0.0, 3.0, 0.19, 3.0);
        let push = Collider.pushOut(b, Vec3.v3(0.5, 0.57, 0.2), 0.22);
        Assert.assertEq(expected = Some(true), push |> Option.map(p -> { let (x, z) = p; x * x + z * z <= 0.22 * 0.22 + 0.000001 }))

    /// 横から壁に食い込んだ球は、1 回の押し出しで壁の面から半径ちょうどの所へ出る（壁の面 x = 0.95・球の真ん中 0.8 → 0.73）。
    @Test
    def testSidePushIsExact(): Unit \ Assert =
        let push = Collider.pushOut(box(1.0, 1.0, 0.0, 0.05, 1.0, 5.0), Vec3.v3(0.8, 1.0, 0.0), 0.22);
        Assert.assertEq(expected = Some((-7, 0)), push |> Option.map(p -> { let (x, z) = p; (Float64.tryToInt32(Float64.round(x * 100.0)) |> Option.getWithDefault(0), Float64.tryToInt32(Float64.round(z * 100.0)) |> Option.getWithDefault(0)) }))
}
