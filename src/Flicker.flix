// Flicker — 蛍光灯の点滅の形（時刻だけで決まる。純粋）。
//
// 時間を 1 / rate 秒ずつの区切りに分け、区切りごとに「この区切りで瞬くか・いつ・どれだけ続くか」を番号の乱数で決める。
// 瞬いている間は 1 秒に 18 回ほど点いたり消えたりする（蛍光灯のグローの点き損ないの速さ）。
// 同じ時刻なら毎回同じ明るさになる（描き出しと動画が同じ絵になる）。
mod Flicker {
    use fge::Hash01

    /// 今の管の明るさ: level = 自分で光る絵に掛ける倍率（1 = ベイクの時のまま）・flash = 点きかけの管が瞬いて点いた量（0..1）。
    pub type alias Glow = { level = Float64, flash = Float64 }

    def floorInt(x: Float64): Int32 = Float64.tryToInt32(Float64.floor(x)) |> Option.getWithDefault(0)

    /// 時刻 t が、区切りの中の瞬きの最中か（瞬きは区切りの半分ほどで起き、0.15〜0.65 秒続く）。
    def inBurst(t: Float64, rate: Float64, seed: Int32): Bool =
        let span = 1.0 / Float64.max(0.01, rate);
        let slot = floorInt(t / span);
        let happens = Hash01.at(slot, seed) < 0.55;
        let start = Hash01.at(slot, seed + 1) * span * 0.7;
        let length = 0.15 + 0.5 * Hash01.at(slot, seed + 2);
        let local = t - Int32.toFloat64(slot) * span;
        happens and local >= start and local < start + length

    /// 瞬きの最中に今点いているか（1 秒に 18 回ほど点き消えが替わる）。
    def litNow(t: Float64, seed: Int32): Bool = Hash01.at(floorInt(t * 18.0), seed + 7) > 0.45

    /// 管 1 本の今の明るさ。
    pub def glowOf(t: Float64, lamp: LightsDoc.Lamp): Glow = match lamp#flicker {
        case LightsDoc.FlickerKind.Steady => { level = 1.0, flash = 0.0 }
        case LightsDoc.FlickerKind.Dip =>
            let off = inBurst(t, lamp#rate, lamp#seed) and not litNow(t, lamp#seed);
            { level = if (off) 0.06 else 1.0, flash = 0.0 }
        case LightsDoc.FlickerKind.Sputter =>
            let on = inBurst(t, lamp#rate, lamp#seed) and litNow(t, lamp#seed);
            { level = 0.65 + 0.35 * Hash01.at(floorInt(t * 9.0), lamp#seed + 3), flash = if (on) 1.0 else 0.0 }
    }

    /// 管が瞬きの最中か（揺れない管は瞬かない）。
    def isBursting(t: Float64, lamp: LightsDoc.Lamp): Bool =
        lamp#flicker != LightsDoc.FlickerKind.Steady and inBurst(t, lamp#rate, lamp#seed)

    /// 前の秒 t0 から今の秒 t1 の間に瞬きが始まったか（ジジッという音を鳴らす）。
    pub def burstStarted(t0: Float64, t1: Float64, lamp: LightsDoc.Lamp): Bool =
        t1 > t0 and isBursting(t1, lamp) and not isBursting(t0, lamp)

    /// テレビの画面の明るさ（low..1）: 1 秒に rate 回、場面が替わったように明るさが跳び、間はなめらかにつなぐ。
    /// 細かい揺れ（走査線のちらつき）を 1 割ほど重ねる。
    pub def tvLevel(t: Float64, rate: Float64, low: Float64, seed: Int32): Float64 =
        let u = t * Float64.max(0.1, rate);
        let slot = floorInt(u);
        let f = u - Int32.toFloat64(slot);
        let ease = f * f * (3.0 - 2.0 * f);
        let a = Hash01.at(slot, seed);
        let b = Hash01.at(slot + 1, seed);
        let base = a + (b - a) * ease;
        let shimmer = 0.9 + 0.1 * Hash01.at(floorInt(t * 30.0), seed + 5);
        Float64.max(0.0, Float64.min(1.0, (low + (1.0 - low) * base) * shimmer))

    /// 自分で光る絵の Param の名前（管の明るさ・瞬いた光）。点滅しない管は Param を持たない。
    pub def levelParam(i: Int32): String = "lv${Int32.toString(i)}"

    pub def glowParam(i: Int32): String = "lg${Int32.toString(i)}"

    /// 点滅する管（Steady でない物）と、その番号。
    pub def flickering(lamps: List[LightsDoc.Lamp]): List[(Int32, LightsDoc.Lamp)] =
        lamps |> List.zipWithIndex |> List.filter(e -> snd(e)#flicker != LightsDoc.FlickerKind.Steady)
}
