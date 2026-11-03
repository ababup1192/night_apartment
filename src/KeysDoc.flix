// KeysDoc — player.keys.json（キー割り当て）の宣言ドキュメント層。
// 「どのキーがどの操作か」だけを外に出す — 歩き方はコード（Controls / Walker）のまま。
// 1 つの操作に複数キーを並べられる。fail-open — 読めない・壊れているときは defaults() へ落とす。
// 操作の欄が空・全部知らない名前のときも、その操作だけ既定へ落とす（書き間違いで操作不能を作らない）。
mod KeysDoc {
    use fge::{DocJson, InputMap, JsonCodec}
    use fge::GameEngine.Key
    use Util.Json.Json

    /// 操作ごとのキーの列。
    pub type alias Rec = {
        version = Int32,
        forward = List[Key],      // 前へ歩く
        back = List[Key],         // 後ろへ歩く
        left = List[Key],         // 左へ横歩き
        right = List[Key],        // 右へ横歩き
        turnLeft = List[Key],     // 左を向く
        turnRight = List[Key],    // 右を向く
        lookUp = List[Key],       // 見上げる
        lookDown = List[Key],     // 見下ろす
        sprint = List[Key],       // 押している間は走る
        light = List[Key],        // 手の灯りを点け消し
        door = List[Key],         // 見ている玄関の扉を開け閉め・見ている物を調べる
        colliders = List[Key],    // 当たり判定の箱を重ねて描く（調べる時）
        volume = List[Key]        // 音量の窓を開け閉め（マウスを放している時だけ）
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/player.keys.json"

    /// コード側の既定（assets/player.keys.json と同じ割り当てから出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  forward = Key.W :: Key.Up :: Nil, back = Key.S :: Key.Down :: Nil,
                  left = Key.A :: Nil, right = Key.D :: Nil,
                  turnLeft = Key.Left :: Nil, turnRight = Key.Right :: Nil,
                  lookUp = Key.R :: Nil, lookDown = Key.V :: Nil,
                  sprint = Key.LeftShift :: Nil, light = Key.F :: Nil, door = Key.E :: Nil, colliders = Key.C :: Nil,
                  volume = Key.M :: Nil })

    def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let k = (field, fallback) -> keysOr(field, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  forward = k("forward", d#forward), back = k("back", d#back), left = k("left", d#left), right = k("right", d#right),
                  turnLeft = k("turnLeft", d#turnLeft), turnRight = k("turnRight", d#turnRight),
                  lookUp = k("lookUp", d#lookUp), lookDown = k("lookDown", d#lookDown),
                  sprint = k("run", d#sprint), light = k("light", d#light), door = k("door", d#door), colliders = k("colliders", d#colliders),
                  volume = k("volume", d#volume) })

    /// 欄の文字列列 → キーの列。知らない名前はその 1 個だけ捨て、列ごと空になる形だけ既定へ落とす。
    def keysOr(field: String, fallback: List[Key], root: Map[String, Json]): List[Key] =
        Map.get(field, root)
            |> Option.flatMap(element -> JsonCodec.decodeList(JsonCodec.expectString, element))
            |> Option.map(InputMap.keysOf)
            |> Option.flatMap(keys -> if (List.isEmpty(keys)) None else Some(keys))
            |> Option.getWithDefault(fallback)
}
