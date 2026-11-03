// RoomLights — 2 階の部屋の灯りを、場面の点光源にする規則（純粋）。
//
// 部屋の灯りはベイクにも入っているので、動く物（扉・手の灯りで照らす物）のために薄く足すだけにする（強さは RoomsDoc）。
// 影の無い点光源は壁を抜けて隣の部屋や外廊下を照らすので、描いている部屋の灯りだけを足す。
// 選ぶのは engine（Scene3d.pickLights が目に近い Scene3d.maxPointLights() 本を選ぶ）。
mod RoomLights {
    use fge::{Color, Scene3d}

    /// 灯り 1 つの今の強さ: Blender の W × gain を下限と上限に収めた値。ちらつく灯り（テレビ）は tvIntensity にテレビの明るさを掛ける
    /// （ベイクのテレビの光は動かないので、ちらつきは動く光の方で目立たせる）。
    def intensityOf(doc: RoomsDoc.Light, t: Float64, seed: Int32, light: Rooms.Light): Float64 =
        if (light#flicker) doc#tvIntensity * Flicker.tvLevel(t, doc#tvRate, doc#tvMin, seed)
        else Float64.max(doc#minIntensity, Float64.min(doc#maxIntensity, light#watts * doc#gain))

    /// 描いている部屋（drawn）の灯りを点光源へ。
    pub def pointsOf(doc: RoomsDoc.Light, t: Float64, drawn: Set[String], rooms: List[Rooms.Room]): List[Scene3d.PointLight] =
        rooms |> List.filter(r -> Set.memberOf(r#id, drawn)) |> List.flatMap(r ->
            r#lights |> List.zipWithIndex |> List.map(e -> {
                let (i, l) = e;
                let (cr, cg, cb) = l#color;
                { position = l#position, color = Color.rgb(cr, cg, cb), intensity = intensityOf(doc, t, 71 + i, l),
                  range = l#range * doc#rangeScale }
            }))

}
