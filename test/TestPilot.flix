// 自動の操縦のテスト: 道筋を歩き終える（実際の舞台の箱と部屋と tour.route.json の道筋で）。
mod TestPilot {
    use fge::Vec3

    def tour(): TourDoc.Rec \ Fs.FileRead = TourDoc.rec(TourDoc.load(TourDoc.path()))

    /// tour.route.json の道筋を道路から 60 fps で 5 分まで歩かせると、最後の点（2 階の外廊下・3.1 m）で歩き終え、
    /// 挟まって諦めた点は 0。
    @Test
    def testTourWalksToTheEnd(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        let t = tour();
        let start = { walker = TestKit.standAt(env#boxes, t#startX, 0.0, t#startZ, t#startYaw), doors = Doors.initialAll(env#rooms), light = PlayStep.Flashlight.On };
        let (body, state) = Pilot.simulate(env, t, TestKit.frame(), 18000, Pilot.start(), start);
        Assert.assertEq(expected = (true, 0, 310), (Pilot.isDone(t, state), Pilot.missedOf(state), TestKit.feetCm(body#walker)))

    /// 2 階の外廊下（look_down）から部屋の道筋を歩くと、4 部屋の中へ入り、最後は 4 枚とも閉じている
    /// （204 は初め -14 度で開いていたが、出る時に閉める）。
    @Test
    def testRoomsTourEntersEveryRoom(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        let t = tour();
        let s0 = Pilot.startAfter(t, "look_down") |> Option.getWithDefault(Pilot.start());
        let start = { walker = TestKit.standAt(env#boxes, -11.85, 3.1, 0.66, 90.0), doors = Doors.initialAll(env#rooms), light = PlayStep.Flashlight.On };
        let (bodies, state) = Pilot.trace(env, t, TestKit.frame(), 12000, s0, start);
        let visited = bodies |> List.filterMap(b -> Rooms.roomAt(env#rooms, Vec3.v3(b#walker#x, b#walker#feet, b#walker#z))) |> List.distinct |> List.sort;
        let closed = List.last(bodies) |> Option.map(b -> Map.forAll((_, s) -> Doors.isClosed(s), b#doors)) |> Option.getWithDefault(false);
        Assert.assertEq(expected = ("202" :: "203" :: "204" :: "205" :: Nil, true, 0, true),
            (visited, closed, Pilot.missedOf(state), Pilot.isDone(t, state)))
}
