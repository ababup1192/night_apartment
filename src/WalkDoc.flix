// WalkDoc — walk.kind.json（歩く手触りの数値）の宣言ドキュメント層。
// 歩き方の規則（当たり判定・段差・坂）はコード（World・Collider）で、ここは調整する数だけ。
// 長さはメートル・角度は度・速さは 1 秒あたり。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod WalkDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 歩き始める所: 足元の x・z と向き（度。0 が +Z・90 が +X）。
    pub type alias Start = { x = Float64, z = Float64, yaw = Float64 }

    /// 歩ける範囲（敷地の外の道路の端より先へ出ない）。
    pub type alias Bounds = { minX = Float64, maxX = Float64, minZ = Float64, maxZ = Float64 }

    pub type alias Rec = {
        version = Int32,
        // 歩く速さ・走る速さ（m/秒）。
        walkSpeed = Float64,
        runSpeed = Float64,
        // キーで向きを変える速さ（度/秒）・マウスの 1 px で向きを変える角（度）・マウスの上下を逆にするか・見上げ見下ろしの上限（度）。
        turnSpeed = Float64,
        mouseSensitivity = Float64,
        invertY = Bool,
        pitchLimit = Float64,
        // 目の高さ・体の半径・体の高さ・そのまま上がれる段の高さ（m）。
        eyeHeight = Float64,
        radius = Float64,
        height = Float64,
        stepHeight = Float64,
        // 床として乗れる面の傾きの上限（度。超える面は壁。外階段の段板は約 43 度）。
        floorMaxAngleDeg = Float64,
        // 落ちる速さの増え方（m/秒²）と、当たり判定の箱の無い所の地面の高さ（m。側溝・歩道の継ぎ目で落ちない）。
        gravity = Float64,
        groundY = Float64,
        // 歩く時の頭の上下（m）と、1 歩の長さ（m。足音もこの長さごと）。走る時の 1 歩の長さ。
        bobHeight = Float64,
        stride = Float64,
        runStride = Float64,
        // 縦の画角（度）。
        fovY = Float64,
        start = Start,
        bounds = Bounds
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/walk.kind.json"

    /// コード側の既定値（assets/walk.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, walkSpeed = 1.4, runSpeed = 3.2, turnSpeed = 110.0, mouseSensitivity = 0.18, invertY = false, pitchLimit = 75.0,
                  eyeHeight = 1.6, radius = 0.22, height = 1.7, stepHeight = 0.35, floorMaxAngleDeg = 60.0, gravity = 9.8, groundY = -0.02,
                  bobHeight = 0.025, stride = 0.72, runStride = 1.05, fovY = 58.0,
                  start = { x = 1.5, z = 10.2, yaw = 200.0 },
                  bounds = { minX = -26.0, maxX = 12.0, minZ = -8.0, maxZ = 13.5 } })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(name: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(name, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        let s = objectOf("start", root);
        let b = objectOf("bounds", root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  walkSpeed = f("walkSpeed", d#walkSpeed), runSpeed = f("runSpeed", d#runSpeed),
                  turnSpeed = f("turnSpeed", d#turnSpeed), mouseSensitivity = f("mouseSensitivity", d#mouseSensitivity),
                  invertY = JsonCodec.boolOr("invertY", d#invertY, root),
                  pitchLimit = f("pitchLimit", d#pitchLimit), eyeHeight = f("eyeHeight", d#eyeHeight),
                  radius = f("radius", d#radius), height = f("height", d#height), stepHeight = f("stepHeight", d#stepHeight),
                  floorMaxAngleDeg = f("floorMaxAngleDeg", d#floorMaxAngleDeg),
                  gravity = f("gravity", d#gravity), groundY = f("groundY", d#groundY), bobHeight = f("bobHeight", d#bobHeight),
                  stride = f("stride", d#stride), runStride = f("runStride", d#runStride), fovY = f("fovY", d#fovY),
                  start = { x = JsonCodec.floatOr("x", d#start#x, s), z = JsonCodec.floatOr("z", d#start#z, s),
                            yaw = JsonCodec.floatOr("yaw", d#start#yaw, s) },
                  bounds = { minX = JsonCodec.floatOr("minX", d#bounds#minX, b), maxX = JsonCodec.floatOr("maxX", d#bounds#maxX, b),
                             minZ = JsonCodec.floatOr("minZ", d#bounds#minZ, b), maxZ = JsonCodec.floatOr("maxZ", d#bounds#maxZ, b) } })
}
