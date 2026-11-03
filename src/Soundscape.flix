// Soundscape — 音の場所と時刻の規則（純粋）: 耳がどの場所にいるか（響きと環境音を選ぶ）・足元の面・
// 置いてある物（室外機・給湯器・自販機・変圧器・電線・換気扇・隣の生活音）がいつ動いていて、どれだけ聞こえるか・
// ごく稀な遠くの音がいつ鳴るか。時刻は遊びの時計の秒だけで決まる（同じ秒なら毎回同じ音。動画とテストが同じ音になる）。
// engine に 3D の音が無いので、距離は音量で、壁は高い音の残り具合で表す（左右の振りは無い）。
mod Soundscape {
    use fge::{Hash01, Vec3}

    /// 響きと環境音の場所。
    pub enum Space with Eq, ToString {
        case Outdoor
        case Corridor
        case Stairs
        case Room
    }

    /// 場所の名前（音の名前の尻 <名前>_<場所>。tools/sfx_build.py の SPACES と同じ字）。
    pub def spaceName(s: Space): String = match s {
        case Space.Outdoor  => "outdoor"
        case Space.Corridor => "corridor"
        case Space.Stairs   => "stairs"
        case Space.Room     => "room"
    }

    /// 場所ごとの重み（足して 1。境目ではなめらかに移る）。
    pub type alias Weights = { outdoor = Float64, corridor = Float64, stairs = Float64, room = Float64 }

