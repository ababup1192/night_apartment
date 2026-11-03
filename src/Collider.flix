// Collider — 当たり判定の箱（collision.glb の COL_ ノード）と、歩ける範囲の囲みを足した当たり判定の集まり（純粋）。
//
// 箱はノードの形の境界をノードの向きで写した向きのある箱（engine の CollisionShape3d.Box3d。階段の段板と斜めの手すりは傾いている）。
// 体を箱の中で動かす規則は engine の CharacterBody3d。
mod Collider {
    use fge::{CollisionShape3d, CollisionWorld3d, Model3d, Vec3}

    /// 当たり判定のノードの名前の頭。
    pub def prefix(): String = "COL_"

    /// collision.glb の当たり判定の箱全部（COL_ で始まるノード・ノードの並びの順）。
    pub def boxesOf(model: Model3d.Model3d): List[CollisionShape3d.Box3d] =
        boxesOfNodes(Model3d.nodesWithPrefix(prefix(), model))

    /// ノードの列の箱（mesh の無いノードは捨てる）。斜めの手すりは縦の短い箱の列に置き換える（railSegments）。
    pub def boxesOfNodes(nodes: List[Model3d.ModelNode]): List[CollisionShape3d.Box3d] =
        splitSlantedRails(CollisionShape3d.boxesOfNodes(nodes) |> List.map(withMinThickness))

