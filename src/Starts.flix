// Starts — 始まりの登録簿（App.withStarts）。名前と引数から、新しく作った初期の World を場面へ組む。
// 起動（START="tour"）・flow の `start tour`・テストの App.startOrBug が同じ表を引く。
mod Starts {
    use fge::Resources

    /// 登録簿。先頭が起動の既定。
    pub def all(): List[Resources.Start[Res.Res, World.World]] =
        { name = "play", doc = "道路の端に立つ所（起動の既定）", args = Map.empty(), build = (_, w, _) -> Ok(w) } ::
        { name = "at", doc = "足元 x・z（m。y はその階のおおよその高さ）に、向き yaw・見下ろす角 pitch（度。0 が +Z・pitch は負で見上げる）で立つ所。fov（度）が 0 より大きければ縦の画角を替える。足元は床に合わせる。t（秒）だけ遊びの時計を進めておく（住人の動きの秒）。stairs（秒）が 0 以上なら、階段の人がその動きの秒の所を歩いている。diag=1 なら F3 の診断を出しておく",
          args = Map#{"x" => "0", "y" => "0", "z" => "0", "yaw" => "0", "pitch" => "0", "fov" => "0", "t" => "0", "stairs" => "-1", "diag" => "0"}, build = at } ::
        { name = "tour", doc = "紹介の動画の道筋（tour.route.json）を自動で歩き始める所。from に点の名前を書くと、その点（おおよその高さ y m）に立って次の点から歩く",
          args = Map#{"from" => "", "y" => "0"}, build = tour } :: Nil

    def tour(res: Res.Res, w: World.World, args: Map[String, String]): Result[String, World.World] =
        let after = Map.getWithDefault("from", "", args);
        if (String.isEmpty(after)) Ok(World.withPilot(res, w))
        else numOf("y", args) |> Result.flatMap(y -> World.withPilotAfter(res, after, y, w))

    def at(res: Res.Res, w: World.World, args: Map[String, String]): Result[String, World.World] =
        forM (
            x <- numOf("x", args);
            y <- numOf("y", args);
            z <- numOf("z", args);
            yaw <- numOf("yaw", args);
            pitch <- numOf("pitch", args);
            fov <- numOf("fov", args);
            t <- numOf("t", args);
            stairs <- numOf("stairs", args)
        ) yield {
            let placed = World.placeWalker(res, { x = x, y = y, z = z }, yaw, pitch, World.advancedBy(t, w)) |> World.withFov(if (fov > 0.0) Some(fov) else None);
            let walking = if (stairs >= 0.0) World.withStairsAt(stairs, placed) else placed;
            if (Map.get("diag", args) == Some("1")) World.toggleDiagnostics(walking) else walking
        }

    def numOf(name: String, args: Map[String, String]): Result[String, Float64] =
        let text = Map.getWithDefault(name, "0", args);
        Float64.fromString(text) |> Option.toOk("${name} は数（'${text}'）")
}
