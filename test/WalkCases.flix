// 壁と手すりへ向かって歩く場合を、決まった種の乱数でたくさん作る（毎回同じ場合の列）。
// 作るのは場合の入力だけで、判定は Collider.deepestOverlap と、建物の中に入っていないかの 2 つ（TestWalkProperty）。
mod WalkCases {
    use fge::Hash01

    /// 1 つの場合: 名前・始まりの足元と向き・走るか・1 コマの秒・何コマ歩くか。
    pub type alias Case = { name = String, x = Float64, feet = Float64, z = Float64, yaw = Float64, sprint = Bool, dt = Float64, frames = Int32 }

    /// 歩ける所の種（足元の x・z・おおよその高さ）。道路・自販機の前・門・敷地・1 階と 2〜4 階の外廊下・外階段の踊り場。
    def seeds(): List[(Float64, Float64, Float64)] =
        (0.0, 9.5, 0.0) :: (-2.6, 7.0, 0.0) :: (-7.0, 6.0, 0.0) :: (-7.0, 3.5, 0.0) :: (-13.0, 3.6, 0.0) :: (-1.5, 3.0, 0.0) ::
        (-6.0, 0.8, 0.3) :: (-12.0, 0.75, 0.3) :: (-6.0, 0.8, 3.1) :: (-14.0, 0.8, 3.1) :: (-6.0, 0.8, 5.9) :: (-10.0, 0.8, 8.7) ::
        (-18.2, 0.6, 0.3) :: (-18.3, -2.0, 1.7) :: (-18.2, 0.6, 3.1) :: (-18.3, -2.0, 4.5) :: Nil

    /// 種ごとに、向き・ずれ・速さ・刻みを番号の乱数で振った n 個の場合。
    pub def random(n: Int32): List[Case] =
        let ss = seeds() |> List.toVector;
        let count = Vector.length(ss);
        List.range(0, n) |> List.map(i -> {
            let (sx, sz, sy) = Vector.get(Int32.modulo(i, count), ss);
            let fast = Hash01.at(i, 4) < 0.3;
            { name = "random-${Int32.toString(i)}", x = sx + (Hash01.at(i, 1) - 0.5) * 0.6, feet = sy + 0.05, z = sz + (Hash01.at(i, 2) - 0.5) * 0.3,
              yaw = Hash01.at(i, 3) * 360.0, sprint = fast or Hash01.at(i, 5) < 0.4, dt = if (fast) 0.05 else 1.0 / 60.0, frames = 75 }
        })

    /// 必ず入れる場合: 角・継ぎ目・薄い壁・手すり・速く走った時（1 コマ 0.05 秒で走る）。
    pub def edges(): List[Case] =
        let dash = (name: String, x: Float64, feet: Float64, z: Float64, yaw: Float64) ->
            { name = name, x = x, feet = feet, z = z, yaw = yaw, sprint = true, dt = 0.05, frames = 60 };
        dash("2F parapet head-on", -8.0, 3.15, 0.7, 0.0)
            :: dash("2F parapet glancing", -8.0, 3.15, 0.7, 30.0)
            :: dash("2F front wall", -8.0, 3.15, 0.7, 180.0)
            :: dash("2F corridor west end corner", -1.0, 3.15, 0.7, 45.0)
            :: dash("2F landing rail east", -18.5, 3.15, 0.6, 270.0)
            :: dash("2F landing rail front", -18.5, 3.15, 0.6, 0.0)
            :: dash("2F landing into building corner", -17.6, 3.15, 0.3, 135.0)
            :: dash("flight A side rail", -17.68, 1.0, -0.75, 270.0)
            :: dash("flight A wall side", -17.68, 1.0, -0.75, 90.0)
            :: dash("flight B outer rail", -18.85, 2.4, -0.75, 270.0)
            :: dash("flight B inner rail", -18.85, 2.4, -0.75, 90.0)
            :: dash("mid landing back rail", -18.3, 1.75, -2.0, 180.0)
            :: dash("mid landing east rail", -18.3, 1.75, -2.0, 270.0)
            :: dash("block wall thin", -12.0, 0.05, 5.6, 0.0)
            :: dash("block wall seam at gate post", -5.2, 0.05, 5.5, 20.0)
            :: dash("gate post corner", -8.65, 0.05, 5.4, 0.0)
            :: dash("vending machine face", -2.6, 0.05, 7.0, 180.0)
            :: dash("between vending machines", -2.58, 0.05, 6.6, 180.0)
            :: dash("1F front wall", -8.0, 0.35, 0.7, 180.0)
            :: dash("building east wall from behind the stairs", -18.6, 0.05, -4.0, 90.0)
            :: dash("building west wall from the side yard", 1.5, 0.05, -3.0, 270.0)
            :: dash("air conditioner 2F", -14.8, 3.15, 0.75, 270.0)
            :: dash("under the mid landing from behind", -17.7, 0.05, -3.2, 0.0)
            :: dash("under flight B toward its low end", -18.85, 0.05, 0.6, 180.0)
            :: dash("under the stairs across", -19.0, 0.05, -1.0, 90.0)
            :: Nil
}
