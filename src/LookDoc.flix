// LookDoc — night.look.json（夜の空気と画面の仕上げ）の宣言ドキュメント層。
// ベイクした光の明るさ・自分で光る物の強さ・霧・トーンマップ・ブルーム・ビネット・粒・色調の数だけを持つ。
// 後処理の Pass の並べ方と式はコード（PostView）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod LookDoc {
    use fge::{Color, DocJson, JsonCodec, UiDoc}
    use Util.Json.Json

    pub type alias Rec = {
        version = Int32,
        // ベイクした光に掛ける倍率（書き出しの ×2 と露出 2^0.6 を掛けた値）・自分で光る絵の倍率・
        // ベイクの無い物（金網・ネット）に当てる環境光。
        lightmapIntensity = Float64,
        emissionIntensity = Float64,
        ambient = Color,
        // WhyNot: 地平の色を霧の色にそろえない — 地平の暖かい靄が街明かりの差し色（画風の注文）。遠くの地面の霧との継ぎ目は地平の線に出る。
        // 空: 天頂の色・地平の色（街の明かりが霧に映る暖かい靄）・地平から天頂へ色が寄る曲がり（3D の空。地平より下は霧の色）。
        // 距離の霧（色・かかり始め・かかり切る距離 m）。
        skyColor = Color,
        horizonColor = Color,
        skyCurve = Float64,
        fogColor = Color,
        fogNear = Float64,
        fogFar = Float64,
        // トーンマップ: 露出（stop の数。1 増やすと 2 倍明るく）と白の点。
        exposure = Float64,
        whitePoint = Float64,
        // ブルーム: しきい（HDR の明るさ）・幅・強さ・ぼかしの半径・標本の数・Pass の倍率。
        bloomThreshold = Float64,
        bloomKnee = Float64,
        bloomStrength = Float64,
        bloomRadius = Float64,
        bloomTaps = Int32,
        bloomScale = Float64,
        // 場面の Pass の 1 画素の標本の数（MSAA。手すり・金網・電線の欠けとちらつきを抑える。1 で掛けない）。
        msaaSamples = Int32,
        // 画面の仕上げ: ビネット・フィルムの粒・暗部を寄せる色と割合・底の持ち上げ・彩度。
        vignette = Float64,
        grain = Float64,
        gradeShadow = Color,
        gradeShadowMix = Float64,
        gradeLift = Float64,
        gradeSaturation = Float64
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/night.look.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// コード側の既定値（assets/night.look.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, lightmapIntensity = 2.6, emissionIntensity = 55.0, ambient = hx("#0c0e16"),
                  skyColor = hx("#030516"), horizonColor = hx("#3a2a2e"), skyCurve = 0.25, fogColor = hx("#14151d"), fogNear = 6.0, fogFar = 60.0,
                  exposure = -0.15, whitePoint = 4.0,
                  bloomThreshold = 0.9, bloomKnee = 0.7, bloomStrength = 0.95, bloomRadius = 0.045, bloomTaps = 12, bloomScale = 0.5,
                  msaaSamples = 4,
                  vignette = 0.42, grain = 0.02, gradeShadow = hx("#0a1226"), gradeShadowMix = 0.4, gradeLift = 0.008, gradeSaturation = -0.05 })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def colorOr(fallback: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let f = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        let c = (key, fallback) -> colorOr(fallback, key, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  lightmapIntensity = f("lightmapIntensity", d#lightmapIntensity), emissionIntensity = f("emissionIntensity", d#emissionIntensity),
                  ambient = c("ambient", d#ambient), skyColor = c("skyColor", d#skyColor), horizonColor = c("horizonColor", d#horizonColor),
                  skyCurve = f("skyCurve", d#skyCurve), fogColor = c("fogColor", d#fogColor),
                  fogNear = f("fogNear", d#fogNear), fogFar = f("fogFar", d#fogFar),
                  exposure = f("exposure", d#exposure), whitePoint = f("whitePoint", d#whitePoint),
                  bloomThreshold = f("bloomThreshold", d#bloomThreshold), bloomKnee = f("bloomKnee", d#bloomKnee),
                  bloomStrength = f("bloomStrength", d#bloomStrength), bloomRadius = f("bloomRadius", d#bloomRadius),
                  bloomTaps = JsonCodec.intOr("bloomTaps", d#bloomTaps, root), bloomScale = f("bloomScale", d#bloomScale),
                  msaaSamples = JsonCodec.intOr("msaaSamples", d#msaaSamples, root),
                  vignette = f("vignette", d#vignette), grain = f("grain", d#grain),
                  gradeShadow = c("gradeShadow", d#gradeShadow), gradeShadowMix = f("gradeShadowMix", d#gradeShadowMix),
                  gradeLift = f("gradeLift", d#gradeLift), gradeSaturation = f("gradeSaturation", d#gradeSaturation) })
}
