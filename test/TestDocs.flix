// Doc とプログラムの橋渡し: 壊れた JSON は既定値に落ちる・1 欄だけ書いた JSON はその値が入る・一覧の行の数に追随する。
mod TestDocs {

    /// 壊れた JSON はどの Doc も読めない（呼ぶ側の load が既定値へ落とす）。
    @Test
    def testBrokenJsonFallsBack(): Unit \ Assert =
        Assert.assertEq(expected = (true, true, true, true, true),
            (Option.isEmpty(WalkDoc.fromJson("{")), Option.isEmpty(LookDoc.fromJson("{")), Option.isEmpty(LightsDoc.fromJson("{")),
             Option.isEmpty(SoundDoc.fromJson("{")), Option.isEmpty(TourDoc.fromJson("{"))))

    /// 1 欄だけ書いた JSON: その欄だけ替わり、ほかは既定のまま。
    @Test
    def testOneFieldOverrides(): Unit \ Assert =
        let walk = WalkDoc.fromJson("{\"runSpeed\": 5.0}") |> Option.map(WalkDoc.rec);
        let look = LookDoc.fromJson("{\"fogFar\": 30.0}") |> Option.map(LookDoc.rec);
        Assert.assertEq(expected = (Some((5.0, WalkDoc.rec(WalkDoc.defaults())#walkSpeed)), Some((30.0, LookDoc.rec(LookDoc.defaults())#fogNear))),
            (walk |> Option.map(w -> (w#runSpeed, w#walkSpeed)), look |> Option.map(l -> (l#fogFar, l#fogNear))))

    /// 蛍光灯の行の数に追随し、置き場所の無い行は捨てる。状態と点滅の形は字から読む。
    @Test
    def testLampRowsFollowJson(): Unit \ Assert =
        let doc = LightsDoc.fromJson("{\"lamps\": [{\"name\":\"a\",\"x\":1,\"y\":2,\"z\":3,\"state\":\"dying\",\"flicker\":\"sputter\"}, {\"name\":\"b\",\"x\":1}, {\"name\":\"c\",\"x\":0,\"y\":0,\"z\":0}]}");
        Assert.assertEq(expected = Some(("a" :: "c" :: Nil, LightsDoc.LampState.Dying, LightsDoc.FlickerKind.Sputter)),
            doc |> Option.map(LightsDoc.rec) |> Option.flatMap(r -> List.head(r#lamps) |> Option.map(l -> (r#lamps |> List.map(x -> x#name), l#state, l#flicker))))

    /// 道筋の点の行の数に追随し、x・z の無い行は捨てる。lookYaw の無い点は向きを替えない。
    @Test
    def testTourPointsFollowJson(): Unit \ Assert =
        let doc = TourDoc.fromJson("{\"points\": [{\"name\":\"p\",\"x\":1,\"z\":2}, {\"name\":\"q\",\"x\":1}, {\"name\":\"r\",\"x\":3,\"z\":4,\"lookYaw\":90}]}");
        Assert.assertEq(expected = Some(("p" :: "r" :: Nil, None)),
            doc |> Option.map(TourDoc.rec) |> Option.map(r -> (r#points |> List.map(p -> p#name), List.head(r#points) |> Option.flatMap(p -> p#lookYaw))))

    /// 実際の assets の蛍光灯は 20 本（4 階 × 5 戸）で、点滅するのは 5 本。
    @Test
    def testAssetsHaveTwentyLamps(): Unit \ {Assert, Fs.FileRead} =
        let lamps = LightsDoc.rec(LightsDoc.load(LightsDoc.path()))#lamps;
        Assert.assertEq(expected = (20, 5), (List.length(lamps), List.length(Flicker.flickering(lamps))))

    /// 部屋の Doc: 壊れた JSON は読めず、扉の速さだけ書いた JSON はその値が入り、ほかの欄（開け切る角・描く距離）は既定のまま。
    @Test
    def testRoomsDocOneField(): Unit \ Assert =
        let d = RoomsDoc.rec(RoomsDoc.defaults());
        Assert.assertEq(expected = (true, Some((30.0, d#door#openDeg, d#draw#seeRange))),
            (Option.isEmpty(RoomsDoc.fromJson("{")),
             RoomsDoc.fromJson("{\"door\": {\"speedDeg\": 30.0}}") |> Option.map(RoomsDoc.rec) |> Option.map(r -> (r#door#speedDeg, r#door#openDeg, r#draw#seeRange))))

    /// 道筋の点の press と light: 書いた点だけ E を押し・手の灯りを替え、書かない点は押さず替えない。
    @Test
    def testTourPressAndLight(): Unit \ Assert =
        let doc = TourDoc.fromJson("{\"points\": [{\"name\":\"p\",\"x\":1,\"z\":2,\"press\":true,\"light\":false}, {\"name\":\"q\",\"x\":1,\"z\":3}]}");
        Assert.assertEq(expected = Some((true, PlayStep.LightCue.TurnOff) :: (false, PlayStep.LightCue.Keep) :: Nil),
            doc |> Option.map(TourDoc.rec) |> Option.map(r -> r#points |> List.map(p -> (p#press, p#light))))

    /// 住人の Doc: 壊れた JSON は読めず、階段の人の歩き出す秒だけ書いた JSON はその値が入り、ほかの欄（範囲・音の距離）は既定のまま。
    @Test
    def testPeopleDocOneField(): Unit \ Assert =
        let d = PeopleDoc.rec(PeopleDoc.defaults());
        Assert.assertEq(expected = (true, Some((5.0, d#stairs#trigger#minX, d#sound#range))),
            (Option.isEmpty(PeopleDoc.fromJson("{")),
             PeopleDoc.fromJson("{\"stairs\": {\"startS\": 5.0}}") |> Option.map(PeopleDoc.rec) |> Option.map(r -> (r#stairs#startS, r#stairs#trigger#minX, r#sound#range))))

    /// 手の灯りの縁で暗くなり始める角と、マウスの上下の反転は JSON の値が入る。
    @Test
    def testFlashlightInnerConeAndInvertY(): Unit \ Assert =
        Assert.assertEq(expected = (Some(9.0), Some(true)),
            (LightsDoc.fromJson("{\"flashlight\": {\"innerConeDeg\": 9.0}}") |> Option.map(d -> LightsDoc.rec(d)#flashlight#innerConeDeg),
             WalkDoc.fromJson("{\"invertY\": true}") |> Option.map(d -> WalkDoc.rec(d)#invertY)))
}
