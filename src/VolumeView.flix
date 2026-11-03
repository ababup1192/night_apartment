// VolumeView — 画面の右下の小さなスピーカーの印と、押すと上に開く音量の窓（全体・環境音・効果音の 3 本のバー）。純粋。
// マウスを放している間だけ出る（World.showsVolumeIcon）。動画と静止画には出さない（View.inputForCapture）。
// 画風は AGENTS.local.md の夜のアパート: 夜の藍の板に、蛍光灯の緑がかった白で印とバーを灯す。字は出さず、行の頭の小さな絵
// （スピーカー・風・足跡）で何のバーかを見せる。0 にした行は差し色（自販機の赤）の点で、鳴らないことを示す。
mod VolumeView {
    use fge::{Color, RawDraw, Rect2, Render, Vec2, ZStack}
    use ZOrder.Layer

    /// 描くのに要る値: 音量・窓の状態・色・遊びの時計の秒（印の灯りがゆっくり息をする）。
    pub type alias In = { prefs = AudioPrefs.Prefs, menu = AudioPrefs.Menu, theme = ThemeDoc.Doc, t = Float64 }

    // ── 置き場所（design 480×270） ──

    /// 印の真ん中。
    pub def iconCenter(): Vec2.Vec2 = { x = World.width() - 16.0, y = World.height() - 16.0 }

