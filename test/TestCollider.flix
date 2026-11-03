// 当たり判定の集まりと歩く規則を、手で組んだ小さな箱で確かめる（書き出しに依らない形）。
// 箱は軸に沿った 1 つか 2 つと、歩ける範囲の囲み（WalkDoc の既定の bounds・groundY）。体は WalkDoc の既定（半径 0.22・段の高さ 0.35）。
mod TestCollider {
    use fge::{CollisionShape3d, Num, Vec3}

    /// 真ん中 (cx, cy, cz)・半分の大きさ (hx, hy, hz) の、軸に沿った箱。
    def box(cx: Float64, cy: Float64, cz: Float64, hx: Float64, hy: Float64, hz: Float64): CollisionShape3d.Box3d =
        CollisionShape3d.box3d(Vec3.v3(cx, cy, cz), Vec3.v3(hx, hy, hz))

    /// 床（上の面が 0）。
    def floor(): CollisionShape3d.Box3d = box(0.0, -0.5, 0.0, 20.0, 0.5, 20.0)

    def walk(): WalkDoc.Rec = TestKit.walk()

    def lastOf(ws: List[Walker.Walker], w: Walker.Walker): Walker.Walker = List.last(ws) |> Option.getWithDefault(w)

    /// 1 秒 +X へ歩く（yaw 90 度）。
    def east(bx: List[CollisionShape3d.Box3d], x: Float64): Walker.Walker =
        let world = Collider.worldOf(bx, walk());
        let start = Walker.settle(world, walk(), Walker.standing(x, 0.0, 0.0, 90.0));
        lastOf(Walker.simulate(world, walk(), TestKit.forward(false), TestKit.frame(), 60, start), start)

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
        let world = Collider.worldOf(floor() :: box(-1.0, 1.0, 0.0, 1.0, 1.0, 5.0) :: Nil, walk());
        let start = Walker.settle(world, walk(), Walker.standing(-0.1, 2.0, 0.0, 90.0));
        let path = Walker.simulate(world, walk(), TestKit.forward(false), TestKit.frame(), 90, start);
        Assert.assertEq(expected = (200, true, 0, Some(Walker.Surface.Flat)),
            (TestKit.feetCm(start), List.exists(w -> not Walker.isGrounded(w), path), TestKit.feetCm(lastOf(path, start)), Walker.surfaceOf(lastOf(path, start))))

    // ── 歩ける範囲の囲み ──

    /// 歩ける範囲の東の端（maxX）の 0.5 m 手前から 1 秒東へ歩くと、体の真ん中がちょうど端で止まる（囲みの壁は半径だけ外にある）。
    @Test
    def testBoundsStopBodyCenterAtEdge(): Unit \ Assert =
        let w = east(floor() :: Nil, walk()#bounds#maxX - 0.5);
        Assert.assertEq(expected = Float64.round(walk()#bounds#maxX * 100.0), Float64.round(w#x * 100.0))

    /// 当たり判定の箱の無い所では、groundY の高さの地面に立つ。
    @Test
    def testGroundWithoutBoxesIsAtGroundY(): Unit \ Assert =
        let w = Walker.settle(Collider.worldOf(Nil, walk()), walk(), Walker.standing(0.0, 0.0, 0.0, 0.0));
        Assert.assertEq(expected = (Some(Walker.Surface.Flat), Float64.round(walk()#groundY * 100.0)), (Walker.surfaceOf(w), Float64.round(w#feet * 100.0)))

    // ── 名前で引く箱 ──

    /// 斜めの手すり（傾いた箱で、一番薄い向きが水平）は、縦の 6 本の箱になる（手すりは段鼻の線の真上にだけ立つ）。
    @Test
    def testSlantedRailBecomesUprightSegments(): Unit \ Assert =
        let c = Num.cos(0.6);
        let s = Num.sin(0.6);
        let rail = { center = Vec3.v3(0.0, 1.0, 0.0), ax = Vec3.v3(c, s, 0.0), ay = Vec3.v3(0.0 - s, c, 0.0), az = Vec3.v3(0.0, 0.0, 1.0),
                     half = Vec3.v3(1.5, 0.5, 0.02) };
        let segments = Collider.splitSlantedRails(rail :: Nil);
        Assert.assertEq(expected = (6, true), (List.length(segments), List.forAll(b -> b#ay#y == 1.0, segments)))
}