    /// 板（道路の面など、厚さ 0 の形）の箱に 5 mm の厚さを持たせた箱（真ん中はそのまま）。
    /// WhyNot: 厚さ 0 のまま渡さない — engine の床のレイは厚さ 0 の箱の面に当たらず、道路の上で groundY の地面まで沈む。
    def withMinThickness(b: CollisionShape3d.Box3d): CollisionShape3d.Box3d =
        let t = (h: Float64) -> Float64.max(0.005, h);
        { half = Vec3.v3(t(b#half#x), t(b#half#y), t(b#half#z)) | b }

    /// 箱の列の、斜めの手すりを縦の短い箱の列に置き換えた物（ほかの箱はそのまま・並びは保つ）。
    pub def splitSlantedRails(boxes: List[CollisionShape3d.Box3d]): List[CollisionShape3d.Box3d] =
        boxes |> List.flatMap(b -> if (isSlantedRail(b)) railSegments(6, b) else b :: Nil)

    /// 斜めの手すり: 傾いた箱で、一番薄い向きがほぼ水平（段板は一番薄い向きがほぼ縦なので入らない）。
    def isSlantedRail(b: CollisionShape3d.Box3d): Bool =
        let (thin, _) = thinnest(b);
        isTilted(b) and Float64.abs(thin#y) < 0.3

    /// 箱の上を向く面が傾いているか（3 本の向きのどれも、ほぼ真上を向いていない）。
    /// WhyNot: engine の CharacterBody3d の同じ式を使わない — 非公開で、ここは手すりの見分けと表示の色分けにだけ使う（足の着き方の Slope は engine の Floor#sloped）。
    pub def isTilted(b: CollisionShape3d.Box3d): Bool =
        Float64.abs(b#ax#y) < 0.98 and Float64.abs(b#ay#y) < 0.98 and Float64.abs(b#az#y) < 0.98

    /// 一番薄い向きと、その半分の厚さ。
    def thinnest(b: CollisionShape3d.Box3d): (Vec3.Vec3, Float64) =
        if (b#half#x <= b#half#y and b#half#x <= b#half#z) (b#ax, b#half#x)
        else if (b#half#y <= b#half#z) (b#ay, b#half#y)
        else (b#az, b#half#z)

    /// 斜めの手すりの箱を、段鼻の線に沿った n 本の縦の箱に分ける。
    /// 書き出しの箱は高さの向きが坂に直角で、上の端が踊り場の上へ斜めにはみ出す（1.1 m の高さで 0.75 m ほど）。
    /// 縦の箱の列にすると、手すりは段鼻の線の真上にだけ立つ。
    def railSegments(n: Int32, b: CollisionShape3d.Box3d): List[CollisionShape3d.Box3d] =
        let (thin, thick) = thinnest(b);
        let others = (b#ax, b#half#x) :: (b#ay, b#half#y) :: (b#az, b#half#z) :: Nil |> List.filter(e -> Vec3.dot(fst(e), thin) < 0.5 and Vec3.dot(fst(e), thin) > -0.5);
        // 長さの向き（長い方）と高さの向き（短い方。上を向くようにそろえる）。
        let sorted = others |> List.sortBy(e -> 0.0 - snd(e));
        match sorted {
            case (len, hl) :: (hgt, hh) :: _ =>
                let up = if (hgt#y >= 0.0) hgt else Vec3.mul(hgt, -1.0);
                let nose = (s: Float64) -> Vec3.add(Vec3.sub(b#center, Vec3.mul(up, hh)), Vec3.mul(len, s));
                let height = 2.0 * hh;
                List.range(0, n) |> List.filterMap(k -> {
                    let p0 = nose(0.0 - hl + 2.0 * hl * Int32.toFloat64(k) / Int32.toFloat64(n));
                    let p1 = nose(0.0 - hl + 2.0 * hl * Int32.toFloat64(k + 1) / Int32.toFloat64(n));
                    let flat = Vec3.v3(p1#x - p0#x, 0.0, p1#z - p0#z);
                    let span = Vec3.length(flat);
                    if (span < 0.001) None
                    else {
                        let ax = Vec3.mul(flat, 1.0 / span);
                        let ay = Vec3.v3(0.0, 1.0, 0.0);
                        let az = Vec3.normalized(Vec3.cross(ax, ay));
                        let lo = Float64.min(p0#y, p1#y);
                        let hi = Float64.max(p0#y, p1#y) + height;
                        Some({ center = Vec3.v3((p0#x + p1#x) / 2.0, (lo + hi) / 2.0, (p0#z + p1#z) / 2.0), ax = ax, ay = ay, az = az,
                               half = Vec3.v3(span / 2.0, (hi - lo) / 2.0, thick) })
                    }
                })
            case _ => b :: Nil
        }

    // ── 歩ける範囲 ──

    /// 囲みの壁と地面の板の厚さ（m）。
    def slab(): Float64 = 1.0

    /// 歩ける範囲 bounds の外側に立てる 4 枚の壁（内側の面が範囲の端から体の半径 radius だけ外 — 体の真ん中は範囲の端まで行ける）と、
    /// 当たり判定の箱の無い所の地面（上の面が groundY の板。側溝・歩道の継ぎ目で落ちない）。
    /// WhyNot: 体の位置を範囲へ丸めない — 丸めた位置は壁から押し出した後の位置とぶつかり、範囲の端の壁へ押し戻しうる。
    def enclosureOf(bounds: WalkDoc.Bounds, groundY: Float64, radius: Float64): List[CollisionShape3d.Box3d] =
        let t = slab();
        let (x0, x1, z0, z1) = (bounds#minX - radius, bounds#maxX + radius, bounds#minZ - radius, bounds#maxZ + radius);
        let (cx, cz) = ((x0 + x1) / 2.0, (z0 + z1) / 2.0);
        let (hx, hz) = ((x1 - x0) / 2.0 + t, (z1 - z0) / 2.0 + t);
        let (cy, hy) = (groundY + 50.0, 100.0);
        let box = (c: Vec3.Vec3, h: Vec3.Vec3) -> CollisionShape3d.box3d(c, h);
        box(Vec3.v3(cx, groundY - t / 2.0, cz), Vec3.v3(hx, t / 2.0, hz))
            :: box(Vec3.v3(x0 - t / 2.0, cy, cz), Vec3.v3(t / 2.0, hy, hz))
            :: box(Vec3.v3(x1 + t / 2.0, cy, cz), Vec3.v3(t / 2.0, hy, hz))
            :: box(Vec3.v3(cx, cy, z0 - t / 2.0), Vec3.v3(hx, hy, t / 2.0))
            :: box(Vec3.v3(cx, cy, z1 + t / 2.0), Vec3.v3(hx, hy, t / 2.0))
            :: Nil

    /// 1 マスの幅（m）。体のまわりを引く時に見る箱の数と、格子に入れる時の重なりの釣り合い。
    def cellSize(): Float64 = 2.0

    /// 動かない箱 boxes と歩ける範囲の囲みを入れた当たり判定の集まり。
    pub def worldOf(boxes: List[CollisionShape3d.Box3d], walk: WalkDoc.Rec): CollisionWorld3d.CollisionWorld3d =
        CollisionWorld3d.build(cellSize(), List.append(boxes, enclosureOf(walk#bounds, walk#groundY, walk#radius)))
}