    def iconRect(): Rect2.Rect2 = { position = { x = iconCenter()#x - 11.0, y = iconCenter()#y - 11.0 }, size = { x = 22.0, y = 22.0 } }

    def panelSize(): Vec2.Vec2 = { x = 128.0, y = 70.0 }

    def panelAt(): Vec2.Vec2 = { x = World.width() - 8.0 - panelSize()#x, y = World.height() - 30.0 - panelSize()#y }

    def panelRect(): Rect2.Rect2 = { position = panelAt(), size = panelSize() }

    def rowIndex(c: AudioPrefs.Channel): Int32 = match c {
        case AudioPrefs.Channel.Master   => 0
        case AudioPrefs.Channel.Ambience => 1
        case AudioPrefs.Channel.Effects  => 2
    }

    /// 行の真ん中の高さ。
    def rowY(c: AudioPrefs.Channel): Float64 = panelAt()#y + 15.0 + 20.0 * Int32.toFloat64(rowIndex(c))

    def trackX(): Float64 = panelAt()#x + 30.0

    def trackLength(): Float64 = 86.0

    /// バーを押せる所（行の高さいっぱい・バーの両端の少し外まで）。
    def rowRect(c: AudioPrefs.Channel): Rect2.Rect2 =
        { position = { x = trackX() - 4.0, y = rowY(c) - 8.0 }, size = { x = trackLength() + 8.0, y = 16.0 } }

    /// 行 c のバーの上で、値 v の所（キーの無い所から押す操作と、そのテスト）。
    pub def barPoint(c: AudioPrefs.Channel, v: Float64): Vec2.Vec2 = { x = trackX() + trackLength() * v, y = rowY(c) }

    /// 押した所の値（バーの左端 0・右端 1）。
    pub def valueAt(cursor: Vec2.Vec2): Float64 = Float64.max(0.0, Float64.min(1.0, (cursor#x - trackX()) / trackLength()))

    // ── 押せる物 ──

    /// 印と、開いている時は窓（バー・窓の中・窓の外）の当たりと絵。
    pub def tree(w: In): ZStack.Tree[Layer, World.Press] =
        let icon = ZStack.of(ZStack.leaf(iconItems(w)) :: ZStack.hit(World.Press.VolumeIcon, iconRect()) :: Nil);
        if (not w#menu#open) icon
        else {
            let rows = AudioPrefs.channels() |> List.map(c -> ZStack.hit(World.Press.VolumeBar(c), rowRect(c)));
            let panel = ZStack.of(ZStack.leaf(panelItems(w)) :: ZStack.hit(World.Press.VolumePanel, panelRect()) :: rows);
            ZStack.blocking(Some(World.Press.VolumeOutside), ZStack.of(panel :: icon :: Nil))
        }

    // ── 絵 ──

    def lit(w: In): Color = ThemeDoc.rec(w#theme)#accent

    def night(w: In): Color = ThemeDoc.rec(w#theme)#bg

    /// 差し色（自販機の赤。テーマの Doc に差し色の欄が無いので、ここで決める — 鳴らない行の小さな点にだけ使う）。
    def warning(_w: In): Color = Color.hsv({ h = 4.0, s = 0.78, v = 0.78 })

    def placed(at: Vec2.Vec2, item: Render.Item): Render.PlacedItem = { at = at, item = item }

    /// 角の丸い板（縁を細く灯す）。
    def plate(at: Vec2.Vec2, size: Vec2.Vec2, fill: Color, edge: { color = Color, alpha = Float64 }, z: Int32): Render.PlacedItem =
        placed(at, RawDraw.box(size, fill, z) |> Render.rounded(4.0) |> Render.fade(0.88)
                   |> Render.outlineA({ color = edge#color, alpha = edge#alpha, width = 1.0 }))

    /// スピーカーの形（中心 c・大きさ s 倍）と、音量で増える音の輪（0 なら赤い斜めの線）。
    def speaker(c: Vec2.Vec2, s: Float64, level: Float64, color: Color, mute: Color, z: Int32): List[Render.PlacedItem] =
        let p = (x: Float64, y: Float64) -> { x = c#x + x * s, y = c#y + y * s };
        let body = placed(Vec2.zero(), RawDraw.polygon(p(-6.0, -2.5) :: p(-3.0, -2.5) :: p(-3.0, 2.5) :: p(-6.0, 2.5) :: Nil, color, z));
        let cone = placed(Vec2.zero(), RawDraw.polygon(p(-3.0, -2.5) :: p(1.0, -6.0) :: p(1.0, 6.0) :: p(-3.0, 2.5) :: Nil, color, z));
        let arc = (r: Float64) -> List.range(0, 3) |> List.map(k -> {
            let a0 = -0.9 + 0.6 * Int32.toFloat64(k);
            let a1 = a0 + 0.6;
            RawDraw.lineSeg(p(2.0 + r * Vec2.cos(a0), r * Vec2.sin(a0)), p(2.0 + r * Vec2.cos(a1), r * Vec2.sin(a1)), 1.1 * s, color, z)
        });
        let waves =
            if (level <= 0.0) RawDraw.lineSeg(p(3.0, -4.5), p(8.0, 4.5), 1.3 * s, mute, z + 1) :: Nil
            else if (level < 0.5) arc(4.0)
            else List.append(arc(4.0), arc(7.0));
        body :: cone :: waves

    /// 風（環境音）: 長さの違う 3 本の流れる線（板が半透明なので、板の色を重ねて形を抜く描き方はしない）。
    def wind(c: Vec2.Vec2, color: Color, z: Int32): List[Render.PlacedItem] =
        let line = (x0: Float64, x1: Float64, y: Float64) -> RawDraw.lineSeg({ x = c#x + x0, y = c#y + y }, { x = c#x + x1, y = c#y + y }, 1.1, color, z);
        let curl = RawDraw.lineSeg({ x = c#x + 3.0, y = c#y - 3.5 }, { x = c#x + 4.6, y = c#y - 2.2 }, 1.1, color, z);
        line(-5.0, 3.0, -3.5) :: curl :: line(-3.0, 5.0, 0.0) :: line(-5.5, 1.5, 3.5) :: Nil

    /// 足跡（効果音）: 左右に少しずれた 2 つの足跡（足裏と踵）。
    def footprint(c: Vec2.Vec2, color: Color, z: Int32): List[Render.PlacedItem] =
        let print = (dx: Float64, dy: Float64) ->
            RawDraw.ellipseAt({ x = c#x + dx, y = c#y + dy - 1.2 }, { x = 1.5, y = 2.2 }, color, z)
                :: RawDraw.ellipseAt({ x = c#x + dx - 0.2, y = c#y + dy + 2.2 }, { x = 1.1, y = 1.2 }, color, z) :: Nil;
        List.append(print(-2.4, 1.2), print(2.4, -1.6))

    /// 隅の印: 夜の藍の小さな板・ゆっくり息をする灯り（窓が開いている時は強く）・全体の音量で輪の数が替わるスピーカー。
    def iconItems(w: In): List[Render.PlacedItem] =
        let c = iconCenter();
        let r = iconRect();
        let breath = 0.85 + 0.15 * Vec2.sin(w#t * 1.4);
        let glow = Render.lightAt({ at = c, radius = 18.0, color = lit(w), strength = (if (w#menu#open) 0.28 else 0.12) * breath, z = 0 });
        let board = plate(r#position, r#size, Color.mix(night(w), lit(w), 0.10), { color = lit(w), alpha = if (w#menu#open) 0.45 else 0.22 }, 1);
        let glyph = speaker({ x = c#x - 1.0, y = c#y }, 1.0, w#prefs#master, Color.mix(night(w), lit(w), if (w#menu#open) 0.95 else 0.7), warning(w), 2);
        glow :: board :: glyph

    /// 開いた窓: 下に落ちる翳り（場面から浮かせる）・板・上の縁の淡い明るみ・3 本の行。
    def panelItems(w: In): List[Render.PlacedItem] =
        let at = panelAt();
        let size = panelSize();
        let fill = Color.mix(night(w), lit(w), 0.08);
        let shadow = Render.darkAt({ at = { x = at#x + size#x / 2.0, y = at#y + size#y / 2.0 + 4.0 }, radius = 92.0, strength = 0.45, z = 0 });
        let board = plate(at, size, fill, { color = lit(w), alpha = 0.24 }, 1);
        let sheen = placed({ x = at#x + 3.0, y = at#y + 2.0 },
                           Render.vgrad({ x = size#x - 6.0, y = 14.0 }, { top = Color.mix(fill, lit(w), 0.12), bottom = fill }, 2) |> Render.fade(0.7));
        List.flatten((shadow :: board :: sheen :: Nil) :: (AudioPrefs.channels() |> List.map(rowItems(w, fill))))

    /// 1 本の行: 選んでいる行の淡い帯・頭の絵・溝・灯った部分・つまみ（0 なら赤い点）。
    def rowItems(w: In, fill: Color, c: AudioPrefs.Channel): List[Render.PlacedItem] =
        let y = rowY(c);
        let v = AudioPrefs.get(c, w#prefs);
        let focused = w#menu#focus == c;
        let ink = Color.mix(fill, lit(w), if (focused) 0.95 else 0.6);
        let headAt = { x = panelAt()#x + 15.0, y = y };
        let band = if (focused) placed({ x = panelAt()#x + 4.0, y = y - 8.0 }, RawDraw.box({ x = panelSize()#x - 8.0, y = 16.0 }, lit(w), 3) |> Render.rounded(3.0) |> Render.fade(0.07)) :: Nil
                   else Nil;
        let head = match c {
            case AudioPrefs.Channel.Master   => speaker(headAt, 0.75, v, ink, warning(w), 4)
            case AudioPrefs.Channel.Ambience => wind(headAt, ink, 4)
            case AudioPrefs.Channel.Effects  => footprint(headAt, ink, 4)
        };
        let groove = placed({ x = trackX(), y = y - 1.5 }, RawDraw.box({ x = trackLength(), y = 3.0 }, Color.darken(night(w), 0.3), 4) |> Render.rounded(1.5));
        let filled = if (v <= 0.0) Nil
                     else placed({ x = trackX(), y = y - 1.5 }, RawDraw.box({ x = trackLength() * v, y = 3.0 }, ink, 5) |> Render.rounded(1.5) |> Render.fade(0.85)) :: Nil;
        let knobAt = { x = trackX() + trackLength() * v, y = y };
        let knob =
            if (v <= 0.0) RawDraw.circleAt(knobAt, 2.6, warning(w), 6) :: Nil
            else Render.lightAt({ at = knobAt, radius = 8.0, color = lit(w), strength = if (focused) 0.35 else 0.18, z = 6 })
                     :: RawDraw.circleAt(knobAt, 3.0, Color.mix(fill, lit(w), 1.0), 7) :: Nil;
        List.flatten(band :: head :: (groove :: filled) :: knob :: Nil)
}
