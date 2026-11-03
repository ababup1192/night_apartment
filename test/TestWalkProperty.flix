// 壁と手すりへ向かって歩く場合をたくさん試す: どの場合も、どのコマでも、体が箱に食い込まず（深さ 2 cm 以下）、
// 建物の中（壁の向こう）に入らない。場合は WalkCases（決まった種の乱数と、角・継ぎ目・薄い壁・速く走る時を必ず）。
// 落ちた場合は名前の列で出る（その場合だけ make flow で再生して、挟まった所を見る。README の「挟まった時」）。
mod TestWalkProperty {

    /// 建物の中（外壁の内側。外廊下より奥）か。
    def insideBuilding(w: Walker.Walker): Bool = w#x > -16.95 and w#x < -0.05 and w#z < -0.25 and w#z > -6.85

    /// 1 つの場合を歩かせ、食い込んだか建物に入ったコマがあれば、その名前。
    def failure(bx: List[Collider.Box], c: WalkCases.Case): Option[String] =
        let walk = TestKit.walk();
        let start = Walker.settle(bx, walk, Walker.standing(c#x, c#feet, c#z, c#yaw));
        let path = Walker.simulate(bx, walk, TestKit.forward(c#sprint), TestKit.clockOf(c#dt), c#frames, start);
        let deepest = path |> List.map(w -> Collider.deepestOverlap(bx, Walker.bodyOf(walk), w#x, w#feet, w#z)) |> List.foldLeft(Float64.max, 0.0);
        if (deepest > 0.02 or List.exists(insideBuilding, path)) Some("${c#name} (食い込み ${Float64.toString(deepest)} m)") else None

    /// 必ず入れる 25 の場合（角・継ぎ目・薄い壁・手すり・階段の下・1 コマ 0.05 秒で走る）で食い込まず抜けない。
    @Test
    def testEdgeCasesNeverPenetrate(): Unit \ {Assert, Fs.FileRead} =
        let bx = TestKit.boxes();
        Assert.assertEq(expected = Nil, WalkCases.edges() |> List.filterMap(failure(bx)))

    /// 決まった種の乱数で作った 480 の場合（16 の歩ける所 × 30。向き・ずれ・歩く/走る・刻み 1/60 秒か 0.05 秒）で食い込まず抜けない。
    @Test
    def testRandomWalksNeverPenetrate(): Unit \ {Assert, Fs.FileRead} =
        let bx = TestKit.boxes();
        Assert.assertEq(expected = Nil, WalkCases.random(480) |> List.filterMap(failure(bx)))

}
