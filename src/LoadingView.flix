// LoadingView — 起動の読み込みの幕（純粋）。夜の外廊下の天井に付いた蛍光灯 1 本が、点こうとして瞬いている。
//
// ── 画面の層（奥から手前へ）──
//   壁     … 打ち放しのコンクリートの壁。上ほど暗い藍へ沈む横の帯と、型枠の継ぎ目の縦の線
//   光だまり … 管の真下の壁を照らす楕円（管が点いている間だけ。緑がかった白）
//   管     … 器具の箱と管。点き損なう間は両端だけ橙に灯る
//   字とバー … 「Loading」と点・細い鉄の枠に緑がかった白の目盛りが左から埋まる
// 灯りは壁の色の段で表し、上へ白を重ねない（画面を白く飛ばさない）。
mod LoadingView {
    use fge::{App, Color, Hash01, Num, RawDraw, Render, TextDraw, Vec2, ZStack}
    use ZOrder.Layer

    /// 描くのに要る値: 時刻・進み（0..1）・幕の濃さ（1 = 覆い切る・0 = 消えた）・文言。
    pub type alias In = { t = Float64, progress = Float64, alpha = Float64, label = String }

    def p(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    def wd(): Float64 = World.width()
    def ht(): Float64 = World.height()

    // 色: 下地 = 打ち放しの灰・主役 = 蛍光灯の緑がかった白・差し色 = 電極の橙。影は夜の藍。
    def concrete(): Color = Color.rgb(0.30, 0.31, 0.32)
    def tube(): Color = Color.rgb(0.86, 0.98, 0.90)
    def ember(): Color = Color.rgb(1.0, 0.55, 0.25)
    def shadow(): Color = Color.rgb(0.03, 0.04, 0.08)

    /// 管の真ん中（design px）。
    def lamp(): Vec2.Vec2 = p(240.0, 62.0)

    /// 幕が画面を隙間なく覆っているか（下の場面を描かなくてよい）。
    pub def covers(w: In): Bool = w#alpha >= 1.0

    /// 管が今点いているか（瞬きは 1 秒に 14 回ほど替わり、点いている時間は進みに連れて長くなる）。
    def lit(w: In): Bool =
        let slot = Float64.tryToInt32(Float64.floor(w#t * 14.0)) |> Option.getWithDefault(0);
        Hash01.at(slot, 5) < 0.25 + 0.6 * w#progress

    pub def tree(ctx: App.ViewCtx, w: In): ZStack.Tree[Layer, World.Press] =
        if (w#alpha <= 0.0) ZStack.leaf(Nil)
        else {
            let all = List.flatten(wall(w) :: fixture(w) :: label(ctx, w) :: bar(w) :: Nil);
            ZStack.leaf(if (w#alpha >= 1.0) all else all |> List.map(Render.overItem(Render.fade(w#alpha))))
        }

    /// 点 q の明るさの段（0 = 暗がり・1 = 管のすぐ下）。管が消えている間は 0.15 倍。段は 6 つに丸める。
    def litAt(w: In, q: Vec2.Vec2): Float64 =
        let d = Vec2.sub(q, lamp());
        let e = Num.sqrt(d#x * d#x / 4.0 + d#y * d#y);
        let raw = Num.clamp(0.0, 1.0, 1.0 - e / 150.0);
        let k = if (lit(w)) 1.0 else 0.15;
        Float64.floor(raw * raw * k * 5.0 + 0.5) / 5.0

    /// 打ち放しの壁: 8 px の横の帯（上ほど藍へ）と、型枠の継ぎ目（60 px ごとの縦の線・帯ごとに少し明るさが揺れる）。
    def wall(w: In): List[Render.PlacedItem] =
        let rows = 34;
        let bands = List.range(0, rows) |> List.flatMap(r -> {
            let y = Int32.toFloat64(r) * 8.0;
            List.range(0, 8) |> List.map(c -> {
                let x = Int32.toFloat64(c) * 60.0;
                let lift = litAt(w, p(x + 30.0, y + 4.0));
                let base = Color.mix(shadow(), concrete(), 0.25 + 0.1 * Hash01.at(r * 13 + c, 2) + 0.05 * Int32.toFloat64(r) / Int32.toFloat64(rows));
                { at = p(x, y), item = RawDraw.box(p(59.0, 8.0), Color.mix(base, Color.mix(concrete(), tube(), 0.3), lift), 0) }
            })
        });
        { at = Vec2.zero(), item = Render.vgrad(p(wd(), ht()), { top = shadow(), bottom = Color.mix(shadow(), concrete(), 0.35) }, 0) } :: bands

    /// 器具の箱と管（点いている間は管全体・消えている間は両端だけ橙）。
    def fixture(w: In): List[Render.PlacedItem] =
        let c = lamp();
        let body = { at = p(c#x - 70.0, c#y - 12.0), item = RawDraw.box(p(140.0, 9.0), Color.rgb(0.55, 0.56, 0.54), 2) };
        let lip = { at = p(c#x - 70.0, c#y - 4.0), item = RawDraw.box(p(140.0, 2.0), Color.rgb(0.25, 0.26, 0.27), 2) };
        let glass = if (lit(w))
                RawDraw.ellipseAt(p(c#x, c#y + 34.0), p(96.0, 30.0), Color.mix(concrete(), tube(), 0.16), 1)
                :: { at = p(c#x - 62.0, c#y - 1.0), item = RawDraw.box(p(124.0, 4.0), tube(), 3) } :: Nil
            else { at = p(c#x - 62.0, c#y - 1.0), item = RawDraw.box(p(124.0, 4.0), Color.rgb(0.22, 0.24, 0.24), 3) }
                :: RawDraw.ellipseAt(p(c#x - 58.0, c#y + 1.0), p(5.0, 2.5), ember(), 4)
                :: RawDraw.ellipseAt(p(c#x + 58.0, c#y + 1.0), p(5.0, 2.5), ember(), 4) :: Nil;
        body :: lip :: glass

    /// 「Loading」と、時刻で 0〜3 個に増える点。字の下に 2 px ずらした影。
    def label(ctx: App.ViewCtx, w: In): List[Render.PlacedItem] =
        let dots = Int32.modulo(Float64.tryToInt32(Float64.floor(w#t / 0.35)) |> Option.getWithDefault(0), 4);
        let text = w#label + String.repeat(dots, ".") + String.repeat(3 - dots, " ");
        let at = (c: Vec2.Vec2, color: Color, z: Int32) ->
            TextDraw.centeredAt({ text = text, atlas = ctx#atlas, size = 16.0, color = color, z = z, center = c });
        at(p(242.0, 200.0), shadow(), 5) :: at(p(240.0, 198.0), Color.mix(tube(), concrete(), 0.25), 6) :: Nil

    /// 細い鉄の枠と、左から埋まる目盛り。
    def bar(w: In): List[Render.PlacedItem] =
        let (x0, y0, width, height) = (170.0, 216.0, 140.0, 8.0);
        let filled = Num.clamp(0.0, 1.0, w#progress) * (width - 4.0);
        { at = p(x0, y0), item = Render.outline(Color.rgb(0.34, 0.35, 0.38), 1.0, RawDraw.box(p(width, height), Color.rgb(0.16, 0.17, 0.2), 7)) }
            :: { at = p(x0 + 2.0, y0 + 2.0), item = RawDraw.box(p(width - 4.0, height - 4.0), shadow(), 8) }
            :: { at = p(x0 + 2.0, y0 + 2.0), item = RawDraw.box(p(filled, height - 4.0), Color.mix(tube(), concrete(), 0.2), 9) }
            :: { at = p(x0 + 2.0, y0 + 2.0), item = RawDraw.box(p(filled, 1.0), tube(), 9) } :: Nil
}
