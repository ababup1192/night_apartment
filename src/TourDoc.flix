// TourDoc — tour.route.json（紹介の動画で歩く道筋）の宣言ドキュメント層。
// 道筋は通る点の並び。点へどう歩くか（向きの変え方・待ち方）はコード（Pilot）。
// fail-open — 読めない・壊れているときは defaults() へ落とす。
mod TourDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 通る点 1 つ: 名前・足元の x・z・着いてから待つ秒・待つ間に向く向き（度。None なら歩いて来た向きのまま）・
    /// 待つ間に見上げる角（度。正で下を向く）・この点へは走るか・
    /// 着いて向き終えたら E を押すか（玄関の扉の開け閉め）・着いた所で手の灯りをどうするか（JSON の light が true / false。書かなければ Keep）。
    pub type alias Point = { name = String, x = Float64, z = Float64, wait = Float64,
                             lookYaw = Option[Float64], lookPitch = Float64, sprint = Bool, press = Bool, light = PlayStep.LightCue }

    pub type alias Rec = {
        version = Int32,
        // 歩き出す所と向き（度）。
        startX = Float64,
        startZ = Float64,
        startYaw = Float64,
        // 歩きながら向きを変える速さ（度/秒）と、点に着いたとみなす距離（m）。
        turnRate = Float64,
        arriveRadius = Float64,
        points = List[Point]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/tour.route.json"

    /// コード側の既定値（道筋そのものは JSON が正なので、ここは 1 点だけ）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, startX = 1.5, startZ = 10.2, startYaw = 200.0, turnRate = 90.0, arriveRadius = 0.3,
                  points = { name = "vending", x = -2.6, z = 7.4, wait = 2.0, lookYaw = Some(180.0), lookPitch = 0.0, sprint = false,
                             press = false, light = PlayStep.LightCue.Keep } :: Nil })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def pointOf(obj: Map[String, Json]): Option[Point] =
        let num = key -> Map.get(key, obj) |> Option.flatMap(JsonCodec.expectFloat);
        forM (x <- num("x"); z <- num("z")) yield
            { name = JsonCodec.stringOr("name", "", obj), x = x, z = z, wait = JsonCodec.floatOr("wait", 0.0, obj),
              lookYaw = num("lookYaw"), lookPitch = JsonCodec.floatOr("lookPitch", 0.0, obj),
              sprint = JsonCodec.boolOr("run", false, obj), press = JsonCodec.boolOr("press", false, obj),
              light = Map.get("light", obj) |> Option.flatMap(JsonCodec.expectBool) |> Option.map(lightCueOf) |> Option.getWithDefault(PlayStep.LightCue.Keep) }

    /// JSON の light（true = 点ける・false = 消す）を灯りの指示へ（書かない点は呼ぶ側で Keep）。
    def lightCueOf(on: Bool): PlayStep.LightCue = if (on) PlayStep.LightCue.TurnOn else PlayStep.LightCue.TurnOff

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  startX = f("startX", d#startX), startZ = f("startZ", d#startZ), startYaw = f("startYaw", d#startYaw),
                  turnRate = f("turnRate", d#turnRate), arriveRadius = f("arriveRadius", d#arriveRadius),
                  points = Map.get("points", root)
                      |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))
                      |> Option.map(rows -> rows |> List.filterMap(pointOf))
                      |> Option.getWithDefault(d#points) })
}
