// E で調べるテスト: 目の向きのレイが当たった物（自販機・扉の板）を引く・届かない扉と文言の無い物では向いている扉へ戻る・
// 文言は出しておく秒で消える・Doc の名前の頭は一番長く合う物が勝つ。物は書き出しの collision.glb、文言は assets/inspect.kind.json。
mod TestInspect {
    use fge::{Clock, Num}

    /// 足元 (x, y, z)・向き yaw・見下ろす角 pitchDeg（度）に立ち、扉は初めの角の体。
    def body(env: PlayStep.Env, x: Float64, y: Float64, z: Float64, yaw: Float64, pitchDeg: Float64): PlayStep.Body =
        let w = TestKit.standAt(env#world, x, y, z, yaw);
        { walker = { pitch = pitchDeg * Num.pi() / 180.0 | w }, doors = Doors.initialAll(env#rooms), light = PlayStep.Flashlight.Off, seen = None }

    def doc(): InspectDoc.Rec \ Fs.FileRead = InspectDoc.rec(TestKit.inspectDoc())

    /// 自販機の前で白い自販機を見て押すと、白い自販機の文言を引く。
    @Test
    def testVendingMachineShowsItsText(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        Assert.assertEq(expected = InspectDoc.textOf(doc(), "COL_PRP_vending_white") |> Option.map(Inspect.Pick.Thing),
            Some(PlayStep.pressed(env, body(env, -2.3, 0.0, 7.6, 195.0, 8.0))))

    /// 2 階の外廊下で 202 の扉の板を見て押すと、その扉を引く。
    @Test
    def testLookingAtDoorPicksIt(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        Assert.assertEq(expected = Inspect.Pick.Door("202"), PlayStep.pressed(env, body(env, -4.1, 3.1, 0.9, 180.0, 0.0)))

    /// 扉の届く距離（RoomsDoc の door.reach）の外から扉の板を見て押しても、扉は引かない（調べる距離の中でも）。
    /// 足元から 202 の扉の板の真ん中までは水平に約 0.9 m なので、届く距離を 0.5 m にした Doc で押す。
    @Test
    def testDoorBeyondDoorReachIsNotPicked(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        let short = { doors = { reach = 0.5 | env#doors } | env };
        Assert.assertEq(expected = Inspect.Pick.Nothing, PlayStep.pressed(short, body(short, -4.1, 3.1, 0.9, 180.0, 0.0)))

    /// 扉の前で足元の床を見て押すと（床は文言の無い物）、向いている扉を引く。
    @Test
    def testFloorFallsBackToFacingDoor(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        Assert.assertEq(expected = Inspect.Pick.Door("202"), PlayStep.pressed(env, body(env, -4.1, 3.1, 0.9, 180.0, 60.0)))

    /// 遠くの物（調べられる距離の外）は引かない。
    @Test
    def testFarThingIsNotPicked(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        Assert.assertEq(expected = Inspect.Pick.Nothing, PlayStep.pressed(env, body(env, -2.3, 0.0, 11.5, 195.0, 2.0)))

    /// Doc の全部の名前の頭が、collision.glb のどれかのノードに合う（書き間違えた頭は文言が出ない）。
    @Test
    def testEveryPrefixMatchesSomeNode(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = Nil, Inspect.unmatchedPrefixes(doc(), TestKit.model()))

    /// 押した時刻から出しておく秒の間は文言を出し、過ぎたら出さない。
    @Test
    def testCaptionDisappearsAfterShowSeconds(): Unit \ Assert =
        let d = InspectDoc.rec(InspectDoc.defaults());
        let seen = Some({ text = "x", at = Clock.zero() });
        let at = (s: Float64) -> Clock.nowOf((Clock.startAt(s): Clock.Clock[PlayClock.Play]));
        Assert.assertEq(expected = (true, false), (Option.nonEmpty(Inspect.showing(d, at(1.0), seen)), Option.nonEmpty(Inspect.showing(d, at(d#showSeconds + 0.1), seen))))

    /// 名前の頭は一番長く合う物が勝ち（行の並びによらない）、「頭 + _」で切れない名前には合わない。
    @Test
    def testLongestPrefixWinsAtNameBoundary(): Unit \ Assert =
        let d = { things = { prefix = "COL_PRP_bike", text = "b" } :: { prefix = "COL_PRP_bike_abandoned", text = "a" } :: { prefix = "COL_PRP_pot", text = "p" } :: Nil
                  | InspectDoc.rec(InspectDoc.defaults()) };
        Assert.assertEq(expected = (Some("a"), Some("b"), Some("p"), None),
            (InspectDoc.textOf(d, "COL_PRP_bike_abandoned"), InspectDoc.textOf(d, "COL_PRP_bike"), InspectDoc.textOf(d, "COL_PRP_pot_2"), InspectDoc.textOf(d, "COL_PRP_pothos")))
}
