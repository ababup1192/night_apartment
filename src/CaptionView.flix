// CaptionView — E で調べた物の文言を画面の下に出す（純粋）。
// 下から藍へ沈むグラデーションの面の上に、字を 1 字ずつ出す。字の下に 1 px ずらした藍の影を敷いて場面から浮かせ、
// 出始めと消え際は面ごと薄めて出し入れする。
mod CaptionView {
    use fge::{App, Color, Render, TextDraw, Vec2}

    /// 描くのに要る値: 文言・出してからの秒・出しておく秒・1 秒に出す字の数・色。
    pub type alias In = { text = String, age = Float64, showSeconds = Float64, charsPerSecond = Float64, theme = ThemeDoc.Doc }

    /// グラデーションの面の高さ（design px）・字の大きさ・字の行の真ん中の、画面の下からの高さ。
    def bandHeight(): Float64 = 64.0
    def textSize(): Float64 = 11.0
    def lineFromBottom(): Float64 = 24.0

    /// 出し入れの秒（出始め・消え際）。
    def fadeInSeconds(): Float64 = 0.25
    def fadeOutSeconds(): Float64 = 0.8

    def smooth(x: Float64): Float64 = { let q = Float64.max(0.0, Float64.min(1.0, x)); q * q * (3.0 - 2.0 * q) }

    /// 面と字の濃さ（出始めに濃くなり、消え際に薄れる）。
    def alphaOf(c: In): Float64 = smooth(c#age / fadeInSeconds()) * smooth((c#showSeconds - c#age) / fadeOutSeconds())

    /// 今出ている字（1 秒に charsPerSecond 字ずつ）。
    def shownText(c: In): String =
        let n = Float64.tryToInt32(Float64.floor(Float64.max(0.0, c#age) * Float64.max(1.0, c#charsPerSecond))) |> Option.getWithDefault(0);
        String.takeLeft(n, c#text)

    /// 下から藍へ沈むグラデーションの面（上のふちは透ける）。
    def band(bg: Color, alpha: Float64): Render.PlacedItem =
        let (w, h, top) = (World.width(), World.height(), World.height() - bandHeight());
        let v = (x: Float64, y: Float64, a: Float64) -> { pos = { x = x, y = y }, color = bg, alpha = a * alpha };
        Render.at(Vec2.zero(), Render.gradPolygon(v(0.0, top, 0.0) :: v(w, top, 0.0) :: v(w, h, 0.78) :: v(0.0, h, 0.78) :: Nil, 0))

    /// 文言の面・影・字。
    pub def items(ctx: App.ViewCtx, c: In): List[Render.PlacedItem] =
        let theme = ThemeDoc.rec(c#theme);
        let alpha = alphaOf(c);
        let center = { x = World.width() / 2.0, y = World.height() - lineFromBottom() };
        let line = (color: Color, dx: Float64, z: Int32) ->
            TextDraw.centeredAt({ text = shownText(c), atlas = ctx#atlas, size = textSize(), color = color, z = z,
                                  center = { x = center#x + dx, y = center#y + dx } });
        if (alpha <= 0.0) Nil
        else Render.fadeAll(alpha, band(theme#bg, 1.0) :: line(Color.darken(theme#bg, 0.5), 1.0, 1) :: line(Color.mix(theme#accent, theme#bg, 0.15), 0.0, 2) :: Nil)
}
