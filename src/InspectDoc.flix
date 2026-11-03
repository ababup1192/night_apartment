// InspectDoc — inspect.kind.json（E で調べた物に出す文言）の宣言ドキュメント層。
// 当たり判定のノードの名前の頭ごとの文言と、調べられる距離・出しておく秒・字の出る速さだけを持つ。
// どの物を引くか（目の向きのレイ）と出し方はコード（Inspect・CaptionView）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod InspectDoc {
    use fge::{DocJson, JsonCodec, Log}
    use Util.Json.Json

    /// 調べられる物 1 つ: collision.glb の当たり判定のノードの名前の頭（COL_PRP_vending_red など）と、出す文言。
    pub type alias Thing = { prefix = String, text = String }

    pub type alias Rec = {
        version = Int32,
        // 目から何 m までの物を調べられるか・文言を出しておく秒・1 秒に出す字の数。
        reach = Float64,
        showSeconds = Float64,
        charsPerSecond = Float64,
        // 名前の頭ごとの文言（並びは問わない。textOf が一番長く合う頭を選ぶ）。
        things = List[Thing]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/inspect.kind.json"

    /// コード側の既定値（assets/inspect.kind.json の数と同じ。文言は空 — 調べても何も出ない）。
    pub def defaults(): Doc = Doc.Doc({ version = 1, reach = 2.2, showSeconds = 4.0, charsPerSecond = 40.0, things = Nil })

    /// 名前 name のノードに出す文言: 頭が name そのものか、name が「頭 + _」で始まる物のうち、一番長い頭の物（どれにも合わなければ None）。
    /// WhyNot: 素の startsWith にしない — COL_PRP_pot が後から足した COL_PRP_pothos にも合う。並びで勝ち負けを決めない — Studio で行を並べ替えると文言が入れ替わる。
    pub def textOf(r: Rec, name: String): Option[String] =
        r#things
            |> List.filter(t -> isMatch(t#prefix, name))
            |> List.maximumBy((a, b) -> Order.compare(String.length(a#prefix), String.length(b#prefix)))
            |> Option.map(t -> t#text)

    /// 名前 name が頭 prefix に合うか（name が prefix そのものか、「prefix_」で始まる）。
    def isMatch(prefix: String, name: String): Bool =
        prefix != "" and (name == prefix or String.startsWith(prefix = "${prefix}_", name))

    /// どの名前 names にも合わない頭（書き間違えた頭は文言が出ない）。
    pub def unmatchedPrefixes(r: Rec, names: List[String]): List[String] =
        r#things |> List.filter(t -> not List.exists(isMatch(t#prefix), names)) |> List.map(t -> t#prefix)

    def thingOf(obj: Map[String, Json]): Option[Thing] =
        forM (
            prefix <- Map.get("prefix", obj) |> Option.flatMap(JsonCodec.expectString);
            text <- Map.get("text", obj) |> Option.flatMap(JsonCodec.expectString)
        ) yield { prefix = prefix, text = text }

    def thingsOr(fallback: List[Thing], root: Map[String, Json]): List[Thing] =
        Map.get("things", root)
            |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))
            |> Option.map(rows -> rows |> List.filterMap(row -> match thingOf(row) {
                case Some(t) => Some(t)
                case None    => Log.fellBackThen("inspect", "things の行", "その行を飛ばす", "prefix か text が字でない", None)
            }))
            |> Option.getWithDefault(fallback)

    def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  reach = JsonCodec.floatOr("reach", d#reach, root),
                  showSeconds = JsonCodec.floatOr("showSeconds", d#showSeconds, root),
                  charsPerSecond = JsonCodec.floatOr("charsPerSecond", d#charsPerSecond, root),
                  things = thingsOr(d#things, root) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)
}
