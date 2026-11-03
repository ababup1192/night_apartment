// PeopleDoc — people.kind.json（住人の灯り・音の大きさ・階段の人が歩き出す所）の宣言ドキュメント層。
// 住人の置き場所・向き・動き・当たり判定のカプセル・照らす灯りは書き出し（manifest.json の people）が正で、ここは手で詰める数だけ。
// いつ鳴らすか・どこで歩き出すか・どう照らすかの規則はコード（People・Sounds）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod PeopleDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 住人を照らす灯り（manifest の lights。部屋の灯りと同じ名前の物は部屋の方を使う）: Blender の 1 W あたりの強さ・強さの上限・届く距離の倍率。
    pub type alias Light = { gain = Float64, maxIntensity = Float64, rangeScale = Float64 }

    /// 範囲（足元の x・z と高さ y）。
    pub type alias Area = { minX = Float64, maxX = Float64, minZ = Float64, maxZ = Float64, minY = Float64, maxY = Float64 }

    /// 階段ですれ違う人: 足元がこの範囲に入ったら 1 回だけ歩き出す・歩き出す時の動きの秒（途中から始めると、見えない所から降りてくる）。
    pub type alias Stairs = { trigger = Area, startS = Float64 }

    /// 住人の音: 聞こえる距離（m）・すぐそばでの大きさ（頭を打つ・地団駄・足音）・
    /// 別の部屋や閉じた扉の向こうで聞く時の大きさの倍率と、高い音の残り具合（0..1。小さいほど籠もる）・開いた扉越しの高い音の残り具合。
    pub type alias Sound = { range = Float64, hitVolume = Float64, stompVolume = Float64, stepVolume = Float64,
                             wallVolume = Float64, wallHF = Float64, doorHF = Float64 }

    /// 読む時に絵を縮める長い辺の上限（px）。
    pub type alias TextureMax = { baseColor = Int32, normal = Int32 }

    pub type alias Rec = {
        version = Int32,
        light = Light,
        stairs = Stairs,
        sound = Sound,
        textureMax = TextureMax
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/people.kind.json"

    /// コード側の既定値（assets/people.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  light = { gain = 0.08, maxIntensity = 0.6, rangeScale = 1.0 },
                  stairs = { trigger = { minX = -18.4, maxX = -17.0, minZ = -2.0, maxZ = 1.1, minY = 0.2, maxY = 1.8 }, startS = 10.133 },
                  sound = { range = 14.0, hitVolume = 0.85, stompVolume = 0.75, stepVolume = 0.7, wallVolume = 0.55, wallHF = 0.12, doorHF = 0.45 },
                  textureMax = { baseColor = 2048, normal = 1024 } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(name: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(name, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let li = objectOf("light", root);
        let st = objectOf("stairs", root);
        let so = objectOf("sound", root);
        let tx = objectOf("textureMax", root);
        let num = (o, key, fallback) -> JsonCodec.floatOr(key, fallback, o);
        let t = d#stairs#trigger;
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  light = { gain = num(li, "gain", d#light#gain), maxIntensity = num(li, "maxIntensity", d#light#maxIntensity),
                            rangeScale = num(li, "rangeScale", d#light#rangeScale) },
                  stairs = { trigger = { minX = num(st, "minX", t#minX), maxX = num(st, "maxX", t#maxX), minZ = num(st, "minZ", t#minZ),
                                         maxZ = num(st, "maxZ", t#maxZ), minY = num(st, "minY", t#minY), maxY = num(st, "maxY", t#maxY) },
                             startS = num(st, "startS", d#stairs#startS) },
                  sound = { range = num(so, "range", d#sound#range), hitVolume = num(so, "hitVolume", d#sound#hitVolume),
                            stompVolume = num(so, "stompVolume", d#sound#stompVolume), stepVolume = num(so, "stepVolume", d#sound#stepVolume),
                            wallVolume = num(so, "wallVolume", d#sound#wallVolume), wallHF = num(so, "wallHF", d#sound#wallHF),
                            doorHF = num(so, "doorHF", d#sound#doorHF) },
                  textureMax = { baseColor = JsonCodec.intOr("baseColor", d#textureMax#baseColor, tx),
                                 normal = JsonCodec.intOr("normal", d#textureMax#normal, tx) } })
}
