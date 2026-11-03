// Rooms — 2 階の部屋（manifest.json の rooms）: 部屋の囲み・玄関の扉・部屋の灯り・自動操縦の通り道と、部屋を描くかの規則（純粋）。
//
// 書き出しの座標は glTF（右手系）なので、engine の座標（左手系。x を反転）へ写して持つ。
// 扉の板の当たり判定の箱は collision.glb のノード（manifest の door.collision_box）を名前で引く。引いた箱は常に効く箱の列から外し、
// 扉の角に合わせて回して使う（Doors.leafBox）。扉の形は doors の部品のノード（door.node）を名前で引く（Stage.groupsOf）。
mod Rooms {
    use fge::{CollisionShape3d, DocJson, JsonCodec, Log, Model3d, Num, Vec3}
    use Util.Json.Json

    /// 部屋の灯り 1 つ（engine の座標）。color = 線形の色・watts = Blender の W・range = 届く距離（m）・flicker = ちらつかせる（テレビ）。
    pub type alias Light = { name = String, position = Vec3.Vec3, color = (Float64, Float64, Float64), watts = Float64, range = Float64, flicker = Bool }

    /// 玄関の扉: 蝶番の軸の足元（engine）・回し切れる角（度。glTF の向きで負が外廊下）・初めの角・閉じた扉の板の箱・
    /// 扉の形のノードの名前（manifest の door.node）。
    pub type alias Door = { hinge = Vec3.Vec3, openLimitDeg = Float64, initialDeg = Float64, leaf = CollisionShape3d.Box3d, node = String }

    /// 部屋 1 つ。part = 部屋の部品の名前（manifest の parts の鍵）・doorPart = 扉の部品の名前・
    /// min / max = バルコニー込みの部屋の囲み（engine）・path = 外廊下の扉の前 → 玄関 → DK → 窓の前（床の点）。
    pub type alias Room = { id = String, part = String, doorPart = String, min = Vec3.Vec3, max = Vec3.Vec3,
                            door = Door, lights = List[Light], path = List[Vec3.Vec3] }

    /// glTF の点を engine の点へ。
    def fromGltf(x: Float64, y: Float64, z: Float64): Vec3.Vec3 = Vec3.v3(0.0 - x, y, z)

    // ── manifest.json の rooms ──

    /// 扉の板の箱を探す前の部屋（扉の箱だけがまだ無い）。
    /// doorNode = 扉の形のノードの名前・doorBox = 扉の板の当たり判定のノードの名前（manifest の door.node・door.collision_box）。
    type alias Entry = { id = String, part = String, doorPart = String, doorNode = String, doorBox = String, min = Vec3.Vec3, max = Vec3.Vec3,
                         hinge = Vec3.Vec3, openLimitDeg = Float64, initialDeg = Float64, lights = List[Light], path = List[Vec3.Vec3] }

