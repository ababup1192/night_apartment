// Pilot — 決めた道筋（TourDoc）を歩く自動の操縦（純粋）。
//
// 次の点へ向きを変えながら歩き、着いたら決めた向き・見上げる角へゆっくり向いて待ち、次の点へ。
// 点に press があれば、決めた向きを向き終えた所で E を 1 回押す（玄関の扉を開け閉めする）。light があれば着いた所で手の灯りをそうする。
// 出すのはキーと同じ操作（PlayStep.Act）なので、当たり判定・扉・足音は手で歩く時と同じ規則を通る。
mod Pilot {
    use fge::{Clock, Num}

    /// 何番目の点へ向かっているか・その点で待った秒・着いたか・その点へ向かい始めてからの秒（挟まって着けない時に諦める）・
    /// その点で E を押したか・挟まって諦めた点の数。
    pub type alias State = { index = Int32, waited = Float64, arrived = Bool, heading = Float64, pressed = Bool, missed = Int32 }

    pub def start(): State = startAt(0)

    /// index 番目の点へ向かい始める状態。
    def startAt(index: Int32): State = { index = index, waited = 0.0, arrived = false, heading = 0.0, pressed = false, missed = 0 }

    /// 次の点へ向かい始める状態（諦めた点の数は持ち越す）。
    def nextOf(s: State): State = { missed = s#missed | startAt(s#index + 1) }

    /// 挟まって着けずに諦めた点の数。
    pub def missedOf(s: State): Int32 = s#missed

    /// 名前の点の次の点から歩き始める状態（その点に立っている所から続ける。名前が無ければ None）。
    pub def startAfter(tour: TourDoc.Rec, name: String): Option[State] =
        tour#points |> List.zipWithIndex |> List.find(e -> snd(e)#name == name) |> Option.map(e -> startAt(fst(e) + 1))

    /// 向かっている点の名前（歩き終えたら空）。
    pub def pointName(tour: TourDoc.Rec, s: State): String =
        List.nth(s#index, tour#points) |> Option.map(p -> p#name) |> Option.getWithDefault("")

    /// E を押す点で、決めた向きを向き終えるのを待つ秒の上限（向けない時は押さずに次へ）。
    def pressGraceSeconds(): Float64 = 3.0

    /// 1 つの点へ向かう秒の上限（挟まって着けない時は、次の点へ進む）。
    def giveUpSeconds(): Float64 = 20.0

    /// 道筋を歩き終えたか。
    pub def isDone(tour: TourDoc.Rec, s: State): Bool = s#index >= List.length(tour#points)

    def deg(r: Float64): Float64 = r * 180.0 / Num.pi()

    /// -180..180 へ折り返した角の差（度）。
    def wrapDeg(a: Float64): Float64 = Num.wrapTo(360.0, a + 180.0) - 180.0

    /// 目標の角へ、なめらかに寄せる 1 コマの角（度）。速さの上限は rate（度/秒）。
    def ease(diff: Float64, rate: Float64, dt: Float64): Float64 =
        let want = diff * Num.clamp(0.0, 1.0, 5.0 * dt);
        Num.clamp(0.0 - rate * dt, rate * dt, want)

    def walking(d: Walker.Drive): PlayStep.Act = { drive = d | PlayStep.idle() }

    /// このコマの操作と、次の状態（秒は遊びの時計の今のコマの分）。
    pub def drive(tour: TourDoc.Rec, w: Walker.Walker, clock: Clock.Clock[PlayClock.Play], s: State): (PlayStep.Act, State) =
        driveSeconds(tour, w, Clock.dtOf(clock), s)

    def driveSeconds(tour: TourDoc.Rec, w: Walker.Walker, dt: Float64, s: State): (PlayStep.Act, State) =
        match List.nth(s#index, tour#points) {
            case None => (walking({ lookDeg = ease(0.0 - deg(w#pitch), tour#turnRate, dt) | Walker.idle() }), s)
            case Some(p) =>
                let (dx, dz) = (p#x - w#x, p#z - w#z);
                let dist = Num.sqrt(dx * dx + dz * dz);
                if (not s#arrived and dist > tour#arriveRadius and s#heading > giveUpSeconds())
                    (PlayStep.idle(), { missed = s#missed + 1 | nextOf(s) })
                else if (not s#arrived and dist > tour#arriveRadius) {
                    let diff = wrapDeg(deg(Num.atan2(dx, dz)) - deg(w#yaw));
                    let facing = if (Float64.abs(diff) < 50.0) 1.0 else 0.25;
                    let slow = Num.clamp(0.4, 1.0, dist / 0.9);
                    (walking({ forward = facing * slow, turnDeg = ease(diff, tour#turnRate, dt),
                               lookDeg = ease(0.0 - deg(w#pitch), tour#turnRate * 0.5, dt), sprint = p#sprint | Walker.idle() }), { heading = s#heading + dt | s })
                }
                else waitAt(tour, p, w, dt, s)
        }

    /// 点に着いて待つ 1 コマ: 決めた向きへ寄せ、向き終えたら E を 1 回押し、待ち終えたら次の点へ。
    /// E を押す点では、待つ秒を押した時から数える（扉が回り切る前に歩き出して、回る扉に挟まらない）。
    def waitAt(tour: TourDoc.Rec, p: TourDoc.Point, w: Walker.Walker, dt: Float64, s: State): (PlayStep.Act, State) =
        let turn = p#lookYaw |> Option.map(y -> ease(wrapDeg(y - deg(w#yaw)), tour#turnRate * 0.7, dt)) |> Option.getWithDefault(0.0);
        let look = ease(p#lookPitch - deg(w#pitch), tour#turnRate * 0.5, dt);
        let aligned = p#lookYaw |> Option.forAll(y -> Float64.abs(wrapDeg(y - deg(w#yaw))) < 4.0);
        let press = p#press and not s#pressed and aligned;
        let pressed = s#pressed or press;
        let waited = if (press) 0.0 else s#waited + dt;
        let done = if (p#press and not pressed) waited >= p#wait + pressGraceSeconds() else waited >= p#wait;
        let next = if (done) nextOf(s) else { waited = waited, arrived = true, pressed = pressed | s };
        ({ drive = { turnDeg = turn, lookDeg = look | Walker.idle() }, press = press, light = if (s#arrived) PlayStep.LightCue.Keep else p#light }, next)

    /// 道筋を状態 s0 から n コマ歩かせた体の列（1 コマ目の後から。歩き終えたらそこで止める）と最後の状態。
    pub def trace(env: PlayStep.Env, tour: TourDoc.Rec, clock: Clock.Clock[PlayClock.Play], n: Int32, s0: State, b: PlayStep.Body): (List[PlayStep.Body], State) =
        let (_, out, last) = List.range(0, n) |> List.foldLeft((acc, _) -> {
            let (body, bodies, s) = acc;
            if (isDone(tour, s)) acc
            else {
                let (act, next) = drive(tour, body#walker, clock, s);
                let moved = PlayStep.step(env, act, clock, body);
                (moved, moved :: bodies, next)
            }
        }, (b, Nil, s0));
        (List.reverse(out), last)

    /// 道筋を状態 s0 から n コマ歩かせた後の体と状態（同じ時計の刻みで。テストが道筋を歩き終えられるかを見る）。
    pub def simulate(env: PlayStep.Env, tour: TourDoc.Rec, clock: Clock.Clock[PlayClock.Play], n: Int32, s0: State, b: PlayStep.Body): (PlayStep.Body, State) =
        List.range(0, n) |> List.foldLeft((acc, _) -> {
            let (body, s) = acc;
            if (isDone(tour, s)) acc
            else {
                let (act, next) = drive(tour, body#walker, clock, s);
                (PlayStep.step(env, act, clock, body), next)
            }
        }, (b, s0))
}
