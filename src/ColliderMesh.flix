// ColliderMesh — 当たり判定の箱と体を、場面に重ねて描く形にする（調べる時の表示。純粋）。
// 箱は 12 本の辺を細い角柱にした線の形（中の場面が見える。engine の CollisionShape3d.debugMesh）、体は押し出しに使う球ごとの小さな箱。
mod ColliderMesh {
    use fge::{CharacterBody3d, CollisionShape3d, Color, Mesh3d, Vec3}

    /// 箱の辺の形: 平らな箱（緑）と傾いた箱（階段の段板・斜めの手すり。橙）を別の形にする。
    pub def boxesMeshes(boxes: List[CollisionShape3d.Box3d]): List[Mesh3d.Mesh3d] =
        let (tilted, flat) = List.partition(Collider.isTilted, boxes);
        CollisionShape3d.debugMesh(flat, Color.rgb(0.2, 1.0, 0.45)) :: CollisionShape3d.debugMesh(tilted, Color.rgb(1.0, 0.75, 0.2)) :: Nil

    /// 動く箱（扉の板・住人）の辺の形。
    pub def movingMesh(boxes: List[CollisionShape3d.Box3d]): Mesh3d.Mesh3d = CollisionShape3d.debugMesh(boxes, Color.rgb(0.2, 1.0, 0.45))

    /// 体の形（足元が原点）: 押し出しに使う球ごとに半径の大きさの箱と、足元の薄い板。
    pub def bodyMesh(s: CharacterBody3d.Settings): Mesh3d.Mesh3d =
        let r = s#radius;
        let capsule = CharacterBody3d.capsuleOf(s, CharacterBody3d.bodyAt(Vec3.zero()));
        let spheres = CollisionShape3d.sphereCentersOf(capsule) |> List.map(c -> CollisionShape3d.box3d(c, Vec3.v3(r, r, r)));
        let feet = CollisionShape3d.box3d(Vec3.zero(), Vec3.v3(r, 0.005, r));
        CollisionShape3d.debugMesh(feet :: spheres, Color.rgb(1.0, 0.25, 0.3))
}
