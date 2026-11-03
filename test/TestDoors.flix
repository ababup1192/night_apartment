// 玄関の扉のテスト: 開け閉めの進み・端で止まる・押した時の向き・体に当たる所で止まる・閉じた扉は通れず開いた扉は通れる。
// 扉は書き出しの 202 の扉（蝶番 engine の (-3.675, 3.1, 0.02)・閉じた板の箱の真ん中 (-4.1, 4.1, 0.02)）。速さと開け切る角は RoomsDoc の既定から。
mod TestDoors {
    use fge::{Mat4, Vec3}

    def doc(): RoomsDoc.Door = TestKit.doorDoc()

    def body(): Collider.Body = Walker.bodyOf(TestKit.walk())

    /// 扉から遠い足元（体に当たらない）。
    def away(): Vec3.Vec3 = Vec3.v3(0.0, 0.0, 10.0)

    def closed(): Doors.State = { angle = 0.0, motion = Doors.Motion.Still }

    def dt(): Float64 = 1.0 / 60.0

    def near(a: Float64, b: Float64): Bool = Float64.abs(a - b) < 0.001

    // ── 開け閉めの進み ──

    /// 閉じた扉を押して 0.5 秒（30 コマ）で、速さ × 0.5 秒だけ外廊下の側（負）へ回る。
    @Test
    def testOpeningAdvancesBySpeed(): Unit \ {Assert, Fs.FileRead} =
        let door = TestKit.room("202")#door;
        let s = Doors.stepTimes(doc(), door, body(), away(), dt(), 30, Doors.toggle(Doors.openTo(doc(), door), closed()));
        Assert.assertTrue(near(s#angle, 0.0 - doc()#speedDeg * 0.5))

    /// 開け始めて 2 秒たつと、開け切る角でちょうど止まる（それより先へ回らない）。
    @Test
    def testOpeningStopsAtOpenAngle(): Unit \ {Assert, Fs.FileRead} =
        let door = TestKit.room("202")#door;
        let s = Doors.stepTimes(doc(), door, body(), away(), dt(), 120, Doors.toggle(Doors.openTo(doc(), door), closed()));
        Assert.assertEq(expected = (Doors.openTo(doc(), door), Doors.Motion.Still), (s#angle, s#motion))

    /// 開け切った扉を押して 2 秒たつと、角 0 で止まって閉じた扉になる。
    @Test
    def testClosingStopsShut(): Unit \ {Assert, Fs.FileRead} =
        let door = TestKit.room("202")#door;
        let stop = Doors.openTo(doc(), door);
        let s = Doors.stepTimes(doc(), door, body(), away(), dt(), 120, Doors.toggle(stop, { angle = stop, motion = Doors.Motion.Still }));
        Assert.assertEq(expected = (0.0, true), (s#angle, Doors.isClosed(s)))

    /// Doc の開け切る角が書き出しの止まる角（-90 度）より先でも、-90 度までしか回らない。
    @Test
    def testOpenAngleIsCappedByExport(): Unit \ {Assert, Fs.FileRead} =
        let door = TestKit.room("202")#door;
        Assert.assertEq(expected = door#openLimitDeg, Doors.openTo({ openDeg = -170.0 | doc() }, door))

    // ── 押した時の向き ──

    /// 少し開いたまま止まった扉（204 の初めの -14 度）は押すと開き、回っている途中で押すと向きが逆になる。
    @Test
    def testPressDirection(): Unit \ {Assert, Fs.FileRead} =
        let door = TestKit.room("204")#door;
        let stop = Doors.openTo(doc(), door);
        let ajar = Doors.initial(door);
        Assert.assertEq(expected = (-14.0, Doors.Motion.Opening, Doors.Motion.Closing),
            (ajar#angle, Doors.toggle(stop, ajar)#motion, Doors.toggle(stop, Doors.toggle(stop, ajar))#motion))

    // ── 扉の板の箱と形 ──

    /// -90 度まで開いた扉の板は、蝶番から外廊下（+Z）へ 0.425 m 出た所に真ん中がある（閉じた板の半分の幅）。
    @Test
    def testLeafBoxSwingsIntoCorridor(): Unit \ {Assert, Fs.FileRead} =
        let c = Doors.leafBox(TestKit.room("202")#door, -90.0)#center;
        Assert.assertTrue(near(c#x, -3.675) and near(c#z, 0.445))

    /// 扉の形を回す行列は、閉じた板の箱の真ん中を、同じ角の板の箱の真ん中へ運ぶ（絵と当たり判定がずれない）。
    @Test
    def testTransformMatchesLeafBox(): Unit \ {Assert, Fs.FileRead} =
        let door = TestKit.room("202")#door;
        let moved = Mat4.apply(Doors.transformOf(door, -60.0), door#leaf#center);
        let box = Doors.leafBox(door, -60.0)#center;
        Assert.assertTrue(Vec3.length(Vec3.sub(moved, box)) < 0.001)

    // ── 体と扉 ──

    /// 扉の前（回る板の届く所）に立っていると、開けても体に当たる所で止まり、体に食い込まない（押し込まない）。
    @Test
    def testDoorStopsAtBody(): Unit \ {Assert, Fs.FileRead} =
        let door = TestKit.room("202")#door;
        let feet = Vec3.v3(-4.1, 3.1, 0.6);
        let s = Doors.stepTimes(doc(), door, body(), feet, dt(), 120, Doors.toggle(Doors.openTo(doc(), door), closed()));
        Assert.assertEq(expected = (Doors.Motion.Opening, true),
            (s#motion, Collider.deepestOverlap(Doors.leafBox(door, s#angle) :: Nil, body(), feet#x, feet#y, feet#z) <= 0.002))

    /// 扉の前で E を押して 2 秒じっとしていても、体は動かされない（回る扉は体を押しのけない）。
    @Test
    def testPressDoesNotMoveBody(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        let start = { walker = TestKit.standAt(env#boxes, -4.1, 3.1, 0.6, 180.0), doors = Doors.initialAll(env#rooms), light = PlayStep.Flashlight.Off };
        let pressed = PlayStep.step(env, { press = true | PlayStep.idle() }, TestKit.frame(), start);
        let after = PlayStep.simulate(env, PlayStep.idle(), TestKit.frame(), 120, pressed);
        Assert.assertEq(expected = (start#walker#x, start#walker#z, Doors.Motion.Opening),
            (after#walker#x, after#walker#z, Map.get("202", after#doors) |> Option.map(s -> s#motion) |> Option.getWithDefault(Doors.Motion.Still)))

    /// 閉じた扉へ向かって 1 秒歩いても外廊下（z > 0）から出られない。
    @Test
    def testClosedDoorBlocks(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        let start = { walker = TestKit.standAt(env#boxes, -4.1, 3.1, 0.6, 180.0), doors = Doors.initialAll(env#rooms), light = PlayStep.Flashlight.Off };
        let after = PlayStep.simulate(env, { drive = TestKit.forward(false) | PlayStep.idle() }, TestKit.frame(), 60, start);
        Assert.assertEq(expected = true, after#walker#z > 0.0)

    /// 開け切った扉へ向かって 1 秒歩くと、玄関の中（z < -0.5）へ入れる。
    @Test
    def testOpenDoorLetsYouIn(): Unit \ {Assert, Fs.FileRead} =
        let env = TestKit.env();
        let open = Map.insert("202", { angle = Doors.openTo(env#doors, TestKit.room("202")#door), motion = Doors.Motion.Still }, Doors.initialAll(env#rooms));
        let start = { walker = TestKit.standAt(env#boxes, -4.1, 3.1, 0.6, 180.0), doors = open, light = PlayStep.Flashlight.Off };
        let after = PlayStep.simulate(env, { drive = TestKit.forward(false) | PlayStep.idle() }, TestKit.frame(), 60, start);
        Assert.assertEq(expected = true, after#walker#z < -0.5)

    // ── 扉の音 ──

    /// 止まっていた扉が開き始めると開ける音・閉じ始めると軋み・閉じる途中から閉まり切ると閉まる音・回っている途中は鳴らない。
    @Test
    def testDoorSounds(): Unit \ Assert =
        let opening = { angle = -10.0, motion = Doors.Motion.Opening };
        let closing = { angle = -1.0, motion = Doors.Motion.Closing };
        let open = { angle = -90.0, motion = Doors.Motion.Still };
        Assert.assertEq(expected = (Some(Sounds.DoorSound.Open), Some(Sounds.DoorSound.Creak), Some(Sounds.DoorSound.Shut), None),
            (Sounds.doorShot(closed(), opening), Sounds.doorShot(open, { angle = -89.0 | closing }), Sounds.doorShot(closing, closed()),
             Sounds.doorShot(opening, { angle = -20.0 | opening })))
}
