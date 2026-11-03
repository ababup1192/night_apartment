// Doors — 玄関の扉の状態と、1 コマ進める規則（純粋）。
//
// 角は書き出しと同じ glTF の向きの度（0 = 閉・負 = 外廊下（+Z）へ開く）。engine の座標は x を反転しているので、
// 回す時は engine の Y 軸まわりに符号を逆にした角で回す（Mat4.rotateY は +Z を +X へ回す向き）。
// 扉の板の当たり判定の箱は、閉じた時の箱を蝶番のまわりに同じ角で回した向きのある箱（Collider.Box のまま使える）。
// 回っている扉が体に当たる所では、そのコマは回さない（体を押し込まない・押しのけない）。体がどけば続きから回る。
mod Doors {
    use fge::{Mat4, Vec2, Vec3}

    /// 扉の動き。Still = 止まっている・Opening = 開いている途中・Closing = 閉じている途中。
    pub enum Motion with Eq, ToString {
        case Still
        case Opening
        case Closing
    }

    /// 扉 1 枚の状態: 今の角（度）と動き。
    pub type alias State = { angle = Float64, motion = Motion }

    /// 閉じているとみなす角の幅（度）。
    def closedEps(): Float64 = 0.5

    /// 書き出しの初めの角で止まっている扉（204 は少し開いている）。
    pub def initial(door: Rooms.Door): State = { angle = door#initialDeg, motion = Motion.Still }

    /// 部屋ごとの初めの扉の状態。
    pub def initialAll(rooms: List[Rooms.Room]): Map[String, State] =
        rooms |> List.map(r -> (r#id, initial(r#door))) |> List.toMap

    /// 閉じているか（止まっていて角がほぼ 0）。
    pub def isClosed(s: State): Bool = s#motion == Motion.Still and Float64.abs(s#angle) < closedEps()

    /// E を押した: 動いている途中なら向きを逆に、止まっていれば開け切る角 stop の半分より閉じた側なら開け、開いた側なら閉める
    /// （少し開いたまま止まっている扉は、押すと開く）。
    pub def toggle(stop: Float64, s: State): State = match s#motion {
        case Motion.Opening => { motion = Motion.Closing | s }
        case Motion.Closing => { motion = Motion.Opening | s }
        case Motion.Still   => { motion = if (Float64.abs(s#angle) < Float64.abs(stop) / 2.0) Motion.Opening else Motion.Closing | s }
    }

    /// 開け切る角（Doc の角と書き出しの止まる角の、閉じた側の方）。
    pub def openTo(doc: RoomsDoc.Door, door: Rooms.Door): Float64 = Float64.max(door#openLimitDeg, Float64.min(0.0, doc#openDeg))

    /// 1 コマ進める。体（足元 feet）に扉の板が食い込む向きへは回さない（前より深くなるなら、そのコマは止める）。
    def step(doc: RoomsDoc.Door, door: Rooms.Door, body: Collider.Body, feet: Vec3.Vec3, dt: Float64, s: State): State =
        let turn = doc#speedDeg * dt;
        match s#motion {
            case Motion.Still   => s
            case Motion.Opening =>
                let stop = openTo(doc, door);
                let next = Float64.max(stop, s#angle - turn);
                moveTo(door, body, feet, next, next <= stop, s)
            case Motion.Closing =>
                let next = Float64.min(0.0, s#angle + turn);
                moveTo(door, body, feet, next, next >= 0.0, s)
        }

    /// step を n コマくり返した状態。
    pub def stepTimes(doc: RoomsDoc.Door, door: Rooms.Door, body: Collider.Body, feet: Vec3.Vec3, dt: Float64, n: Int32, s: State): State =
        List.range(0, n) |> List.foldLeft((acc, _) -> step(doc, door, body, feet, dt, acc), s)

    def moveTo(door: Rooms.Door, body: Collider.Body, feet: Vec3.Vec3, next: Float64, reached: Bool, s: State): State =
        let before = Collider.deepestOverlap(leafBox(door, s#angle) :: Nil, body, feet#x, feet#y, feet#z);
        let after = Collider.deepestOverlap(leafBox(door, next) :: Nil, body, feet#x, feet#y, feet#z);
        if (after > Float64.max(0.002, before)) s
        else { angle = next, motion = if (reached) Motion.Still else s#motion }

    /// glTF の向きの角（度）を、engine の Y 軸まわりの角（ラジアン）へ。
    def engineAngle(deg: Float64): Float64 = 0.0 - deg * Walker.pi() / 180.0

    /// 水平の向きを engine の Y 軸まわりに a（ラジアン）回す（Mat4.rotateY と同じ向き）。
    def turnY(a: Float64, v: Vec3.Vec3): Vec3.Vec3 =
        let (s, c) = (Vec2.sin(a), Vec2.cos(a));
        Vec3.v3(c * v#x + s * v#z, v#y, c * v#z - s * v#x)

    /// 角 angle（度）の扉の板の当たり判定の箱。
    pub def leafBox(door: Rooms.Door, angle: Float64): Collider.Box =
        let a = engineAngle(angle);
        let b = door#leaf;
        let h = door#hinge;
        let c = Vec3.add(h, turnY(a, Vec3.sub(b#center, h)));
        { center = c, ax = turnY(a, b#ax), ay = turnY(a, b#ay), az = turnY(a, b#az), half = b#half }

    /// 扉の形を角 angle（度）まで回す行列（閉じた扉の形は書き出しの置き場所のまま入っている）。
    pub def transformOf(door: Rooms.Door, angle: Float64): Mat4.Mat4 =
        let h = door#hinge;
        Mat4.mul(Mat4.translate(h), Mat4.mul(Mat4.rotateY(engineAngle(angle)), Mat4.translate(Vec3.v3(0.0 - h#x, 0.0 - h#y, 0.0 - h#z))))

    /// 今の角の全部の扉の板の箱。
    pub def leafBoxes(rooms: List[Rooms.Room], states: Map[String, State]): List[Collider.Box] =
        rooms |> List.map(r -> leafBox(r#door, angleOf(states, r)))

    /// 部屋の扉の今の角（状態が無ければ初めの角）。
    pub def angleOf(states: Map[String, State], room: Rooms.Room): Float64 =
        Map.get(room#id, states) |> Option.map(s -> s#angle) |> Option.getWithDefault(room#door#initialDeg)

    /// E で動かす扉の部屋: 足元と同じ階で、足元から扉の板の真ん中まで reach の中、向いている向きから facingDeg の中にある扉のうち一番近い物。
    pub def target(doc: RoomsDoc.Door, rooms: List[Rooms.Room], states: Map[String, State], w: Walker.Walker): Option[String] =
        let cosLimit = Vec2.cos(doc#facingDeg * Walker.pi() / 180.0);
        rooms
            |> List.filterMap(r -> {
                let c = leafBox(r#door, angleOf(states, r))#center;
                let (dx, dz) = (c#x - w#x, c#z - w#z);
                let dist = Vec2.sqrt(dx * dx + dz * dz);
                let facing = dist < 0.001 or (dx * Vec2.sin(w#yaw) + dz * Vec2.cos(w#yaw)) / dist >= cosLimit;
                if (dist <= doc#reach and facing and Float64.abs(w#feet - r#door#hinge#y) < 1.0) Some((dist, r#id)) else None
            })
            |> List.minimumBy((a, b) -> Order.compare(fst(a), fst(b)))
            |> Option.map(snd)

    /// 全部の扉を 1 コマ進める（体は足元 feet）。
    pub def stepAll(doc: RoomsDoc.Door, rooms: List[Rooms.Room], body: Collider.Body, feet: Vec3.Vec3, dt: Float64, states: Map[String, State]): Map[String, State] =
        rooms |> List.foldLeft((acc, r) -> match Map.get(r#id, acc) {
            case Some(s) => Map.insert(r#id, step(doc, r#door, body, feet, dt, s), acc)
            case None    => acc
        }, states)

    /// 部屋の扉を E で動かす（その部屋の状態が無ければそのまま）。
    pub def toggleAt(doc: RoomsDoc.Door, rooms: List[Rooms.Room], id: String, states: Map[String, State]): Map[String, State] =
        match List.find(r -> r#id == id, rooms) {
            case Some(r) => Map.adjust(toggle(openTo(doc, r#door)), id, states)
            case None    => states
        }
}
