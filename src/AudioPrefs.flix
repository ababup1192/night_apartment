// AudioPrefs — 遊ぶ人が決める音量（全体・環境音・効果音）と、それを変える小さな窓の状態（純粋）。
// 値は saves/audio.json に残し、次の起動で読み戻す（Doc ではない — 作り手が調整する値ではなく、遊ぶ人の好み）。
// 書くのは Main の App.addOutput（値が替わった実機のフレームの後で 1 回）。音量はバス（Sounds.mixerOf）の倍率で効く。
// fail-open — 読めない・壊れているときは既定（全部 1）で続ける。
mod AudioPrefs {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 音量の種類（窓の上から順）。
    pub enum Channel with Eq, Order, ToString {
        case Master
        case Ambience
        case Effects
    }

    /// 音量（0..1。0 で鳴らない）。
    pub type alias Prefs = { master = Float64, ambience = Float64, effects = Float64 }

    /// 音量の窓: 開いているか・キーで動かす行。
    pub type alias Menu = { open = Bool, focus = Channel }

    pub def defaults(): Prefs = { master = 1.0, ambience = 1.0, effects = 1.0 }

    pub def closedMenu(): Menu = { open = false, focus = Channel.Master }

    pub def channels(): List[Channel] = Channel.Master :: Channel.Ambience :: Channel.Effects :: Nil

    /// キーの 1 押しで動く量。
    pub def stepSize(): Float64 = 0.1

    def clamp01(v: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, v))

    pub def get(c: Channel, p: Prefs): Float64 = match c {
        case Channel.Master   => p#master
        case Channel.Ambience => p#ambience
        case Channel.Effects  => p#effects
    }

    /// 音量を v に（0..1 に収め、0.01 刻みに丸める — 保存した字が細かい端数で毎フレーム揺れない）。
    pub def set(c: Channel, v: Float64, p: Prefs): Prefs =
        let q = Float64.round(clamp01(v) * 100.0) / 100.0;
        match c {
            case Channel.Master   => { master = q | p }
            case Channel.Ambience => { ambience = q | p }
            case Channel.Effects  => { effects = q | p }
        }

    /// 音量を d だけ動かす。
    pub def nudge(c: Channel, d: Float64, p: Prefs): Prefs = set(c, get(c, p) + d, p)

    /// 実際に掛かる倍率（全体 × 種類）。
    pub def ambienceGain(p: Prefs): Float64 = p#master * p#ambience

    pub def effectsGain(p: Prefs): Float64 = p#master * p#effects

    /// 窓の行を上下に動かす（端で止まる）。
    pub def moveFocus(d: Int32, m: Menu): Menu =
        let all = channels();
        let at = all |> List.zipWithIndex |> List.find(e -> snd(e) == m#focus) |> Option.map(fst) |> Option.getWithDefault(0);
        let next = Int32.max(0, Int32.min(List.length(all) - 1, at + d));
        { focus = List.nth(next, all) |> Option.getWithDefault(m#focus) | m }

    // ── 保存 ──

    pub def path(): String = "saves/audio.json"

    def num(v: Float64): String = Float64.toString(Float64.round(v * 100.0) / 100.0)

    /// 保存する字（App.addOutput の鍵にもなる）。
    pub def toText(p: Prefs): String =
        "{ \"version\": 1, \"master\": ${num(p#master)}, \"ambience\": ${num(p#ambience)}, \"effects\": ${num(p#effects)} }\n"

    pub def fromJson(text: String): Option[Prefs] = DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Prefs =
        let d = defaults();
        let f = (key, fallback) -> clamp01(JsonCodec.floatOr(key, fallback, root));
        { master = f("master", d#master), ambience = f("ambience", d#ambience), effects = f("effects", d#effects) }

    /// 保存した音量（無い・壊れていれば既定）。
    pub def load(p: String): Prefs \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    /// 音量を書く（書けなくても遊びは止めない。次の起動が既定に戻るだけ）。
    pub def save(p: Prefs): Unit \ Fs.FileWrite =
        discard Fs.FileWrite.write({ str = toText(p) }, path())
}
