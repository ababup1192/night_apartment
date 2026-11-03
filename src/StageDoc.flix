// StageDoc — stage.kind.json（舞台の読み込み方）の宣言ドキュメント層。
// 書き出しのフォルダと、読む時に絵を縮める上限（長い辺の px）だけを持つ。起動の時に 1 回だけ読む
// （glb と絵を読み直すのは IO が要り、保存即反映の読み直しは Fs.FileRead だけの口だから）。
// fail-open — 読めない・壊れているときは defaults() へ落とす。
mod StageDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // 書き出しのフォルダ（manifest.json・部品の glb・lightmaps/・textures/・collision.glb がある所）。
        dir = String,
        // 材質の絵・法線マップ・lightmap・自分で光る絵の長い辺の上限（px）。
        baseColorMax = Int32,
        normalMax = Int32,
        lightmapMax = Int32,
        emissiveMax = Int32,
        // 読まない部品の名前（重さを測る時に 1 つずつ外す）。
        skip = List[String]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/stage.kind.json"

    /// コード側の既定値（assets/stage.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, dir = "assets/apartment", baseColorMax = 8192, normalMax = 8192, lightmapMax = 8192, emissiveMax = 8192, skip = Nil })

    def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let i = (key, fallback) -> JsonCodec.intOr(key, fallback, root);
        Doc.Doc({ version = i("version", d#version), dir = JsonCodec.stringOr("dir", d#dir, root),
                  baseColorMax = i("baseColorMax", d#baseColorMax), normalMax = i("normalMax", d#normalMax),
                  lightmapMax = i("lightmapMax", d#lightmapMax), emissiveMax = i("emissiveMax", d#emissiveMax),
                  skip = Map.get("skip", root)
                      |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectString, json))
                      |> Option.getWithDefault(d#skip) })
}
