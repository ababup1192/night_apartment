// LightsDoc — night.lights.json（動く光と、外廊下の蛍光灯の並び・点滅・羽虫）の宣言ドキュメント層。
// ベイクした光は動かない。ここにあるのは、毎コマ変わる物（手の灯り・点滅・羽虫）の数と、蛍光灯の置き場所。
// 点滅の形（いつ消え、いつ点くか）の式はコード（Flicker）。
// fail-open — 読めない・壊れているときは defaults() へ落とし、欄が無ければその欄だけ既定。
mod LightsDoc {
    use fge::{Color, DocJson, JsonCodec, UiDoc}
    use Util.Json.Json

    /// 蛍光灯の今の状態（ベイクの時の状態。光が焼き込まれているのは On と Dim だけ）。
    pub enum LampState with Eq, ToString {
        case On
        case Dim
        case Dying
        case Dead
    }

    /// 点滅の形。Steady = 揺れない・Dip = たまにふっと消える・Sputter = 消えたまま、たまに点こうとして瞬く。
    pub enum FlickerKind with Eq, ToString {
        case Steady
        case Dip
        case Sputter
    }

    /// 蛍光灯 1 本: 名前・管の真ん中（m）・状態・点滅の形・点滅の起きやすさ（1 秒あたりの回数の目安）・種。
    pub type alias Lamp = { name = String, x = Float64, y = Float64, z = Float64, state = LampState,
                            flicker = FlickerKind, rate = Float64, seed = Int32 }

    /// 手の灯り（懐中電灯）: 色・強さ・届く距離（m）・円錐の角（度）・縁で暗くなり始める角（度。小さいほど輪の縁がぼける）・
    /// 目からのずれ（前・下・右 m）・影を落とすか・始めから点いているか。
    pub type alias Flashlight = { color = Color, intensity = Float64, range = Float64, coneDeg = Float64, innerConeDeg = Float64,
                                  forward = Float64, down = Float64, right = Float64, shadow = Bool, startOn = Bool }

    /// 点滅の光: 点きかけの管が瞬いた時の動く光（色・強さ・届く距離）と、Dip の管が消えた時に画面を沈める量と届く距離。
    pub type alias Flash = { color = Color, intensity = Float64, range = Float64, tubeGlow = Float64, screenDip = Float64, dipRange = Float64 }

    /// 羽虫: 点いた管 1 本あたりの数・管からの広がり（m）・粒の大きさ（m）・飛ぶ速さ・色・描く距離（m）。
    pub type alias Flies = { perLamp = Int32, spread = Float64, size = Float64, speed = Float64, color = Color, drawRange = Float64 }

    pub type alias Rec = {
        version = Int32,
        flashlight = Flashlight,
        flash = Flash,
        flies = Flies,
        lamps = List[Lamp]
    }
    pub enum Doc(Rec)
    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/night.lights.json"

    def hx(s: String): Color = Color.hex(s) |> Option.getWithDefault(Color.rgb(1.0, 0.0, 1.0))

