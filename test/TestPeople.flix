// 住人のテスト: 書き出しの読み方・置き場所が箱と重ならない・出来事の秒と音・階段の人は 1 回だけ・カプセルを通り抜けない・音の壁。
// 置き場所・出来事の秒・カプセルは書き出しの manifest.json の people（headbanger の hit は 0.9333 秒ほか 5 回・7.4 秒のループ、
// stomper の stomp_l は 0.3 と 0.9333 秒ほか、stairwalker は 26.433 秒 1 回きり）。
mod TestPeople {
    use fge::{AnimationClip3d, CollisionWorld3d, Skin3d, Vec3}

    def entries(): List[People.Entry] \ Fs.FileRead = People.entriesOf(TestKit.manifest())

    def entry(id: String): People.Entry \ Fs.FileRead =
        match entries() |> List.find(e -> e#id == id) {
            case Some(e) => e
            case None    => bug!("住人 ${id} が書き出しに無い")
        }

    def dt(): Float64 = 1.0 / 60.0

    // ── 書き出しの読み方 ──

    /// manifest の住人は 4 人。階段の人だけが 1 回きり（ループしない）で root motion、ほかの 3 人はその場でループする。
    @Test
    def testManifestListsFourPeople(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = ("headbanger", true, false) :: ("stairwalker", false, true) :: ("stomper", true, false) :: ("swayer", true, false) :: Nil,
            entries() |> List.map(e -> (e#id, e#loop, e#rootMotion)))

    /// 置き場所は glTF の x を反転した engine の座標（204 の男性は glTF (12.25, 3.25, -2.6251) → (-12.25, 3.25, -2.6251)）。
    @Test
    def testPositionIsMirroredFromGltf(): Unit \ {Assert, Fs.FileRead} =
        let p = entry("headbanger")#position;
        Assert.assertEq(expected = (-12.25, 3.25, -2.6251), (p#x, p#y, p#z))

    /// 4 人とも形・骨・動きつきで読め、骨は 53 本・動きの長さは manifest の duration_s と同じ秒（7.4・26.433・4.8・6.4 を 0.1 秒に丸めて）。
    @Test
    def testResidentsLoadWithSkinAndClip(): Unit \ {Assert, Fs.FileRead, IO} =
        Assert.assertEq(expected = (53, 7.4) :: (53, 26.4) :: (53, 4.8) :: (53, 6.4) :: Nil,
            TestKit.residents() |> List.map(p -> (Skin3d.jointCount(p#skin), Float64.round(AnimationClip3d.duration(p#clip) * 10.0) / 10.0)))

    // ── 置き場所 ──

    /// 部屋にいる 3 人のカプセル（段の高さより上）は、舞台の当たり判定の箱のどれにも食い込まない。
    @Test
    def testResidentsDoNotOverlapBoxes(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = ("headbanger", 0.0) :: ("stomper", 0.0) :: ("swayer", 0.0) :: Nil,
            People.placementOverlaps(Collider.worldOf(TestKit.statics(), TestKit.walk()), TestKit.walk()#stepHeight, entries()))

    // ── 出来事の秒 ──

    /// 頭を打つ男性の hit は 1 周（0〜7.4 秒）に 5 回・次の周（7.4〜14.8 秒）にも 5 回・0.93〜0.94 秒の 1 コマに 1 回。
    @Test
    def testHitsRepeatEveryLoop(): Unit \ {Assert, Fs.FileRead} =
        let e = entry("headbanger");
        Assert.assertEq(expected = (5, 5, 1),
            (List.length(People.eventsBetween(e, 0.0, 7.4)), List.length(People.eventsBetween(e, 7.4, 14.8)),
             List.length(People.eventsBetween(e, 0.93, 0.94))))

    /// 階段の人の足音の名前は、足が着いた面で替わる（2.2667 秒は鉄の左・22.8 秒はコンクリートの右・24.0 秒は地面の右）。
    @Test
    def testStepSoundFollowsSurface(): Unit \ {Assert, Fs.FileRead} =
        let e = entry("stairwalker");
        Assert.assertEq(expected = "p_stairwalker_step_steel_l" :: "p_stairwalker_step_concrete_r" :: "p_stairwalker_step_ground_r" :: Nil,
            List.flatten(People.eventsBetween(e, 2.2, 2.3) :: People.eventsBetween(e, 22.75, 22.85) :: People.eventsBetween(e, 23.95, 24.05) :: Nil)
                |> List.filterMap(Sounds.personShot(e#id)))

    /// 遊びの時計が 0.9 → 0.95 秒に進んだコマで、頭を打つ音（0.9333 秒。3 本の差分のうち、その秒で選ぶ 2 本目）と地団駄の左足（0.9333 秒）が鳴り、
    /// 0.95 → 1.0 秒のコマでは鳴らない。
    @Test
    def testHitAndStompSoundOnTheirSeconds(): Unit \ {Assert, Fs.FileRead, IO} =
        let res = TestKit.peopleRes();
        let w0 = World.initial(res) |> World.advancedBy(0.9);
        let w1 = World.advancedBy(0.05, w0);
        let w2 = World.advancedBy(0.05, w1);
        Assert.assertEq(expected = ("p_headbanger_hit_2" :: "p_stomper_stomp_l" :: Nil, Nil),
            (Sounds.events(res, w0, w1), Sounds.events(res, w1, w2)))

    // ── 階段の人 ──

    /// 階段の人は、足元が歩き出す範囲（1 階の段板 A の下）に入ったコマで歩き出し、動きの長さを過ぎると消え、
    /// 範囲に居続けても二度と歩き出さない。道路の端に立っている間は歩き出さない。
    @Test
    def testStairwalkerWalksOnlyOnce(): Unit \ {Assert, Fs.FileRead, IO} =
        let res = TestKit.peopleRes();
        let start = World.initial(res);
        let foot = World.placeWalker(res, { x = -17.68, y = 0.3, z = 0.75 }, 180.0, 0.0, start);
        let walking = World.stepTimes(res, TestKit.noInput(), dt(), 1, foot);
        let gone = World.stepTimes(res, TestKit.noInput(), 30.0, 1, walking);
        let stayed = World.stepTimes(res, TestKit.noInput(), dt(), 60, gone);
        Assert.assertEq(expected = ("Waiting", "Walking", "Gone", "Gone"),
            (TestKit.stairsName(World.stairsOf(World.stepTimes(res, TestKit.noInput(), dt(), 1, start))),
             TestKit.stairsName(World.stairsOf(walking)), TestKit.stairsName(World.stairsOf(gone)), TestKit.stairsName(World.stairsOf(stayed))))

    /// 段板 A に立ち止まっている体に、降りてくる階段の人（19〜21 秒）がぶつかっても、体は人のカプセルの外へ押し出され、舞台の箱にも食い込まない。
    @Test
    def testStairwalkerPushesStandingBody(): Unit \ {Assert, Fs.FileRead, IO} =
        let res = TestKit.peopleRes();
        let placed = World.placeWalker(res, { x = -17.915, y = 1.1, z = -1.0 }, 180.0, 0.0, World.initial(res)) |> World.withStairsAt(19.0);
        let after = World.stepTimes(res, TestKit.noInput(), dt(), 120, placed);
        let b = World.walkerOf(after);
        let walk = TestKit.walk();
        Assert.assertEq(expected = (Some(true), true),
            (World.stairwalkerBox(res, after) |> Option.map(bx -> Walker.overlapDepth(CollisionWorld3d.empty(), bx :: Nil, walk, b) < 0.01),
             Walker.overlapDepth(Collider.worldOf(TestKit.statics(), walk), Nil, walk, b) < 0.02))

    // ── カプセル ──

    /// 頭を打つ男性（x = -12.25）へ横から 3 秒歩き続けても、体はカプセルの手前（半径 0.22 + 体の半径 0.22）で止まり、通り抜けない。
    @Test
    def testBodyStopsAtResidentCapsule(): Unit \ {Assert, Fs.FileRead, IO} =
        let res = TestKit.peopleRes();
        let env = Res.playEnv(res);
        let start = { walker = TestKit.standAt(env#world, -11.4, 3.25, -2.6, 270.0), doors = Map.empty(), light = PlayStep.Flashlight.Off, seen = None };
        let moved = PlayStep.simulate(env, { drive = TestKit.forward(false) | PlayStep.idle() }, TestKit.frame(), 180, start);
        Assert.assertTrue(moved#walker#x > -12.25 + 0.22 + 0.22 - 0.01)

    // ── 音の壁 ──

    /// 頭を打つ男性の音: 204 の中で聞けばそのまま・開きかけの扉（初めの角 -14 度）の外の外廊下では籠もるだけ・階段の人の音はいつもそのまま。
    @Test
    def testWallMufflesOtherRooms(): Unit \ {Assert, Fs.FileRead, IO} =
        let res = TestKit.peopleRes();
        let w = World.initial(res);
        let doc = PeopleDoc.rec(res#people)#sound;
        let hb = TestKit.person(res, "headbanger")#entry;
        let sw = TestKit.person(res, "stairwalker")#entry;
        Assert.assertEq(expected = ((1.0, 1.0), (1.0, doc#doorHF), (1.0, 1.0)),
            (Sounds.wallOf(res, w, Vec3.v3(-11.8, 4.8, -3.0), hb), Sounds.wallOf(res, w, Vec3.v3(-11.8, 4.7, 0.8), hb),
             Sounds.wallOf(res, w, Vec3.v3(-11.8, 4.7, 0.8), sw)))
}
