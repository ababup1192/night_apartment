// Sounds — 夜のアパートの音（どの音をいつ・どれだけ鳴らすか。純粋）。音の中身は tools/sfx_build.py が録音素材から作る（make sfx）。
// 起きた音（1 歩踏み出した・扉が動いた・手の灯りを点けた・蛍光灯が瞬いた・室外機が回り出した・住人が壁に頭を打った）は前後の World から名前を導き、
// 続く音（場所の環境音・部屋の中の音・置いてある物の音）は今の World から宣言する。場所と時刻の規則は Soundscape。
// プレイヤーが鳴らす一発の音は、耳のいる場所の響きを畳み込んだ版（<名前>_<場所>）を選ぶ（engine にリアルタイムの響きが無いので）。
// 音量はバスで決める: 種類ごとのバス（足音・扉・手の灯り・環境音…）に Doc の大きさと遊ぶ人の音量（AudioPrefs）を掛け、
// 住人の音は人ごとのバス（p_<人>）で耳からの距離と壁を表す（mixerOf）。
mod Sounds {
    use fge::{App, AudioMixer, Vec3}

    /// 扉 1 枚の音: 開け始め（ノブと掛け金と蝶番）・閉め始めの軋み・閉まり切った音。
    pub enum DoorSound with Eq, ToString {
        case Open
        case Creak
        case Shut
    }

    /// 扉の音の名前の頭（場所の尻を付ける前）。
    def doorSoundName(d: DoorSound): String = match d {
        case DoorSound.Open  => "door_open"
        case DoorSound.Creak => "door_creak"
        case DoorSound.Shut  => "door_shut"
    }

    /// 足音の差分の数（tools/sfx_build.py の FOOTSTEPS の立ち上がりの数と同じ）。
    def stepVariants(): Int32 = 4

    /// 蛍光灯のジジッの差分の数。
    def zapVariants(): Int32 = 4

    /// 頭を打つ音の差分の数。
    def hitVariants(): Int32 = 3

    def floorInt(x: Float64): Int32 = Float64.tryToInt32(Float64.floor(x)) |> Option.getWithDefault(0)

