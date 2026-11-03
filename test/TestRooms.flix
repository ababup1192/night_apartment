// 2 階の部屋のテスト: manifest の rooms の読み方・部屋を描くか・部屋の灯りの選び方。
// 部屋の寸法は書き出しの manifest.json（間口 3.4 m・202 は glTF の x 3.4..6.8）、描く距離は RoomsDoc の既定から。
mod TestRooms {
    use fge::{Color, Model3d, Num, Scene3d, Vec3}

    def draw(): RoomsDoc.Draw = RoomsDoc.rec(RoomsDoc.defaults())#draw

    def lightDoc(): RoomsDoc.Light = RoomsDoc.rec(RoomsDoc.defaults())#light

    def pi(): Float64 = Num.pi()

    // ── manifest の rooms ──

    /// 部屋は 202〜205 の 4 つで、どれも扉の板の箱が見つかり、その 4 つの箱は常に効く箱から外れる。
    @Test
    def testFourRoomsWithDoorLeaves(): Unit \ {Assert, Fs.FileRead} =
        let rooms = fst(TestKit.layout());
        Assert.assertEq(expected = ("202" :: "203" :: "204" :: "205" :: Nil, List.length(TestKit.boxes()) - 4),
            (rooms |> List.map(r -> r#id), List.length(TestKit.statics())))

    /// 部屋の囲みは engine の座標へ x を反転して写る（202 は glTF の x 3.4..6.8 → -6.8..-3.4）。
    @Test
    def testBoundsAreMirrored(): Unit \ {Assert, Fs.FileRead} =
        let r = TestKit.room("202");
        Assert.assertEq(expected = (-6.8, -3.4), (r#min#x, r#max#x))

    /// 壊れた manifest は部屋 0 で、箱はそのまま全部残る。
    @Test
    def testBrokenManifestHasNoRooms(): Unit \ {Assert, Fs.FileRead} =
        let (rooms, statics) = Rooms.layoutOf("{ not json", TestKit.model());
        Assert.assertEq(expected = (0, List.length(Model3d.nodesWithPrefix(Collider.prefix(), TestKit.model()))), (List.length(rooms), List.length(statics)))

    // ── 部屋を描くか ──

    /// 202 を描くか: 部屋の中 → 描く・外廊下から閉じた扉 → 描かない・開いた扉を見ている → 描く・
    /// 5 m 先の開いた扉から目をそらしている → 描かない・開いた扉を見ていても seeRange より遠い → 描かない。
    @Test
    def testRoomDrawnOnlyWhenSeen(): Unit \ {Assert, Fs.FileRead} =
        let r = TestKit.room("202");
        let corridor = Vec3.v3(-4.1, 4.7, 0.8);
        Assert.assertEq(expected = (true, false, true, false, false),
            (Rooms.isDrawn(draw(), r, Vec3.v3(-5.0, 4.85, -3.9), pi(), 0.0),
             Rooms.isDrawn(draw(), r, corridor, pi(), 0.0),
             Rooms.isDrawn(draw(), r, corridor, pi(), -88.0),
             Rooms.isDrawn(draw(), r, Vec3.v3(-9.1, 4.7, 0.7), pi() * 1.5, -88.0),
             Rooms.isDrawn(draw(), r, Vec3.v3(-4.1 - draw()#seeRange - 1.0, 4.7, 0.7), pi() * 0.5, -88.0)))

    /// 少し開いたまま（-14 度）の 204 は、外廊下の扉の前から見えるので描く。
    @Test
    def testAjarRoomIsDrawnFromCorridor(): Unit \ {Assert, Fs.FileRead} =
        let r = TestKit.room("204");
        Assert.assertEq(expected = true, Rooms.isDrawn(draw(), r, Vec3.v3(-11.8, 4.7, 0.7), pi() * 0.75, r#door#initialDeg))

    // ── 部屋の灯り ──

    /// 灯りは描く部屋の物だけ: 203 だけを描くと 203 の 4 つ（ろうそく 2・テレビ・豆電球）・何も描かないと 0・灯りの無い 202 だけなら 0。
    @Test
    def testOnlyDrawnRoomsLight(): Unit \ {Assert, Fs.FileRead} =
        let rooms = fst(TestKit.layout());
        Assert.assertEq(expected = (4, 0, 0),
            (List.length(RoomLights.pointsOf(lightDoc(), 0.0, Set#{"203"}, rooms)), List.length(RoomLights.pointsOf(lightDoc(), 0.0, Set.empty(), rooms)),
             List.length(RoomLights.pointsOf(lightDoc(), 0.0, Set#{"202"}, rooms))))

    /// テレビの明るさは 10 秒の間 tvMin × 0.9（細かい揺れの分）から 1 の中で動き、同じ時刻なら同じ値。
    @Test
    def testTvFlickerStaysInRange(): Unit \ Assert =
        let d = lightDoc();
        let levels = List.range(0, 600) |> List.map(i -> Flicker.tvLevel(Int32.toFloat64(i) / 60.0, d#tvRate, d#tvMin, 71));
        Assert.assertEq(expected = (true, true, true),
            (List.forAll(v -> v >= d#tvMin * 0.9 - 0.000001 and v <= 1.0, levels), List.length(List.distinct(levels)) > 1,
             Flicker.tvLevel(3.3, d#tvRate, d#tvMin, 71) == Flicker.tvLevel(3.3, d#tvRate, d#tvMin, 71)))
}
