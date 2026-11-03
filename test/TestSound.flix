// 音の規則のテスト: 足音の面と響きの場所・差分が続けて同じにならない・置いてある物が全部同時には回らず近い順に鳴る・
// 遊ぶ人の音量（保存と読み戻し・0 で鳴らない）・音量の窓（開く・閉じる・キャプチャ中は出ない・バーを押した値になる・撮る絵には出ない）。
// 面と場所の範囲は night.sound.json と同じ値の SoundDoc.defaults から。
mod TestSound {
    use fge::{App, GameEngine, Vec2, Vec3}

    def sound(): SoundDoc.Rec = SoundDoc.rec(SoundDoc.defaults())

    def res(): Res.Res = Res.build(TestRules.docs())

    def screen(): Vec2.Vec2 = { x = World.width(), y = World.height() }

    /// キーを押さず、cursor を押す（click）か押さないフレーム。
    def clickAt(cursor: Vec2.Vec2, click: Bool): App.Frame =
        App.frameOf({ prev = Set.empty() }, { current = Set.empty() }, 1.0 / 60.0, screen(),
                    { prevCursor = None, cursor = cursor }, { prevDown = false, down = click, wheel = 0.0 })

    /// keys を押したフレーム（マウスは押さない）。
    def keysDown(keys: Set[GameEngine.Key]): App.Frame =
        App.frameOf({ prev = Set.empty() }, { current = keys }, 1.0 / 60.0, screen(),
                    { prevCursor = None, cursor = { x = 240.0, y = 135.0 } }, { prevDown = false, down = false, wheel = 0.0 })

    // ── Doc ──