    /// manifest.json の字と collision.glb から、部屋の並び（番号の順）と、扉の板を外した当たり判定のノード（常に効く物）。
    /// rooms の無い manifest は部屋 0（2 階の部屋の無い書き出しでも歩ける）。扉の板のノードが無い部屋は 1 行知らせて置かない。
    pub def layoutOf(text: String, collision: Model3d.Model3d): (List[Room], List[Model3d.ModelNode]) =
        let entries = entriesOf(text);
        let rooms = entries |> List.filterMap(e -> match Model3d.findNode(e#doorBox, collision) |> Option.flatMap(CollisionShape3d.boxOfNode) {
            case Some(leaf) => Some(roomOf(e, leaf))
            case None       => Log.warnThen("[rooms] ${e#id}: 扉の板の当たり判定のノード（${e#doorBox}）が collision.glb に無いか、形を持たない", None)
        });
        let leaves = entries |> List.map(e -> e#doorBox) |> List.toSet;
        (rooms, Model3d.nodesWithPrefix(Collider.prefix(), collision) |> List.filter(n -> not Set.memberOf(n#name, leaves)))

    def roomOf(e: Entry, leaf: CollisionShape3d.Box3d): Room =
        { id = e#id, part = e#part, doorPart = e#doorPart, min = e#min, max = e#max,
          door = { hinge = e#hinge, openLimitDeg = e#openLimitDeg, initialDeg = e#initialDeg, leaf = leaf, node = e#doorNode },
          lights = e#lights, path = e#path }

    /// manifest.json の rooms を読む（読めない部屋は捨てる）。
    def entriesOf(text: String): List[Entry] =
        DocJson.parse(text)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(root -> Map.get("rooms", root))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(rooms -> Map.toList(rooms) |> List.filterMap(e -> {
                let (id, json) = e;
                JsonCodec.expectObject(json) |> Option.flatMap(entryOf(id))
            }))
            |> Option.getWithDefault(Nil)

    /// [x, y, z]（glTF）を engine の点へ。
    pub def pointOf(json: Json): Option[Vec3.Vec3] =
        match JsonCodec.decodeList(JsonCodec.expectFloat, json) {
            case Some(x :: y :: z :: Nil) => Some(fromGltf(x, y, z))
            case _                        => None
        }

    def rgbOf(json: Json): Option[(Float64, Float64, Float64)] =
        match JsonCodec.decodeList(JsonCodec.expectFloat, json) {
            case Some(r :: g :: b :: Nil) => Some((r, g, b))
            case _                        => None
        }

    def entryOf(id: String, obj: Map[String, Json]): Option[Entry] =
        let at = (o: Map[String, Json], key: String) -> Map.get(key, o) |> Option.flatMap(pointOf);
        let str = (o: Map[String, Json], key: String) -> Map.get(key, o) |> Option.flatMap(JsonCodec.expectString);
        let door = Map.get("door", obj) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty());
        let bounds = Map.get("bounds", obj) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty());
        let lights = Map.get("lights", obj) |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))
            |> Option.map(rows -> rows |> List.filterMap(lightOf)) |> Option.getWithDefault(Nil);
        let path = Map.get("path", obj) |> Option.flatMap(json -> JsonCodec.decodeList(pointOf, json)) |> Option.getWithDefault(Nil);
        forM (
            part <- str(obj, "part");
            glb <- str(door, "glb");
            doorNode <- str(door, "node");
            doorBox <- str(door, "collision_box");
            hinge <- at(door, "hinge");
            lo <- at(bounds, "min");
            hi <- at(bounds, "max")
        ) yield
            // glTF の min / max は x を反転すると入れ替わる。
            { id = id, part = part, doorPart = String.stripSuffix(substr = ".glb", glb) |> Option.getWithDefault(glb),
              doorNode = doorNode, doorBox = doorBox,
              min = Vec3.v3(Float64.min(lo#x, hi#x), lo#y, lo#z), max = Vec3.v3(Float64.max(lo#x, hi#x), hi#y, hi#z),
              hinge = hinge, openLimitDeg = JsonCodec.floatOr("open_angle_deg", -90.0, door),
              initialDeg = JsonCodec.floatOr("initial_angle_deg", 0.0, door), lights = lights, path = path }

    /// 灯り 1 つ（manifest の lights の 1 行。pos と color の無い行は None）。
    pub def lightOf(obj: Map[String, Json]): Option[Light] =
        forM (
            position <- Map.get("pos", obj) |> Option.flatMap(pointOf);
            color <- Map.get("color", obj) |> Option.flatMap(rgbOf)
        ) yield { name = JsonCodec.stringOr("name", "", obj), position = position, color = color,
                  watts = JsonCodec.floatOr("blender_watts", 1.0, obj), range = JsonCodec.floatOr("range_m", 2.0, obj),
                  flicker = JsonCodec.boolOr("flicker", false, obj) }

    // ── 部屋を描くか ──

    /// 目が部屋の囲み（margin だけ広げた）の中か。
    def isInside(margin: Float64, room: Room, eye: Vec3.Vec3): Bool =
        eye#x >= room#min#x - margin and eye#x <= room#max#x + margin and eye#y >= room#min#y - margin and eye#y <= room#max#y + margin
            and eye#z >= room#min#z - margin and eye#z <= room#max#z + margin

    /// 点のある部屋の番号（どの部屋の囲みの中でもなければ None）。
    pub def roomAt(rooms: List[Room], at: Vec3.Vec3): Option[String] =
        rooms |> List.find(r -> isInside(0.0, r, at)) |> Option.map(r -> r#id)

    /// 部屋を描くか: 目が部屋の中にある・または扉が開いていて、扉の前の外廊下の側から扉が見える
    /// （扉の真ん中まで seeRange の中で、目の向きから seeConeDeg の中。nearRange より近ければ向きによらない）。
    /// angle = 扉の今の角（度）・yaw = 目の水平の向き（ラジアン）。
    pub def isDrawn(draw: RoomsDoc.Draw, room: Room, eye: Vec3.Vec3, yaw: Float64, angle: Float64): Bool =
        if (isInside(draw#insideMargin, room, eye)) true
        else if (Float64.abs(angle) < draw#ajarDeg) false
        else {
            let c = room#door#leaf#center;
            let (dx, dz) = (c#x - eye#x, c#z - eye#z);
            let dist = Num.sqrt(dx * dx + dz * dz);
            let level = Float64.abs(eye#y - c#y) < 2.0;
            let facing = dist < 0.001 or (dx * Num.sin(yaw) + dz * Num.cos(yaw)) / dist >= Num.cos(draw#seeConeDeg * Num.pi() / 180.0);
            level and eye#z > room#door#hinge#z and (dist < draw#nearRange or (dist < draw#seeRange and facing))
        }

    /// 部屋の部品の名前が mesh を持つ部屋の番号（部屋の部品でなければ None）。
    pub def roomOfPart(rooms: List[Room], part: String): Option[String] =
        rooms |> List.find(r -> r#part == part) |> Option.map(r -> r#id)

    /// 扉の部品の形のノード node が、どの部屋の扉か（ノードの名前が manifest の door.node の部屋。扉の部品でなければ None）。
    pub def doorOfNode(rooms: List[Room], part: String, node: Option[String]): Option[String] =
        rooms |> List.find(r -> r#doorPart == part and node == Some(r#door#node)) |> Option.map(r -> r#id)
}
