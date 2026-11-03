// Inspect — E で調べる物を引く（純粋）: 目の向きのレイが最初に当たる物（当たり判定のノードか扉の板）を選び、
// ノードなら InspectDoc の名前の頭で文言を引く。壁・床のように文言の無いノードに当たった時は何も引かない。
mod Inspect {
    use fge::{Clock, CollisionShape3d, Model3d, Ray3d}

    /// レイの的の鍵。Node = collision.glb の当たり判定のノードの名前・Door = 部屋の番号の扉の板。
    pub enum Key with Eq, ToString {
        case Node(String)
        case Door(String)
    }

    /// E で引いた物。Door = 開け閉めする扉の部屋の番号・Thing = 出す文言・Nothing = 調べる物に当たらない。
    pub enum Pick with Eq, ToString {
        case Door(String)
        case Thing(String)
        case Nothing
    }

    /// 調べて出している文言と、調べた時刻（遊びの時計）。
    pub type alias Seen = { text = String, at = Clock.Time[PlayClock.Play] }

    /// 動かない物の的（ノードの名前が鍵）。読み込みで 1 回作る。
    /// WhyNot: 住人を的に入れない — 調べる物は Doc の名前の頭で決まる置物だけで、住人の前で押すと奥の物を調べるのは人の決めた手触り。
    /// 厚さ 0 の板（道路の面）はレイに当たらない・斜めの手すりは分ける前の箱（踊り場の上へはみ出す）でレイを止めるが、どちらも文言の無い物で、今の配置では奥に調べる物が無い。
    pub def nodeTargets(nodes: List[Model3d.ModelNode]): List[(Key, Ray3d.RayTarget)] =
        Ray3d.boxTargetsOf(n -> Key.Node(n#name), nodes)

    /// Doc のうち、model のどのノードの名前にも合わない頭。
    pub def unmatchedPrefixes(doc: InspectDoc.Rec, model: Model3d.Model3d): List[String] =
        InspectDoc.unmatchedPrefixes(doc, model#nodes |> List.map(n -> n#name))

    /// 今の角の扉の板の的（部屋の番号が鍵）。
    pub def doorTargets(rooms: List[Rooms.Room], states: Map[String, Doors.State]): List[(Key, Ray3d.RayTarget)] =
        List.zip(rooms, Doors.leafBoxes(rooms, states))
            |> List.map(e -> (Key.Door(fst(e)#id), Ray3d.RayTarget.Shape(CollisionShape3d.BoxShape3d(snd(e)))))

    /// レイ ray が reach の中で最初に当たる物（扉の板と動かない物の的 targets から）。
    pub def pick(doc: InspectDoc.Rec, targets: List[(Key, Ray3d.RayTarget)], ray: Ray3d.Ray3d): Pick =
        match Ray3d.pickNearest(ray, doc#reach, targets) |> Option.map(fst) {
            case Some(Key.Door(id))   => Pick.Door(id)
            case Some(Key.Node(name)) => InspectDoc.textOf(doc, name) |> Option.map(Pick.Thing) |> Option.getWithDefault(Pick.Nothing)
            case None                 => Pick.Nothing
        }

    /// 時刻 now に出す文言と、出してからの秒（出しておく秒を過ぎたら None）。
    pub def showing(doc: InspectDoc.Rec, now: Clock.Time[PlayClock.Play], seen: Option[Seen]): Option[(String, Float64)] =
        seen |> Option.map(s -> (s#text, Clock.since(s#at, now))) |> Option.filter(e -> snd(e) >= 0.0 and snd(e) < doc#showSeconds)
}