    /// 点が箱の中にどれだけ深く入っているか（m。外なら負）。
    def boxDepth(lo: Vec3.Vec3, hi: Vec3.Vec3, p: Vec3.Vec3): Float64 =
        List.foldLeft(Float64.min, 1.0e9, p#x - lo#x :: hi#x - p#x :: p#y - lo#y :: hi#y - p#y :: p#z - lo#z :: hi#z - p#z :: Nil)

    def areaDepth(a: SoundDoc.Area, p: Vec3.Vec3): Float64 =
        boxDepth(Vec3.v3(a#minX, a#minY, a#minZ), Vec3.v3(a#maxX, a#maxY, a#maxZ), p)

    /// 名前 name の範囲のうち、いちばん深く入っている深さ（その名前の範囲が無ければ大きな負）。
    def zoneDepth(zones: List[SoundDoc.Zone], name: String, p: Vec3.Vec3): Float64 =
        zones |> List.filter(z -> z#name == name) |> List.map(z -> areaDepth(z#area, p)) |> List.foldLeft(Float64.max, -1.0e9)

    /// 足元の面（上から順に当てる。どれにも入らなければ concrete）。
    pub def surfaceAt(doc: SoundDoc.Rec, feet: Vec3.Vec3): String =
        doc#surfaces |> List.find(z -> areaDepth(z#area, feet) >= 0.0) |> Option.map(z -> z#name) |> Option.getWithDefault("concrete")

    /// 耳のいる部屋と、その囲みにどれだけ深く入っているか（どの部屋の中でもなければ None）。
    pub def roomDepth(rooms: List[Rooms.Room], ear: Vec3.Vec3): Option[(String, Float64)] =
        rooms |> List.map(r -> (r#id, boxDepth(r#min, r#max, ear))) |> List.filter(e -> snd(e) >= 0.0)
              |> List.foldLeft((best, e) -> match best {
                     case Some(b) if snd(b) >= snd(e) => best
                     case _ => Some(e)
                 }, None)

    /// 耳のいる場所（部屋の中が先・次に外階段・外廊下・それ以外は屋外）。
    pub def spaceAt(doc: SoundDoc.Rec, rooms: List[Rooms.Room], ear: Vec3.Vec3): Space =
        if (Option.nonEmpty(roomDepth(rooms, ear))) Space.Room
        else if (zoneDepth(doc#spaces, "stairs", ear) >= 0.0) Space.Stairs
        else if (zoneDepth(doc#spaces, "corridor", ear) >= 0.0) Space.Corridor
        else Space.Outdoor

    def smooth(x: Float64): Float64 = { let q = Float64.max(0.0, Float64.min(1.0, x)); q * q * (3.0 - 2.0 * q) }

    /// 境目で 0.5・内へ fade / 2 入ると 1・外へ fade / 2 出ると 0。
    def soft(fade: Float64, depth: Float64): Float64 = smooth((depth + fade / 2.0) / fade)

    /// 場所ごとの重み（部屋 → 外階段 → 外廊下の順に取り、残りが屋外）。
    pub def weightsAt(doc: SoundDoc.Rec, rooms: List[Rooms.Room], ear: Vec3.Vec3): Weights =
        let fade = doc#beds#fade;
        let room = rooms |> List.map(r -> soft(fade, boxDepth(r#min, r#max, ear))) |> List.foldLeft(Float64.max, 0.0);
        let stairs = (1.0 - room) * soft(fade, zoneDepth(doc#spaces, "stairs", ear));
        let corridor = (1.0 - room - stairs) * soft(fade, zoneDepth(doc#spaces, "corridor", ear));
        { outdoor = Float64.max(0.0, 1.0 - room - stairs - corridor), corridor = corridor, stairs = stairs, room = room }

    /// 距離 d で、range で消える大きさ（近いほど大きく、2 乗で落ちる）。
    pub def falloff(d: Float64, range: Float64): Float64 =
        let k = Float64.max(0.0, 1.0 - d / Float64.max(0.1, range));
        k * k

    def distance(ear: Vec3.Vec3, s: SoundDoc.Spot): Float64 = Vec3.length(Vec3.sub(Vec3.v3(s#x, s#y, s#z), ear))

    def floorInt(x: Float64): Int32 = Float64.tryToInt32(Float64.floor(x)) |> Option.getWithDefault(0)

    // ── 置いてある物 ──

    /// 動いている間の、動き出してからの秒と止まるまでの秒。
    pub type alias Run = { elapsed = Float64, remaining = Float64 }

    /// i 番目の物が時刻 t に動いていれば、その動きの秒。物ごとに周期の位相をずらし、周期ごとに動き出す所も変える
    /// （全部が同時に回らない）。duty が 1 ならいつも動いている。
    pub def runOf(m: SoundDoc.Machine, i: Int32, t: Float64): Option[Run] =
        if (m#duty >= 1.0) Some({ elapsed = 1.0e6, remaining = 1.0e6 })
        else {
            let u = t + Hash01.at(i, m#seed) * m#period;
            let cycle = floorInt(u / m#period);
            let local = u - Int32.toFloat64(cycle) * m#period;
            let length = m#duty * m#period;
            let offset = Hash01.at(cycle * 97 + i, m#seed + 1) * (m#period - length);
            if (local >= offset and local < offset + length) Some({ elapsed = local - offset, remaining = offset + length - local })
            else None
        }

    /// 動き出しと止まり際の大きさ（1.5 秒で立ち上がり、2 秒で消える）。
    def envelope(r: Run): Float64 = smooth(r#elapsed / 1.5) * smooth(r#remaining / 2.0)

    /// 鳴り続ける音 1 本の名前と大きさ。
    pub type alias Voice = { name = String, volume = Float64 }

    /// 物の群れの鳴り続ける音: 動いていて聞こえる物を近い順に slots 台まで（<loop>_1..n。1 台なら <loop>）。
    pub def machineVoices(m: SoundDoc.Machine, ear: Vec3.Vec3, t: Float64): List[Voice] =
        m#spots |> List.zipWithIndex
            |> List.filterMap(e -> { let (i, s) = e; runOf(m, i, t) |> Option.map(r -> envelope(r) * falloff(distance(ear, s), m#range)) })
            |> List.filter(g -> g > 0.0)
            |> List.sortBy(g -> 0.0 - g) |> List.take(m#slots) |> List.zipWithIndex
            |> List.map(e -> { let (k, g) = e; { name = if (m#slots == 1) m#loop else "${m#loop}_${Int32.toString(k + 1)}", volume = m#volume * g } })

    /// 前の秒 t0 から今の秒 t1 の間に、聞こえる所で動き出した物があるか（動き出しの一発の音を鳴らす）。
    pub def machineStarted(m: SoundDoc.Machine, ear: Vec3.Vec3, t0: Float64, t1: Float64): Bool =
        t1 > t0 and m#duty < 1.0 and not String.isEmpty(m#start)
            and (m#spots |> List.zipWithIndex |> List.exists(e -> {
                     let (i, s) = e;
                     falloff(distance(ear, s), m#range) > 0.0 and (runOf(m, i, t1) |> Option.exists(r -> r#elapsed < t1 - t0))
                 }))

    /// 動き出しの一発の音の大きさ: 4 秒以内に動き出した物のうち、いちばん近い物の距離で決める。
    pub def startGain(m: SoundDoc.Machine, ear: Vec3.Vec3, t: Float64): Float64 =
        m#spots |> List.zipWithIndex
            |> List.filterMap(e -> {
                   let (i, s) = e;
                   runOf(m, i, t) |> Option.filter(r -> r#elapsed < 4.0) |> Option.map(_ -> falloff(distance(ear, s), m#range))
               })
            |> List.foldLeft(Float64.max, 0.0)

    // ── 遠くの音 ──

    /// 周期 slot の遠くの音が鳴り始める秒（その周期は鳴らないなら None）。周期の中で鳴り終わるように置く。
    def farStartOf(f: SoundDoc.Far, slot: Int32): Option[Float64] =
        if (Hash01.at(slot, f#seed) >= f#chance) None
        else Some(Int32.toFloat64(slot) * f#every + Hash01.at(slot, f#seed + 1) * Float64.max(0.0, f#every - f#seconds))

    /// 前の秒 t0 から今の秒 t1 の間に鳴り始めたか。
    pub def farStarted(f: SoundDoc.Far, t0: Float64, t1: Float64): Bool =
        t1 > t0 and (farStartOf(f, floorInt(t1 / f#every)) |> Option.exists(s -> s > t0 and s <= t1))

    // ── 一発の音の選び方 ──

    /// n 本の差分のうち k 回目に鳴らす番号（1..n）。偶数回は前半・奇数回は後半から選ぶので、続けて同じ音にならない
    /// （同じ音の連打は機械の音に聞こえる）。
    pub def variant(n: Int32, seed: Int32, k: Int32): Int32 =
        if (n < 2) 1
        else {
            let half = n / 2;
            let odd = Int32.modulo(k, 2) == 1;
            let within = Hash01.indexOf({ index = k, channel = seed }, if (odd) n - half else half);
            1 + (if (odd) half else 0) + within
        }
}
