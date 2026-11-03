// Collider — 当たり判定の箱（collision.glb）と、体をその中で動かす規則（純粋）。
//
// 箱は向きのある直方体（階段の段板と斜めの手すりは傾いている）。体は縦に並べた球の列で、
// 足元から段の高さより上だけを壁として扱う（段の高さより低い物は上に乗る）。
// 足元の高さは、体の真ん中と周りの 4 点から真下へ伸ばした線が最初に当たる箱の上の面で決める
// （階段の段板は斜めの板なので、上り下りは坂になる）。
mod Collider {
    use fge::{Mesh3d, Model3d, Vec2, Vec3}

    /// 向きのある箱 1 つ。center = 真ん中・ax / ay / az = 3 本の向き（長さ 1・互いに直角）・half = 各向きの半分の長さ。
    pub type alias Box = { center = Vec3.Vec3, ax = Vec3.Vec3, ay = Vec3.Vec3, az = Vec3.Vec3, half = Vec3.Vec3 }

    /// 体の寸法: 半径・高さ・そのまま上がれる段の高さ。
    pub type alias Body = { radius = Float64, height = Float64, stepHeight = Float64 }

    /// collision.glb の部品ごとの箱（頂点の無い部品は捨てる）。斜めの手すりは縦の短い箱の列に置き換える（railSegments）。
    pub def boxesOf(model: Model3d.Model3d): List[Box] =
        model#parts |> List.filterMap(part -> boxOfMesh(part#mesh)) |> List.flatMap(b -> if (isSlantedRail(b)) railSegments(6, b) else b :: Nil)

