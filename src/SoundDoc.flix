// SoundDoc — night.sound.json（足音の面・響きの場所・環境音と置いてある物の音の大きさと置き場所）の宣言ドキュメント層。
// 音の中身は tools/sfx_build.py が録音素材から作る。いつ・どの音を鳴らすかの規則は Sounds と Soundscape。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod SoundDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 鳴る物の置き場所（m）。
    pub type alias Spot = { x = Float64, y = Float64, z = Float64 }

    /// 範囲（x・y・z の箱。y は足元の高さ）。
    pub type alias Area = { minX = Float64, maxX = Float64, minY = Float64, maxY = Float64, minZ = Float64, maxZ = Float64 }

    /// 名前の付いた範囲（足音の面・響きの場所）。
    pub type alias Zone = { name = String, area = Area }

    /// 場所の環境音: 屋外・外廊下・外階段の大きさ・屋外の音が他の場所でどれだけ聞こえるか・
    /// 部屋の中で屋外の音の高い音の残り具合（0..1）・場所の境目でなめらかにつなぐ幅（m）・蛍光灯のうなりが聞こえる距離（m）。
    pub type alias Beds = { outdoor = Float64, corridor = Float64, stairs = Float64,
                            outdoorInCorridor = Float64, outdoorInStairs = Float64, outdoorInRoom = Float64,
                            roomHF = Float64, fade = Float64, lampRange = Float64 }

    /// 部屋の中だけで鳴る音（冷蔵庫・時計・換気扇）。
    pub type alias RoomLoop = { room = String, loop = String, volume = Float64 }

    /// 一発の音の大きさ: 足音・扉・手の灯りのスイッチ・蛍光灯のジジッと、それが聞こえる距離（m）。
    pub type alias Shots = { steps = Float64, doors = Float64, flash = Float64, zap = Float64, zapRange = Float64 }

    /// 置いてある物の音の群れ: 名前・ループの名前（slots が 2 以上なら <loop>_1..n）・同時に鳴らす近い台数・すぐそばでの大きさ・
    /// 聞こえる距離（m）・何秒ごとに（period）どれだけの割合で動くか（duty。1 = いつも）・種・動き出す時の一発の音（空なら無し）とその大きさ・置き場所。
    pub type alias Machine = { name = String, loop = String, slots = Int32, volume = Float64, range = Float64,
                               period = Float64, duty = Float64, seed = Int32, start = String, startVolume = Float64, spots = List[Spot] }

    /// ごく稀な遠くの音: every 秒ごとに chance の確からしさで 1 回鳴る・大きさ・音の長さ（秒）・種。
    pub type alias Far = { name = String, every = Float64, chance = Float64, volume = Float64, seconds = Float64, seed = Int32 }

    pub type alias Rec = {
        version = Int32,
        surfaces = List[Zone],
        spaces = List[Zone],
        beds = Beds,
        roomLoops = List[RoomLoop],
        shots = Shots,
        machines = List[Machine],
        far = List[Far]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/night.sound.json"

    def area(x: (Float64, Float64), y: (Float64, Float64), z: (Float64, Float64)): Area =
        { minX = fst(x), maxX = snd(x), minY = fst(y), maxY = snd(y), minZ = fst(z), maxZ = snd(z) }

    /// コード側の既定値（assets/night.sound.json の面と場所・大きさ。置いてある物は自販機だけ）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 2,
                  surfaces = { name = "metal", area = area((-19.6, -17.15), (0.4, 12.5), (-2.7, 1.25)) }
                      :: { name = "tatami", area = area((-10.11, -6.89), (2.9, 5.6), (-6.75, -3.7)) }
                      :: { name = "wood", area = area((-16.91, -3.49), (2.9, 5.6), (-6.75, -1.2)) }
                      :: { name = "dirt", area = area((-40.0, 4.0), (-1.0, 0.2), (-9.0, 5.9)) } :: Nil,
                  spaces = { name = "stairs", area = area((-19.7, -17.1), (0.2, 12.5), (-2.8, 1.3)) }
                      :: { name = "corridor", area = area((-17.0, 0.0), (0.25, 12.0), (-0.1, 1.25)) } :: Nil,
                  beds = { outdoor = 0.16, corridor = 0.10, stairs = 0.12, outdoorInCorridor = 0.55, outdoorInStairs = 0.8,
                           outdoorInRoom = 0.15, roomHF = 0.2, fade = 1.5, lampRange = 6.0 },
                  roomLoops = Nil,
                  shots = { steps = 0.42, doors = 0.65, flash = 0.30, zap = 0.35, zapRange = 7.0 },
                  machines = { name = "vending", loop = "m_vending", slots = 1, volume = 0.28, range = 9.0, period = 60.0, duty = 1.0,
                               seed = 0, start = "", startVolume = 0.0,
                               spots = { x = -2.05, y = 1.0, z = 5.7 } :: { x = -3.12, y = 1.0, z = 5.7 } :: Nil } :: Nil,
                  far = Nil })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// 欄 key の物の列（無い・形が違えば None）。
    def rowsOf(key: String, obj: Map[String, Json]): Option[List[Map[String, Json]]] =
        Map.get(key, obj) |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))

    def objectOf(key: String, obj: Map[String, Json]): Map[String, Json] =
        Map.get(key, obj) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def spotOf(obj: Map[String, Json]): Option[Spot] =
        let num = key -> Map.get(key, obj) |> Option.flatMap(JsonCodec.expectFloat);
        forM (x <- num("x"); y <- num("y"); z <- num("z")) yield { x = x, y = y, z = z }

    def areaOf(obj: Map[String, Json]): Option[Area] =
        let num = key -> Map.get(key, obj) |> Option.flatMap(JsonCodec.expectFloat);
        forM (x0 <- num("minX"); x1 <- num("maxX"); y0 <- num("minY"); y1 <- num("maxY"); z0 <- num("minZ"); z1 <- num("maxZ"))
            yield area((x0, x1), (y0, y1), (z0, z1))

    /// 名前と範囲を 1 段の欄に並べた行（{ name, minX, maxX, … }。Doc の入れ子を 2 段までにするため area で包まない）。
    def zoneOf(obj: Map[String, Json]): Option[Zone] =
        let name = JsonCodec.stringOr("name", "", obj);
        if (String.isEmpty(name)) None
        else areaOf(obj) |> Option.map(a -> { name = name, area = a })

    def roomLoopOf(obj: Map[String, Json]): Option[RoomLoop] =
        let room = JsonCodec.stringOr("room", "", obj);
        let loop = JsonCodec.stringOr("loop", "", obj);
        if (String.isEmpty(room) or String.isEmpty(loop)) None
        else Some({ room = room, loop = loop, volume = JsonCodec.floatOr("volume", 0.0, obj) })

    /// 置き場所の行（machine = 群れの名前）。
    def placedSpotOf(obj: Map[String, Json]): Option[(String, Spot)] =
        let machine = JsonCodec.stringOr("machine", "", obj);
        if (String.isEmpty(machine)) None else spotOf(obj) |> Option.map(s -> (machine, s))

    /// 群れの行（置き場所は spots の列から、群れの名前で集める — Doc の入れ子を 2 段までにするため群れの中に持たない）。
    def machineOf(spots: List[(String, Spot)], obj: Map[String, Json]): Option[Machine] =
        let name = JsonCodec.stringOr("name", "", obj);
        let loop = JsonCodec.stringOr("loop", "", obj);
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, obj);
        if (String.isEmpty(name) or String.isEmpty(loop)) None
        else Some({ name = name, loop = loop, slots = Int32.max(1, JsonCodec.intOr("slots", 1, obj)),
                    volume = f("volume", 0.0), range = Float64.max(0.1, f("range", 5.0)),
                    period = Float64.max(1.0, f("period", 60.0)), duty = Float64.max(0.0, Float64.min(1.0, f("duty", 1.0))),
                    seed = JsonCodec.intOr("seed", 0, obj), start = JsonCodec.stringOr("start", "", obj),
                    startVolume = f("startVolume", 0.0),
                    spots = spots |> List.filter(e -> fst(e) == name) |> List.map(snd) })

    def farOf(obj: Map[String, Json]): Option[Far] =
        let name = JsonCodec.stringOr("name", "", obj);
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, obj);
        if (String.isEmpty(name)) None
        else Some({ name = name, every = Float64.max(1.0, f("every", 300.0)), chance = f("chance", 0.0), volume = f("volume", 0.0),
                    seconds = f("seconds", 10.0), seed = JsonCodec.intOr("seed", 0, obj) })

    def bedsOf(d: Beds, obj: Map[String, Json]): Beds =
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, obj);
        { outdoor = f("outdoor", d#outdoor), corridor = f("corridor", d#corridor), stairs = f("stairs", d#stairs),
          outdoorInCorridor = f("outdoorInCorridor", d#outdoorInCorridor), outdoorInStairs = f("outdoorInStairs", d#outdoorInStairs),
          outdoorInRoom = f("outdoorInRoom", d#outdoorInRoom), roomHF = f("roomHF", d#roomHF),
          fade = Float64.max(0.01, f("fade", d#fade)), lampRange = f("lampRange", d#lampRange) }

    def shotsOf(d: Shots, obj: Map[String, Json]): Shots =
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, obj);
        { steps = f("steps", d#steps), doors = f("doors", d#doors), flash = f("flash", d#flash), zap = f("zap", d#zap),
          zapRange = f("zapRange", d#zapRange) }

    /// 欄 key の列を row で読む（欄が無い・形が違えば既定の列）。
    def listOr(key: String, row: Map[String, Json] -> Option[a], fallback: List[a], root: Map[String, Json]): List[a] =
        rowsOf(key, root) |> Option.map(List.filterMap(row)) |> Option.getWithDefault(fallback)

    /// 群れの列（群れが無ければ既定。置き場所の列が無ければ既定の群れの置き場所のまま）。
    def machinesOf(d: Rec, root: Map[String, Json]): List[Machine] =
        match rowsOf("spots", root) {
            case None => listOr("machines", machineOf(d#machines |> List.flatMap(m -> m#spots |> List.map(s -> (m#name, s)))), d#machines, root)
            case Some(rows) => listOr("machines", machineOf(rows |> List.filterMap(placedSpotOf)), d#machines, root)
        }

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  surfaces = listOr("surfaces", zoneOf, d#surfaces, root),
                  spaces = listOr("spaces", zoneOf, d#spaces, root),
                  beds = bedsOf(d#beds, objectOf("beds", root)),
                  roomLoops = listOr("roomLoops", roomLoopOf, d#roomLoops, root),
                  shots = shotsOf(d#shots, objectOf("shots", root)),
                  machines = machinesOf(d, root),
                  far = listOr("far", farOf, d#far, root) })
}