    /// night.sound.json を読むと、置いてある物の群れ 7 つと、室外機 18 台・給湯器 18 台の置き場所がそろう（置き場所の列を群れの名前で集める）。
    @Test
    def testSoundDocGathersSpots(): Unit \ {Assert, Fs.FileRead} =
        let doc = SoundDoc.rec(SoundDoc.load(SoundDoc.path()));
        let spotsOf = name -> doc#machines |> List.find(m -> m#name == name) |> Option.map(m -> List.length(m#spots));
        Assert.assertEq(expected = (7, Some(18), Some(18)), (List.length(doc#machines), spotsOf("ac"), spotsOf("heater")))

    // ── 面と場所 ──

    /// 足元の面: 外階段は鉄・敷地は土・203 の奥の部屋は畳・203 の台所は板の間・外廊下はコンクリート。
    @Test
    def testSurfaceFollowsFloor(): Unit \ Assert =
        Assert.assertEq(expected = ("metal", "dirt", "tatami", "wood", "concrete"),
            (Soundscape.surfaceAt(sound(), Vec3.v3(-18.3, 1.7, -2.0)), Soundscape.surfaceAt(sound(), Vec3.v3(-6.0, 0.0, 3.0)),
             Soundscape.surfaceAt(sound(), Vec3.v3(-8.5, 3.2, -5.0)), Soundscape.surfaceAt(sound(), Vec3.v3(-8.5, 3.2, -2.5)),
             Soundscape.surfaceAt(sound(), Vec3.v3(-8.0, 3.1, 0.6))))

    /// 耳のいる場所: 外階段・外廊下・道路（部屋の無い舞台）。
    @Test
    def testSpaceFollowsEar(): Unit \ Assert =
        Assert.assertEq(expected = (Soundscape.Space.Stairs, Soundscape.Space.Corridor, Soundscape.Space.Outdoor),
            (Soundscape.spaceAt(sound(), Nil, Vec3.v3(-18.3, 2.5, -1.0)), Soundscape.spaceAt(sound(), Nil, Vec3.v3(-8.0, 4.6, 0.6)),
             Soundscape.spaceAt(sound(), Nil, Vec3.v3(-6.0, 1.6, 8.0))))

    /// 場所の重みは境目でなめらかに移る: 外廊下の縁（z = 1.25）の上ではちょうど半分ずつ。
    @Test
    def testWeightsBlendAtEdge(): Unit \ Assert =
        let ws = Soundscape.weightsAt(sound(), Nil, Vec3.v3(-8.0, 4.6, 1.25));
        Assert.assertEq(expected = (0.5, 0.5), (ws#corridor, ws#outdoor))

    // ── 足音 ──

    /// 歩数が増えたコマだけ、足元の面と耳のいる場所の響きの足音が鳴る（外階段なら鉄の・階段の響き）。
    @Test
    def testStepSoundFollowsSurfaceAndSpace(): Unit \ Assert =
        let stair = Walker.standing(-18.3, 1.7, -2.0, 0.0);
        let k = Soundscape.variant(4, 71, 1);
        Assert.assertEq(expected = (Some("step_metal_${Int32.toString(k)}_stairs"), None),
            (Sounds.stepName(sound(), Soundscape.Space.Stairs, stair, { steps = 1 | stair }), Sounds.stepName(sound(), Soundscape.Space.Stairs, stair, stair)))

    /// 足音の差分は、続けて同じ物にならない（500 歩）。
    @Test
    def testStepVariantsNeverRepeat(): Unit \ Assert =
        Assert.assertEq(expected = false, List.range(0, 500) |> List.exists(k -> Soundscape.variant(4, 71, k) == Soundscape.variant(4, 71, k + 1)))

    // ── 置いてある物 ──

    /// 周期の半分だけ動く室外機 4 台。
    def acUnits(): SoundDoc.Machine =
        { name = "ac", loop = "m_ac_run", slots = 3, volume = 1.0, range = 10.0, period = 300.0, duty = 0.5, seed = 11,
          start = "m_ac_start", startVolume = 1.0,
          spots = { x = 0.0, y = 0.0, z = 0.0 } :: { x = 3.0, y = 0.0, z = 0.0 } :: { x = 6.0, y = 0.0, z = 0.0 } :: { x = 9.0, y = 0.0, z = 0.0 } :: Nil }

    /// 室外機は全部が同時には回らない: 1 台目が回っていて 2 台目が止まっている秒がある。
    @Test
    def testMachinesTakeTurns(): Unit \ Assert =
        let m = acUnits();
        Assert.assertEq(expected = true,
            List.range(0, 600) |> List.exists(s -> {
                let t = Int32.toFloat64(s);
                Option.nonEmpty(Soundscape.runOf(m, 0, t)) and Option.isEmpty(Soundscape.runOf(m, 1, t))
            }))

    /// いつも動いている物は、近い順に slots 台まで、距離で小さくなる大きさで鳴る（0 m で 1・5 m で 1/4・8 m の 3 台目は鳴らさない）。
    @Test
    def testMachineVoicesKeepNearest(): Unit \ Assert =
        let m = { duty = 1.0, slots = 2, spots = { x = 8.0, y = 0.0, z = 0.0 } :: { x = 0.0, y = 0.0, z = 0.0 } :: { x = 5.0, y = 0.0, z = 0.0 } :: Nil | acUnits() };
        let voices = Soundscape.machineVoices(m, Vec3.v3(0.0, 0.0, 0.0), 10.0);
        Assert.assertEq(expected = (Some(("m_ac_run_1", 1.0)), Some(("m_ac_run_2", 0.25)), 2),
            (List.nth(0, voices) |> Option.map(v -> (v#name, v#volume)), List.nth(1, voices) |> Option.map(v -> (v#name, v#volume)), List.length(voices)))

    /// いつも動いている物は、動き出しの一発の音を鳴らさない。
    @Test
    def testAlwaysOnMachineNeverStarts(): Unit \ Assert =
        let m = { duty = 1.0 | acUnits() };
        Assert.assertEq(expected = false, List.range(0, 600) |> List.exists(s -> Soundscape.machineStarted(m, Vec3.v3(0.0, 0.0, 0.0), Int32.toFloat64(s), Int32.toFloat64(s) + 1.0)))

    // ── 遊ぶ人の音量 ──

    /// 保存した字から、同じ音量が読み戻る。
    @Test
    def testPrefsRoundTrip(): Unit \ Assert =
        let p = { master = 0.3, ambience = 0.0, effects = 0.75 };
        Assert.assertEq(expected = Some((0.3, 0.0, 0.75)), AudioPrefs.fromJson(AudioPrefs.toText(p)) |> Option.map(q -> (q#master, q#ambience, q#effects)))

    /// 音量は 0..1 に収まる。
    @Test
    def testPrefsStayInRange(): Unit \ Assert =
        let p = AudioPrefs.defaults();
        Assert.assertEq(expected = (1.0, 0.0),
            (AudioPrefs.nudge(AudioPrefs.Channel.Master, 0.5, p)#master, AudioPrefs.set(AudioPrefs.Channel.Ambience, -0.3, p)#ambience))

    /// 全体の音量を 0 にすると、どのバスも鳴らない。
    @Test
    def testMuteSilencesEveryBus(): Unit \ Assert =
        let w = World.setVolume(AudioPrefs.Channel.Master, 0.0, World.initial(res()));
        Assert.assertEq(expected = false, Sounds.mixerOf(res(), w)#buses |> List.exists(b -> b#volume > 0.0))

    /// 効果音を 0 にしても、環境音のバスはそのまま。
    @Test
    def testEffectsZeroKeepsAmbience(): Unit \ Assert =
        let w = World.setVolume(AudioPrefs.Channel.Effects, 0.0, World.initial(res()));
        let busVolume = name -> Sounds.mixerOf(res(), w)#buses |> List.find(b -> b#name == name) |> Option.map(b -> b#volume);
        Assert.assertEq(expected = (Some(0.0), Some(1.0)), (busVolume("steps"), busVolume("amb")))

    // ── 音量の窓 ──

    /// 隅の印を押すと窓が開き、窓の外を押すと閉じる（閉じる時にマウスをキャプチャしない）。
    @Test
    def testVolumeMenuOpensAndCloses(): Unit \ Assert =
        let r = res();
        let opened = Controls.step(clickAt(VolumeView.iconCenter(), true), r, World.initial(r));
        let closed = Controls.step(clickAt({ x = 100.0, y = 100.0 }, true), r, opened);
        Assert.assertEq(expected = (true, false, false), (World.isVolumeOpen(opened), World.isVolumeOpen(closed), World.isLooking(closed)))

    /// volume のキー（M）でも開け閉めでき、開いている間の Esc は終了の確認を出さずに窓を閉じる。
    @Test
    def testVolumeKeyAndEscape(): Unit \ Assert =
        let r = res();
        let opened = Controls.step(keysDown(Set#{GameEngine.Key.M}), r, World.initial(r));
        let escaped = Controls.step(keysDown(Set#{GameEngine.Key.Escape}), r, opened);
        Assert.assertEq(expected = (true, false, false), (World.isVolumeOpen(opened), World.isVolumeOpen(escaped), World.isAskingQuit(escaped)))

    /// 窓の効果音のバーの 3 割の所を押すと、効果音の音量が 0.3 になる。
    @Test
    def testBarClickSetsValue(): Unit \ Assert =
        let r = res();
        let opened = World.toggleVolume(World.initial(r));
        let clicked = Controls.step(clickAt(VolumeView.barPoint(AudioPrefs.Channel.Effects, 0.3), true), r, opened);
        Assert.assertEq(expected = (0.3, true), (World.prefsOf(clicked)#effects, World.isVolumeOpen(clicked)))

    /// 開いている間は ← で選んでいる行（初めは全体）が 1 段下がり、歩かない。
    @Test
    def testArrowNudgesWithoutWalking(): Unit \ Assert =
        let r = res();
        let opened = World.toggleVolume(World.initial(r));
        let nudged = Controls.step(keysDown(Set#{GameEngine.Key.Left}), r, opened);
        Assert.assertEq(expected = (0.9, World.walkerOf(opened)#yaw), (World.prefsOf(nudged)#master, World.walkerOf(nudged)#yaw))

    /// マウスをキャプチャしている間は、印も窓も出ない（開いていた窓は閉じる）。
    @Test
    def testVolumeHiddenWhileCapturing(): Unit \ Assert =
        let r = res();
        let looking = World.setLooking(true, World.toggleVolume(World.initial(r)));
        Assert.assertEq(expected = (false, false, true),
            (World.showsVolumeIcon(looking), World.isVolumeOpen(World.setLooking(false, looking)), Option.isEmpty(View.inputOf(r, looking)#volume)))

    /// 動画と静止画に撮る時は、マウスを放していても印を描かない。
    @Test
    def testCaptureHidesVolume(): Unit \ Assert =
        let r = res();
        let w = World.initial(r);
        Assert.assertEq(expected = (true, true), (Option.nonEmpty(View.inputOf(r, w)#volume), Option.isEmpty(View.inputForCapture(r, w)#volume)))
}