    /// コード側の既定値（assets/night.lights.json と同じ手触りから出発する。蛍光灯の並びは JSON が正なので、ここは 1 本だけ）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1,
                  flashlight = { color = hx("#ffe9c8"), intensity = 0.8, range = 14.0, coneDeg = 55.0, innerConeDeg = 18.0,
                                 forward = 0.25, down = 0.3, right = 0.18, shadow = false, startOn = true },
                  flash = { color = hx("#d8f0e0"), intensity = 1.6, range = 5.0, tubeGlow = 2.4, screenDip = 0.25, dipRange = 6.0 },
                  flies = { perLamp = 14, spread = 0.7, size = 0.012, speed = 1.0, color = hx("#e8f0d8"), drawRange = 14.0 },
                  lamps = { name = "2-3", x = -11.75, y = 5.636, z = 0.55, state = LampState.Dying,
                            flicker = FlickerKind.Sputter, rate = 0.6, seed = 23 } :: Nil })

    pub def fromJson(text: String): Option[Doc] = DocJson.decodeObject(fromRoot, text)

    pub def load(p: String): Doc \ Fs.FileRead = DocJson.loadOr(fromJson, defaults(), p)

    def objectOf(name: String, root: Map[String, Json]): Map[String, Json] =
        Map.get(name, root) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def colorOr(fallback: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    /// 字 → 状態（知らない字は On）。
    def stateOf(s: String): LampState = match String.toLowerCase(s) {
        case "dim"   => LampState.Dim
        case "dying" => LampState.Dying
        case "dead"  => LampState.Dead
        case _       => LampState.On
    }

    /// 字 → 点滅の形（知らない字は Steady）。
    def flickerOf(s: String): FlickerKind = match String.toLowerCase(s) {
        case "dip"     => FlickerKind.Dip
        case "sputter" => FlickerKind.Sputter
        case _         => FlickerKind.Steady
    }

    /// 1 行の蛍光灯。名前と置き場所の無い行は捨てる（x・y・z のどれかが無いと、どこで光るか決まらない）。
    def lampOf(obj: Map[String, Json]): Option[Lamp] =
        let num = key -> Map.get(key, obj) |> Option.flatMap(JsonCodec.expectFloat);
        forM (
            x <- num("x");
            y <- num("y");
            z <- num("z")
        ) yield { name = JsonCodec.stringOr("name", "", obj), x = x, y = y, z = z,
                  state = stateOf(JsonCodec.stringOr("state", "on", obj)),
                  flicker = flickerOf(JsonCodec.stringOr("flicker", "steady", obj)),
                  rate = JsonCodec.floatOr("rate", 0.3, obj), seed = JsonCodec.intOr("seed", 1, obj) }

    def lampsOr(fallback: List[Lamp], root: Map[String, Json]): List[Lamp] =
        Map.get("lamps", root)
            |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))
            |> Option.map(rows -> rows |> List.filterMap(lampOf))
            |> Option.getWithDefault(fallback)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let fl = objectOf("flashlight", root);
        let fa = objectOf("flash", root);
        let fi = objectOf("flies", root);
        let num = (o, key, fallback) -> JsonCodec.floatOr(key, fallback, o);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  flashlight = { color = colorOr(d#flashlight#color, "color", fl), intensity = num(fl, "intensity", d#flashlight#intensity),
                                 range = num(fl, "range", d#flashlight#range), coneDeg = num(fl, "coneDeg", d#flashlight#coneDeg),
                                 innerConeDeg = num(fl, "innerConeDeg", d#flashlight#innerConeDeg),
                                 forward = num(fl, "forward", d#flashlight#forward), down = num(fl, "down", d#flashlight#down),
                                 right = num(fl, "right", d#flashlight#right), shadow = JsonCodec.boolOr("shadow", d#flashlight#shadow, fl),
                                 startOn = JsonCodec.boolOr("startOn", d#flashlight#startOn, fl) },
                  flash = { color = colorOr(d#flash#color, "color", fa), intensity = num(fa, "intensity", d#flash#intensity),
                            range = num(fa, "range", d#flash#range), tubeGlow = num(fa, "tubeGlow", d#flash#tubeGlow),
                            screenDip = num(fa, "screenDip", d#flash#screenDip), dipRange = num(fa, "dipRange", d#flash#dipRange) },
                  flies = { perLamp = JsonCodec.intOr("perLamp", d#flies#perLamp, fi), spread = num(fi, "spread", d#flies#spread),
                            size = num(fi, "size", d#flies#size), speed = num(fi, "speed", d#flies#speed),
                            color = colorOr(d#flies#color, "color", fi), drawRange = num(fi, "drawRange", d#flies#drawRange) },
                  lamps = lampsOr(d#lamps, root) })
}