    /// 耳の位置（目の高さ）。
    def earOf(res: Res.Res, w: World.World): Vec3.Vec3 =
        let b = World.walkerOf(w);
        Vec3.v3(b#x, Walker.eyeY(WalkDoc.rec(res#walk), b), b#z)

    /// 耳のいる場所（響きの版を選ぶ）。
    def spaceOf(res: Res.Res, w: World.World): Soundscape.Space =
        Soundscape.spaceAt(SoundDoc.rec(res#sound), res#stage#rooms, earOf(res, w))

    // ── 起きた音 ──

    /// 足音: 歩数が増えたら、足元の面の音（4 本の差分から、続けて同じ物にならないように）を耳のいる場所の響きで。
    pub def stepName(sound: SoundDoc.Rec, space: Soundscape.Space, before: Walker.Walker, after: Walker.Walker): Option[String] =
        if (after#steps <= before#steps) None
        else {
            let surface = Soundscape.surfaceAt(sound, Vec3.v3(after#x, after#feet, after#z));
            let k = Soundscape.variant(stepVariants(), 71, after#steps);
            Some("step_${surface}_${Int32.toString(k)}_${Soundscape.spaceName(space)}")
        }

    /// 扉 1 枚の音: 止まっていたのが開き始めたら開ける音・閉じ始めたら軋み・閉じる途中から閉まり切ったら閉まる音。
    pub def doorShot(before: Doors.State, after: Doors.State): Option[DoorSound] =
        if (before#motion == Doors.Motion.Still and after#motion == Doors.Motion.Opening) Some(DoorSound.Open)
        else if (before#motion != Doors.Motion.Closing and after#motion == Doors.Motion.Closing) Some(DoorSound.Creak)
        else if (before#motion == Doors.Motion.Closing and Doors.isClosed(after)) Some(DoorSound.Shut)
        else None

    /// 全部の扉の音（同じコマに同じ音は 1 回）。
    def doorShots(before: Map[String, Doors.State], after: Map[String, Doors.State]): List[DoorSound] =
        Map.toList(after) |> List.filterMap(e -> {
            let (id, s) = e;
            Map.get(id, before) |> Option.flatMap(b -> doorShot(b, s))
        }) |> List.distinct

    /// 手の灯りのスイッチ。
    def lightShot(before: World.World, after: World.World): Option[String] =
        if (World.isLightOn(before) == World.isLightOn(after)) None
        else Some(if (World.isLightOn(after)) "flash_on" else "flash_off")

    /// 点滅する蛍光灯のうち、聞こえる所の管で瞬きが始まったらジジッ（差分は秒で選ぶ）。
    def zapShot(res: Res.Res, ear: Vec3.Vec3, t0: Float64, t1: Float64): Option[String] =
        let range = SoundDoc.rec(res#sound)#shots#zapRange;
        let started = LightsDoc.rec(res#lights)#lamps |> List.exists(l ->
            Flicker.burstStarted(t0, t1, l) and Vec3.length(Vec3.sub(Vec3.v3(l#x, l#y, l#z), ear)) < range);
        if (started) Some("fluo_zap_${Int32.toString(Soundscape.variant(zapVariants(), 13, floorInt(t1 * 10.0)))}") else None

    /// 置いてある物が動き出した時の一発の音と、ごく稀な遠くの音。
    def placedShots(sound: SoundDoc.Rec, ear: Vec3.Vec3, t0: Float64, t1: Float64): List[String] =
        List.append(sound#machines |> List.filter(m -> Soundscape.machineStarted(m, ear, t0, t1)) |> List.map(m -> m#start),
                    sound#far |> List.filter(f -> Soundscape.farStarted(f, t0, t1)) |> List.map(f -> f#name))

    /// 起きた音の名前（読み込みの幕の間は鳴らさない）。
    pub def events(res: Res.Res, before: World.World, after: World.World): List[String] =
        if (Option.nonEmpty(World.loadingOf(after))) Nil
        else {
            let sound = SoundDoc.rec(res#sound);
            let space = spaceOf(res, after);
            let tail = Soundscape.spaceName(space);
            let ear = earOf(res, after);
            let t0 = World.seconds(before);
            let t1 = World.seconds(after);
            let player = List.flatten(
                (stepName(sound, space, World.walkerOf(before), World.walkerOf(after)) |> Option.toList)
                    :: (doorShots(World.doorsOf(before), World.doorsOf(after)) |> List.map(d -> "${doorSoundName(d)}_${tail}"))
                    :: (lightShot(before, after) |> Option.toList |> List.map(n -> "${n}_${tail}"))
                    :: Nil);
            List.flatten(player :: (zapShot(res, ear, t0, t1) |> Option.toList) :: placedShots(sound, ear, t0, t1)
                         :: personShots(res, before, after) :: Nil)
        }

    // ── 住人の音 ──

    /// 住人の出来事の音の名前（tools/sfx_build.py の名前と同じ字）: p_<人>_hit_<1..3>・p_<人>_stomp_l・p_<人>_step_<面>_r など。
    /// 頭を打つ音は出来事の秒で差分を選ぶ。音の無い出来事（道筋の区切りの印）は None。
    pub def personShot(id: String, ev: People.Event): Option[String] = match ev#name {
        case "hit"     => Some("p_${id}_hit_${Int32.toString(Soundscape.variant(hitVariants(), 29, floorInt(ev#t * 1000.0)))}")
        case "stomp_l" => Some("p_${id}_stomp_l")
        case "stomp_r" => Some("p_${id}_stomp_r")
        case "step_l"  => Some("p_${id}_step_${ev#surface |> Option.getWithDefault("concrete")}_l")
        case "step_r"  => Some("p_${id}_step_${ev#surface |> Option.getWithDefault("concrete")}_r")
        case _         => None
    }

    /// 前後の World の間に住人に起きた出来事の音: 部屋にいる人は遊びの時計の秒・階段の人は歩き出してからの秒で数える。
    def personShots(res: Res.Res, before: World.World, after: World.World): List[String] =
        let t0 = World.seconds(before);
        let t1 = World.seconds(after);
        res#residents |> List.flatMap(p -> {
            let e = p#entry;
            let (a, b) = if (People.isResident(e)) (t0, t1) else stairsSpan(t1 - t0, World.stairsTime(after));
            People.eventsBetween(e, a, b) |> List.filterMap(personShot(e#id))
        })

    /// 階段の人のこのコマの動きの秒の幅（歩いていなければ空の幅）。歩き出したコマは、歩き出した秒の直前から数える。
    def stairsSpan(dt: Float64, now: Option[Float64]): (Float64, Float64) = match now {
        case Some(t) => (t - dt, t)
        case None    => (0.0, 0.0)
    }

    /// 住人の音が聞こえる大きさの倍率（出来事の種類ごと。頭を打つ・地団駄・足音）。
    def kindVolume(doc: PeopleDoc.Sound, e: People.Entry): Float64 =
        let has = (n: String) -> List.exists(ev -> String.startsWith(prefix = n, ev#name), e#events);
        if (has("hit")) doc#hitVolume else if (has("stomp")) doc#stompVolume else if (has("step")) doc#stepVolume else 1.0

    /// 耳と住人の間の壁: (大きさの倍率, 高い音の残り具合)。同じ部屋にいる・部屋の無い所（階段）の人はそのまま、
    /// 扉が開いていれば籠もらせるだけ、閉じた扉や壁の向こうは小さく籠もらせる。
    pub def wallOf(res: Res.Res, w: World.World, ear: Vec3.Vec3, e: People.Entry): (Float64, Float64) =
        let doc = PeopleDoc.rec(res#people)#sound;
        let ajar = RoomsDoc.rec(res#rooms)#draw#ajarDeg;
        match res#stage#rooms |> List.find(r -> r#id == e#room) {
            case None => (1.0, 1.0)
            case Some(r) =>
                if (Rooms.roomAt(res#stage#rooms, ear) == Some(r#id)) (1.0, 1.0)
                else if (Float64.abs(World.doorAngle(r, w)) >= ajar) (1.0, doc#doorHF)
                else (doc#wallVolume, doc#wallHF)
        }

    /// 住人ごとのバス: 音量を耳からの距離と壁で、高い音の残り具合を壁で決める。
    def peopleBuses(res: Res.Res, w: World.World, ear: Vec3.Vec3, effects: Float64): List[AudioMixer.Bus] =
        let doc = PeopleDoc.rec(res#people)#sound;
        res#residents |> List.map(p -> {
            let e = p#entry;
            let at = People.feetAt(e, World.stairsTime(w) |> Option.getWithDefault(0.0));
            let source = Vec3.add(at, Vec3.v3(0.0, 1.0, 0.0));
            let (wall, hf) = wallOf(res, w, ear, e);
            { name = "p_${e#id}", volume = effects * kindVolume(doc, e) * wall * Soundscape.falloff(Vec3.length(Vec3.sub(source, ear)), doc#range),
              lowpassGainHF = hf }
        })

    // ── 音の通り道 ──

    /// 蛍光灯の音（ジジッ）が聞こえる大きさ: 点滅する管のうち、いちばん近い管の距離で決める
    /// （瞬いている管だけで決めると、鳴った瞬間にバスが 0 から上がり始めて頭が欠ける）。
    def zapGain(res: Res.Res, ear: Vec3.Vec3): Float64 =
        let range = SoundDoc.rec(res#sound)#shots#zapRange;
        Flicker.flickering(LightsDoc.rec(res#lights)#lamps)
            |> List.map(e -> { let l = snd(e); Soundscape.falloff(Vec3.length(Vec3.sub(Vec3.v3(l#x, l#y, l#z), ear)), range) })
            |> List.foldLeft(Float64.max, 0.0)

    /// 遠くの音が場所ごとにどれだけ聞こえるか（建物の中ほど小さい）。
    def farWeight(ws: Soundscape.Weights): Float64 = ws#outdoor + 0.8 * ws#corridor + 0.9 * ws#stairs + 0.35 * ws#room

    def bus(name: String, volume: Float64, hf: Float64): AudioMixer.Bus = { name = name, volume = volume, lowpassGainHF = hf }

    def route(name: String, prefixes: List[String]): AudioMixer.Route = { bus = name, prefixes = prefixes }

    /// 音の通り道: 種類ごとのバスに Doc の大きさと遊ぶ人の音量を掛け、住人の音は人ごとのバスへ。
    /// 部屋の中では、屋外から届く音（環境音・電線・変圧器・遠くの音）の高い音を削る。
    pub def mixerOf(res: Res.Res, w: World.World): AudioMixer.Mixer =
        let sound = SoundDoc.rec(res#sound);
        let prefs = World.prefsOf(w);
        let fx = AudioPrefs.effectsGain(prefs);
        let amb = AudioPrefs.ambienceGain(prefs);
        let ear = earOf(res, w);
        let t = World.seconds(w);
        let ws = Soundscape.weightsAt(sound, res#stage#rooms, ear);
        let outsideHF = 1.0 - (1.0 - sound#beds#roomHF) * ws#room;
        let people = peopleBuses(res, w, ear, fx);
        let kinds =
            bus("sfx", fx, 1.0) :: bus("steps", sound#shots#steps * fx, 1.0) :: bus("door", sound#shots#doors * fx, 1.0)
                :: bus("flash", sound#shots#flash * fx, 1.0) :: bus("zap", sound#shots#zap * zapGain(res, ear) * amb, 1.0)
                :: bus("amb", amb, 1.0) :: bus("amb_out", amb, outsideHF) :: Nil;
        let starts = sound#machines |> List.filter(m -> not String.isEmpty(m#start))
            |> List.map(m -> bus(m#start, m#startVolume * Soundscape.startGain(m, ear, t + 0.3) * amb, 1.0));
        let far = sound#far |> List.map(f -> bus(f#name, f#volume * farWeight(ws) * amb, outsideHF));
        let routes =
            route("steps", "step_" :: Nil) :: route("door", "door_" :: Nil) :: route("flash", "flash_" :: Nil)
                :: route("zap", "fluo_zap" :: Nil) :: route("amb", "amb_corridor" :: "amb_stairs" :: "room_" :: "m_" :: Nil)
                :: route("amb_out", "amb_outdoor" :: "m_wires" :: "m_transformer" :: Nil) :: Nil;
        { buses = List.flatten(people :: kinds :: starts :: far :: Nil),
          routes = List.flatten(routes :: (people |> List.map(b -> route(b#name, "${b#name}_" :: Nil)))
                                :: (List.append(starts, far) |> List.map(b -> route(b#name, b#name :: Nil))) :: Nil),
          defaultBus = "sfx", ducks = Nil, cooldowns = Nil, snapshots = Nil, transitionSeconds = 0.15 }

    // ── 続く音 ──

    /// 点いている蛍光灯のうなりが聞こえる大きさ（消えた管は鳴らない）。
    def lampHum(res: Res.Res, ear: Vec3.Vec3): Float64 =
        let range = SoundDoc.rec(res#sound)#beds#lampRange;
        LightsDoc.rec(res#lights)#lamps
            |> List.filter(l -> l#state == LightsDoc.LampState.On or l#state == LightsDoc.LampState.Dim)
            |> List.map(l -> Soundscape.falloff(Vec3.length(Vec3.sub(Vec3.v3(l#x, l#y, l#z), ear)), range))
            |> List.foldLeft(Float64.max, 0.0)

    /// 場所の環境音（ずっと小さく）: 屋外の夜（他の場所では小さく）・外廊下の蛍光灯のうなり・外階段を抜ける風。
    def beds(res: Res.Res, ws: Soundscape.Weights, ear: Vec3.Vec3): List[Soundscape.Voice] =
        let b = SoundDoc.rec(res#sound)#beds;
        { name = "amb_outdoor", volume = b#outdoor * (ws#outdoor + b#outdoorInCorridor * ws#corridor + b#outdoorInStairs * ws#stairs + b#outdoorInRoom * ws#room) }
            :: { name = "amb_corridor", volume = b#corridor * ws#corridor * lampHum(res, ear) }
            :: { name = "amb_stairs", volume = b#stairs * ws#stairs } :: Nil

    /// 耳のいる部屋の中の音（冷蔵庫・時計・換気扇）。
    def roomVoices(res: Res.Res, ws: Soundscape.Weights, ear: Vec3.Vec3): List[Soundscape.Voice] =
        match Soundscape.roomDepth(res#stage#rooms, ear) {
            case None => Nil
            case Some((id, _)) =>
                SoundDoc.rec(res#sound)#roomLoops |> List.filter(l -> l#room == id) |> List.map(l -> { name = l#loop, volume = l#volume * ws#room })
        }

    /// 鳴り続ける音と大きさ（読み込み中は鳴らさない。ほとんど聞こえない物は宣言しない）。
    pub def hums(res: Res.Res, w: World.World): List[App.Sustain] =
        if (Option.nonEmpty(World.loadingOf(w))) Nil
        else {
            let sound = SoundDoc.rec(res#sound);
            let ear = earOf(res, w);
            let t = World.seconds(w);
            let ws = Soundscape.weightsAt(sound, res#stage#rooms, ear);
            List.flatten(beds(res, ws, ear) :: roomVoices(res, ws, ear) :: (sound#machines |> List.flatMap(m -> Soundscape.machineVoices(m, ear, t))) :: Nil)
                |> List.filter(v -> v#volume > 0.0005)
                |> List.map(v -> { name = v#name, volume = Float64.min(1.0, v#volume), pitch = 1.0 })
        }
}