    /// 斜めの手すり: 傾いた箱で、一番薄い向きがほぼ水平（段板は一番薄い向きがほぼ縦なので入らない）。
    def isSlantedRail(b: Box): Bool =
        let (thin, _) = thinnest(b);
        isTilted(b) and Float64.abs(thin#y) < 0.3

    /// 一番薄い向きと、その半分の厚さ。
    def thinnest(b: Box): (Vec3.Vec3, Float64) =
        if (b#half#x <= b#half#y and b#half#x <= b#half#z) (b#ax, b#half#x)
        else if (b#half#y <= b#half#z) (b#ay, b#half#y)
        else (b#az, b#half#z)

    /// 斜めの手すりの箱を、段鼻の線に沿った n 本の縦の箱に分ける。
    /// 書き出しの箱は高さの向きが坂に直角で、上の端が踊り場の上へ斜めにはみ出す（1.1 m の高さで 0.75 m ほど）。
    /// 縦の箱の列にすると、手すりは段鼻の線の真上にだけ立つ。
    def railSegments(n: Int32, b: Box): List[Box] =
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

    /// 形 1 つを囲む向きのある箱。向きは面の法線から取る（箱の面は 3 組の向きしか持たない）。
    /// 法線が 1 組しか無い板（道路の面）は、法線と直角な向きを world の軸から作る。
    def boxOfMesh(m: Mesh3d.Mesh3d): Option[Box] =
        let pos = Mesh3d.positions(m);
        let nrm = Mesh3d.normals(m);
        let count = Vector.length(pos) / 3;
        if (count == 0) None
        else {
            let at = (v: Vector[Float64], i: Int32) -> Vec3.v3(Vector.get(3 * i, v), Vector.get(3 * i + 1, v), Vector.get(3 * i + 2, v));
            let normals = List.range(0, Vector.length(nrm) / 3) |> List.map(i -> at(nrm, i)) |> List.filter(n -> Vec3.length(n) > 0.5);
            let first = List.head(normals) |> Option.map(Vec3.normalized) |> Option.getWithDefault(Vec3.v3(0.0, 1.0, 0.0));
            let second = normals |> List.find(n -> Float64.abs(Vec3.dot(Vec3.normalized(n), first)) < 0.5)
                |> Option.map(Vec3.normalized) |> Option.getWithDefault(leastAligned(first));
            let ax = first;
            let az = Vec3.normalized(Vec3.cross(ax, second));
            let ay = Vec3.normalized(Vec3.cross(az, ax));
            let points = List.range(0, count) |> List.map(i -> at(pos, i));
            let span = (a: Vec3.Vec3) -> {
                let ds = points |> List.map(q -> Vec3.dot(q, a));
                let lo = List.foldLeft(Float64.min, 1.0e18, ds);
                let hi = List.foldLeft(Float64.max, -1.0e18, ds);
                (lo, hi)
            };
            let (x0, x1) = span(ax);
            let (y0, y1) = span(ay);
            let (z0, z1) = span(az);
            let mid = Vec3.add(Vec3.add(Vec3.mul(ax, (x0 + x1) / 2.0), Vec3.mul(ay, (y0 + y1) / 2.0)), Vec3.mul(az, (z0 + z1) / 2.0));
            let thin = (lo: Float64, hi: Float64) -> Float64.max(0.005, (hi - lo) / 2.0);
            Some({ center = mid, ax = ax, ay = ay, az = az, half = Vec3.v3(thin(x0, x1), thin(y0, y1), thin(z0, z1)) })
        }

    /// a と最も揃っていない world の軸を、a と直角にした向き。
    def leastAligned(a: Vec3.Vec3): Vec3.Vec3 =
        let pick = if (Float64.abs(a#x) < 0.6) Vec3.v3(1.0, 0.0, 0.0) else Vec3.v3(0.0, 0.0, 1.0);
        Vec3.normalized(Vec3.sub(pick, Vec3.mul(a, Vec3.dot(pick, a))))

    /// 箱の向きの座標（箱の真ん中が 0・軸は ax / ay / az）。world の座標（素の Vec3）と取り違えないよう包む。
    enum Local(Vec3.Vec3)

    def unwrap(l: Local): Vec3.Vec3 = match l { case Local.Local(v) => v }

    /// world の点を箱の向きの座標へ。
    def toLocal(b: Box, p: Vec3.Vec3): Local =
        let d = Vec3.sub(p, b#center);
        Local.Local(Vec3.v3(Vec3.dot(d, b#ax), Vec3.dot(d, b#ay), Vec3.dot(d, b#az)))

    /// world の向きを箱の向きの座標へ（平行移動を受けない）。
    def toLocalDir(b: Box, d: Vec3.Vec3): Local =
        Local.Local(Vec3.v3(Vec3.dot(d, b#ax), Vec3.dot(d, b#ay), Vec3.dot(d, b#az)))

    /// 箱の向きの座標の向きを world へ。
    def toWorldDir(b: Box, local: Local): Vec3.Vec3 =
        let l = unwrap(local);
        Vec3.add(Vec3.add(Vec3.mul(b#ax, l#x), Vec3.mul(b#ay, l#y)), Vec3.mul(b#az, l#z))

    /// 箱の中で一番近い点（箱の向きの座標）。
    def clampInside(b: Box, local: Local): Local =
        let l = unwrap(local);
        Local.Local(Vec3.v3(clampTo(b#half#x, l#x), clampTo(b#half#y, l#y), clampTo(b#half#z, l#z)))

    def subLocal(a: Local, b: Local): Local = Local.Local(Vec3.sub(unwrap(a), unwrap(b)))

    def clampTo(h: Float64, v: Float64): Float64 = Float64.max(0.0 - h, Float64.min(h, v))

    /// 球（真ん中 c・半径 r）を箱の外へ出す水平のずれ (x, z)。重なっていなければ None。
    /// 真ん中が箱の中にある時と、上か下から触れている時は、水平に一番浅い向きへ出す。
    pub def pushOut(b: Box, c: Vec3.Vec3, r: Float64): Option[(Float64, Float64)] =
        let l = toLocal(b, c);
        let d = toWorldDir(b, subLocal(l, clampInside(b, l)));
        let dist = Vec3.length(d);
        if (dist >= r) None
        else if (dist > 0.000001) {
            let flat = Vec2.sqrt(d#x * d#x + d#z * d#z);
            let v2 = Float64.max(0.0, dist * dist - flat * flat);
            // 水平にだけ動かして解く: 縦の差はそのままなので、水平の差が sqrt(r² − 縦の差²) になるまで、差の水平の向きへ動かす。
            // WhyNot: 差の向きの長さ (r − dist) をそのまま水平へ写さない — 傾いた面（斜めの手すりの端）では押し切れず、割って補うと押し過ぎる。
            if (flat > 0.02 * r) {
                let k = (Vec2.sqrt(r * r - v2) - flat) / flat;
                Some((d#x * k, d#z * k))
            }
            // 真上か真下から触れている（段の高さを少し超える物の上面）: 水平の向きが無いので、箱の足元の一番浅い縁の向きへ、1 回に半径まで。
            else insidePush(b, l, r) |> Option.map(capTo(r))
        }
        else insidePush(b, l, r)

    /// 水平のずれの長さを m までに抑える（1 回の押し出しで体が大きく飛ばない）。
    def capTo(m: Float64, p: (Float64, Float64)): (Float64, Float64) =
        let (x, z) = p;
        let len = Vec2.sqrt(x * x + z * z);
        if (len <= m) p else (x * m / len, z * m / len)

    /// 真ん中が箱の中にある球を、水平の成分を持つ向きのうち一番浅い向きへ出すずれ。
    def insidePush(b: Box, local: Local, r: Float64): Option[(Float64, Float64)] =
        let l = unwrap(local);
        let candidates = (b#ax, b#half#x, l#x) :: (b#ay, b#half#y, l#y) :: (b#az, b#half#z, l#z) :: Nil;
        candidates
            |> List.filter(e -> { let (a, _, _) = e; Vec2.sqrt(a#x * a#x + a#z * a#z) > 0.5 })
            |> List.map(e -> { let (a, h, v) = e; (h - Float64.abs(v), a, if (v >= 0.0) 1.0 else -1.0) })
            |> List.minimumBy((p, q) -> { let (dp, _, _) = p; let (dq, _, _) = q; Order.compare(dp, dq) })
            |> Option.map(e -> {
                let (depth, a, sign) = e;
                let k = (depth + r) * sign;
                (a#x * k, a#z * k)
            })

    /// 真下へ伸ばした線（origin から下へ maxDrop まで）が箱の上の面に当たる高さ。当たらない・始まりが箱の中なら None。
    def hitBelow(b: Box, origin: Vec3.Vec3, maxDrop: Float64): Option[Float64] =
        let o = unwrap(toLocal(b, origin));
        let d = unwrap(toLocalDir(b, Vec3.v3(0.0, -1.0, 0.0)));
        let slab = (ov: Float64, dv: Float64, h: Float64) ->
            if (Float64.abs(dv) < 0.000001) (if (Float64.abs(ov) <= h) Some((-1.0e18, 1.0e18)) else None)
            else {
                let t1 = (0.0 - h - ov) / dv;
                let t2 = (h - ov) / dv;
                Some((Float64.min(t1, t2), Float64.max(t1, t2)))
            };
        forM (
            sx <- slab(o#x, d#x, b#half#x);
            sy <- slab(o#y, d#y, b#half#y);
            sz <- slab(o#z, d#z, b#half#z);
            hit <- {
                let tmin = Float64.max(fst(sx), Float64.max(fst(sy), fst(sz)));
                let tmax = Float64.min(snd(sx), Float64.min(snd(sy), snd(sz)));
                if (tmin >= 0.0 and tmin <= tmax and tmin <= maxDrop) Some(origin#y - tmin) else None
            }
        ) yield hit

    /// 拾った床: 高さと、傾いた面（階段の段板）か。
    pub type alias Ground = { y = Float64, slope = Bool }

    /// 箱の上を向く面が傾いているか（3 本の向きのどれも、ほぼ真上を向いていない）。
    def isTilted(b: Box): Bool =
        Float64.abs(b#ax#y) < 0.98 and Float64.abs(b#ay#y) < 0.98 and Float64.abs(b#az#y) < 0.98

    /// 足元 (x, feet, z) の下で、段の高さより上から下へ drop まで探した一番高い床。無ければ None。
    /// 体の真ん中の真下で決め、真ん中の下に床が無い時（板の継ぎ目・縁）だけ、半径の 0.6 倍だけ離れた 4 点から探す。
    /// WhyNot: 5 点の一番高い所を取らない — 斜めの手すりの端の面を縁の点が拾い、体が手すりに乗り上げて上下に震える。
    pub def groundBelow(boxes: List[Box], body: Body, x: Float64, feet: Float64, z: Float64, drop: Float64): Option[Ground] =
        let top = feet + body#stepHeight;
        let probe = (dx: Float64, dz: Float64) ->
            boxes |> List.filterMap(b -> hitBelow(b, Vec3.v3(x + dx, top, z + dz), body#stepHeight + drop) |> Option.map(y -> { y = y, slope = isTilted(b) }));
        let highest = (gs: List[Ground]) -> List.maximumBy((a, b) -> Order.compare(a#y, b#y), gs);
        let k = body#radius * 0.6;
        match highest(probe(0.0, 0.0)) {
            case Some(g) => Some(g)
            case None    => highest(List.flatten(probe(k, 0.0) :: probe(0.0 - k, 0.0) :: probe(0.0, k) :: probe(0.0, 0.0 - k) :: Nil))
        }

    /// 体が箱に食い込んでいる深さの一番大きい物（m。食い込んでいなければ 0）。テストと当たり判定の表示が読む。
    pub def deepestOverlap(boxes: List[Box], body: Body, x: Float64, feet: Float64, z: Float64): Float64 =
        sphereHeights(body) |> List.flatMap(h -> boxes |> List.map(b -> {
            let l = toLocal(b, Vec3.v3(x, feet + h, z));
            let d = Vec3.length(toWorldDir(b, subLocal(l, clampInside(b, l))));
            Float64.max(0.0, body#radius - d)
        })) |> List.foldLeft(Float64.max, 0.0)

    /// 体の球の真ん中の高さ（足元から）: 段の高さより上から、頭の手前まで、半径ほどの間で並べる。
    pub def sphereHeights(body: Body): List[Float64] =
        let lo = body#stepHeight + body#radius;
        let hi = Float64.max(lo, body#height - body#radius);
        let n = Int32.max(1, Float64.tryToInt32(Float64.ceil((hi - lo) / Float64.max(0.05, body#radius * 2.0))) |> Option.getWithDefault(1));
        List.range(0, n + 1) |> List.map(i -> lo + (hi - lo) * Int32.toFloat64(i) / Int32.toFloat64(n))

    /// 足元 (x, feet, z) の体を箱の外へ出した水平の位置。押し出しを 3 回くり返す（角で 2 枚に挟まれた時）。
    pub def resolve(boxes: List[Box], body: Body, x: Float64, feet: Float64, z: Float64): (Float64, Float64) =
        let heights = sphereHeights(body);
        let once = (p: (Float64, Float64)) -> {
            let (px, pz) = p;
            heights |> List.foldLeft((acc, h) -> {
                let (ax, az) = acc;
                boxes |> List.foldLeft((inner, b) -> {
                    let (ix, iz) = inner;
                    match pushOut(b, Vec3.v3(ix, feet + h, iz), body#radius) {
                        case Some((dx, dz)) => (ix + dx, iz + dz)
                        case None           => inner
                    }
                }, (ax, az))
            }, (px, pz))
        };
        once(once(once((x, z))))

    /// 足元の点の近く（水平の距離 reach の中）にある箱だけ（毎コマ全部の箱を球ごとに見ない）。
    pub def near(boxes: List[Box], x: Float64, z: Float64, reach: Float64): List[Box] =
        boxes |> List.filter(b -> {
            let ext = Float64.abs(b#ax#x) * b#half#x + Float64.abs(b#ay#x) * b#half#y + Float64.abs(b#az#x) * b#half#z;
            let ezt = Float64.abs(b#ax#z) * b#half#x + Float64.abs(b#ay#z) * b#half#y + Float64.abs(b#az#z) * b#half#z;
            Float64.abs(b#center#x - x) <= ext + reach and Float64.abs(b#center#z - z) <= ezt + reach
        })
}
