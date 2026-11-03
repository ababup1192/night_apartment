// RoomsDoc — rooms.kind.json（2 階の部屋の玄関の扉・部屋を描く距離・部屋の灯り）の宣言ドキュメント層。
// 扉の蝶番・部屋の囲み・灯りの置き場所は書き出し（manifest.json の rooms）が正で、ここは手で詰める数だけを持つ。
// 扉の回り方・どの扉を動かすか・どの部屋を描くかの規則はコード（Doors・Rooms）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod RoomsDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 玄関の扉: 回る速さ（度/秒）・E で開け切る角（度。負で外廊下へ。書き出しの止まる角より先へは回さない）・
    /// E が届く距離（足元から扉の板の真ん中まで m）・扉を向いているとみなす角（度）。
    pub type alias Door = { speedDeg = Float64, openDeg = Float64, reach = Float64, facingDeg = Float64 }

    /// 部屋を描くか: 部屋の囲みの外へ足す幅（m。囲みの中に目があれば描く）・開いた扉越しに描く距離（目から扉まで m）・
    /// 扉を見ているとみなす角（度。目の向きから扉までの角がこれより小さい時だけ扉越しに描く）・
    /// これより近ければ向きによらず描く距離（m）・開いているとみなす角（度）。
    pub type alias Draw = { insideMargin = Float64, seeRange = Float64, seeConeDeg = Float64, nearRange = Float64, ajarDeg = Float64 }

    /// 部屋の灯り（ベイクにも入っている光を、動く物と扉のために薄く足す）: Blender の 1 W あたりの強さ・強さの下限と上限・
    /// 届く距離の倍率・ちらつく灯り（テレビ）の明るい時の強さと、一番暗い所（0..1）と 1 秒に替わる回数。
    pub type alias Light = { gain = Float64, minIntensity = Float64, maxIntensity = Float64, rangeScale = Float64,
                             tvIntensity = Float64, tvMin = Float64, tvRate = Float64 }

    pub type alias Rec = {
        version = Int32,
        door = Door,
        draw = Draw,
        light = Light
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/rooms.kind.json"

    /// コード側の既定値（assets/rooms.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  door = { speedDeg = 95.0, openDeg = -88.0, reach = 1.7, facingDeg = 55.0 },
                  draw = { insideMargin = 0.4, seeRange = 14.0, seeConeDeg = 80.0, nearRange = 1.6, ajarDeg = 1.0 },
                  light = { gain = 0.02, minIntensity = 0.04, maxIntensity = 0.35, rangeScale = 1.0, tvIntensity = 0.6, tvMin = 0.2, tvRate = 7.0 } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(name: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(name, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let dr = objectOf("door", root);
        let dw = objectOf("draw", root);
        let li = objectOf("light", root);
        let num = (o, key, fallback) -> JsonCodec.floatOr(key, fallback, o);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  door = { speedDeg = num(dr, "speedDeg", d#door#speedDeg), openDeg = num(dr, "openDeg", d#door#openDeg),
                           reach = num(dr, "reach", d#door#reach), facingDeg = num(dr, "facingDeg", d#door#facingDeg) },
                  draw = { insideMargin = num(dw, "insideMargin", d#draw#insideMargin), seeRange = num(dw, "seeRange", d#draw#seeRange),
                           seeConeDeg = num(dw, "seeConeDeg", d#draw#seeConeDeg), nearRange = num(dw, "nearRange", d#draw#nearRange),
                           ajarDeg = num(dw, "ajarDeg", d#draw#ajarDeg) },
                  light = { gain = num(li, "gain", d#light#gain), minIntensity = num(li, "minIntensity", d#light#minIntensity),
                            maxIntensity = num(li, "maxIntensity", d#light#maxIntensity), rangeScale = num(li, "rangeScale", d#light#rangeScale),
                            tvIntensity = num(li, "tvIntensity", d#light#tvIntensity),
                            tvMin = num(li, "tvMin", d#light#tvMin), tvRate = num(li, "tvRate", d#light#tvRate) } })
}
