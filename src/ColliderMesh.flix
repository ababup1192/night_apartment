// ColliderMesh — 当たり判定の箱と体を、場面に重ねて描く形にする（調べる時の表示。純粋）。
// 箱は 12 本の辺を細い角柱にした線の形（中の場面が見える）、体は球の高さごとの小さな箱。
mod ColliderMesh {
    use fge::{Color, Mesh3d, Vec3}

    /// 辺の太さ（m）。
    def thickness(): Float64 = 0.015

    /// 箱 1 つの 8 つの角（world）。
    def cornersOf(b: Collider.Box): List[Vec3.Vec3] =
        let signs = (-1.0, -1.0, -1.0) :: (1.0, -1.0, -1.0) :: (1.0, 1.0, -1.0) :: (-1.0, 1.0, -1.0) ::
                    (-1.0, -1.0, 1.0) :: (1.0, -1.0, 1.0) :: (1.0, 1.0, 1.0) :: (-1.0, 1.0, 1.0) :: Nil;
        signs |> List.map(s -> {
            let (sx, sy, sz) = s;
            Vec3.add(b#center, Vec3.add(Vec3.mul(b#ax, sx * b#half#x), Vec3.add(Vec3.mul(b#ay, sy * b#half#y), Vec3.mul(b#az, sz * b#half#z))))
        })

    /// 箱の 12 本の辺（角の番号の組）。
    def edges(): List[(Int32, Int32)] =
        (0, 1) :: (1, 2) :: (2, 3) :: (3, 0) :: (4, 5) :: (5, 6) :: (6, 7) :: (7, 4) :: (0, 4) :: (1, 5) :: (2, 6) :: (3, 7) :: Nil

    /// 頂点の並びを、外（from の反対）から見て時計回りに並べ直す（Newell の法線が外を向かなければ逆順）。
    def facing(out: Vec3.Vec3, pts: List[Vec3.Vec3]): List[Vec3.Vec3] =
        let pairs = List.zip(pts, List.append(List.drop(1, pts), List.take(1, pts)));
        let n = pairs |> List.foldLeft((acc, e) -> {
            let (a, b) = e;
            Vec3.v3(acc#x + (a#y - b#y) * (a#z + b#z), acc#y + (a#z - b#z) * (a#x + b#x), acc#z + (a#x - b#x) * (a#y + b#y))
        }, Vec3.zero());
        if (Vec3.dot(n, out) >= 0.0) pts else List.reverse(pts)

    /// a から b への細い角柱の 4 つの横の面。
    def bar(a: Vec3.Vec3, b: Vec3.Vec3, color: Color): List[Mesh3d.Polygon] =
        let d = Vec3.normalized(Vec3.sub(b, a));
        let pick = if (Float64.abs(d#y) < 0.9) Vec3.v3(0.0, 1.0, 0.0) else Vec3.v3(1.0, 0.0, 0.0);
        let u = Vec3.mul(Vec3.normalized(Vec3.cross(d, pick)), thickness());
        let v = Vec3.mul(Vec3.normalized(Vec3.cross(d, u)), thickness());
        let sides = (u, v) :: (v, Vec3.mul(u, -1.0)) :: (Vec3.mul(u, -1.0), Vec3.mul(v, -1.0)) :: (Vec3.mul(v, -1.0), u) :: Nil;
        sides |> List.map(s -> {
            let (p, q) = s;
            let pts = Vec3.add(a, p) :: Vec3.add(b, p) :: Vec3.add(b, q) :: Vec3.add(a, q) :: Nil;
            { points = facing(Vec3.add(p, q), pts), color = color }
        })

    /// 全部の箱の辺の形（傾いた箱は別の色）。
    pub def boxesMesh(boxes: List[Collider.Box]): Mesh3d.Mesh3d =
        let flat = Color.rgb(0.2, 1.0, 0.45);
        let tilted = Color.rgb(1.0, 0.75, 0.2);
        boxes |> List.flatMap(b -> {
            let cs = cornersOf(b) |> List.toVector;
            let color = if (Float64.abs(b#ay#y) > 0.98 or Float64.abs(b#ax#y) > 0.98 or Float64.abs(b#az#y) > 0.98) flat else tilted;
            edges() |> List.flatMap(e -> { let (i, j) = e; bar(Vector.get(i, cs), Vector.get(j, cs), color) })
        }) |> Mesh3d.fromPolygons

    /// 体の形（足元が原点）: 球の高さごとに半径の大きさの箱の辺と、足元の十字。
    pub def bodyMesh(body: Collider.Body): Mesh3d.Mesh3d =
        let r = body#radius;
        let cubes = Collider.sphereHeights(body) |> List.map(h ->
            { center = Vec3.v3(0.0, h, 0.0), ax = Vec3.v3(1.0, 0.0, 0.0), ay = Vec3.v3(0.0, 1.0, 0.0), az = Vec3.v3(0.0, 0.0, 1.0), half = Vec3.v3(r, r, r) });
        let color = Color.rgb(1.0, 0.25, 0.3);
        let cross = List.append(bar(Vec3.v3(0.0 - r, 0.0, 0.0), Vec3.v3(r, 0.0, 0.0), color), bar(Vec3.v3(0.0, 0.0, 0.0 - r), Vec3.v3(0.0, 0.0, r), color));
        cubes |> List.flatMap(b -> {
            let cs = cornersOf(b) |> List.toVector;
            edges() |> List.flatMap(e -> { let (i, j) = e; bar(Vector.get(i, cs), Vector.get(j, cs), color) })
        }) |> List.append(cross) |> Mesh3d.fromPolygons
}
