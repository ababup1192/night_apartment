// Res — 描く元の束: Doc と、Doc と舞台から作る物（置く物の元・場面の絵・当たり判定の箱・ドット絵のアトラス）。
// 読むだけで、Doc の読み直しの時だけ替わる。遊びの状態は World が持ち、App の w は Resources.With[Res, World] の組（Main）。
// Res は World を使わない（使う向きは World → Res だけ。lint/rules.flix の module-cycle）。
mod Res {

    use fge::{Mesh3d, PxShade, PxSpriteAtlas, PxSpriteDoc, Texture3d}

    /// 起動時と描き出しが同じ形で読む Doc の束と、読み込んだ舞台（Controls.loadDocs）。
    pub type alias Docs = {
        sample = SampleDoc.Doc,
        keys = KeysDoc.Doc,
        theme = ThemeDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        walk = WalkDoc.Doc,
        look = LookDoc.Doc,
        lights = LightsDoc.Doc,
        sound = SoundDoc.Doc,
        tour = TourDoc.Doc,
        rooms = RoomsDoc.Doc,
        people = PeopleDoc.Doc,
        stage = Stage.Loaded,
        residents = List[People.Person],
        // 起動の時に読んだ、遊ぶ人の音量（saves/audio.json）。
        prefs = AudioPrefs.Prefs
    }

    /// 描く元の束。
    pub type alias Res = {
        sample = SampleDoc.Doc,
        keys = KeysDoc.Doc,
        theme = ThemeDoc.Doc,
        // 仕上げ（shaded）を掛けた後のドット絵と、それを 1 枚にまとめたアトラス・鍵（羽虫の粒が読む）。
        sprites = PxSpriteDoc.Doc,
        atlas = PxSpriteAtlas.Baked,
        atlasKey = String,
        walk = WalkDoc.Doc,
        look = LookDoc.Doc,
        lights = LightsDoc.Doc,
        sound = SoundDoc.Doc,
        tour = TourDoc.Doc,
        rooms = RoomsDoc.Doc,
        people = PeopleDoc.Doc,
        // 起動の時に読んだ、遊ぶ人の音量（World の始まりの値。遊んでいる間に変えた値は World が持つ）。
        prefs = AudioPrefs.Prefs,
        // 読み込んだ舞台（部品・常に効く当たり判定の箱・2 階の部屋）と住人。
        stage = Stage.Loaded,
        residents = List[People.Person],
        // 描き方ごとの置く物の元の束（LookDoc の lightmap の倍率と、LightsDoc の点滅する管の範囲から作る）。
        placed = List[Stage.Group],
        // 場面の絵（全部の部品と住人の絵を 1 枚ずつ）。
        textures = List[Texture3d.Texture3d],
        // 当たり判定の箱と体を重ねて描く形（調べる時の表示。体は足元が原点）。
        colliderMesh = Mesh3d.Mesh3d,
        bodyMesh = Mesh3d.Mesh3d
    }

    /// Doc の束から描く元を組む。
    pub def build(docs: Docs): Res =
        let sprites = shaded(docs#theme, docs#sprites);
        let (baked, key) = bakedOf(docs#theme, sprites);
        { sample = docs#sample, keys = docs#keys, theme = docs#theme, sprites = sprites, atlas = baked, atlasKey = key,
          walk = docs#walk, look = docs#look, lights = docs#lights, sound = docs#sound, tour = docs#tour, rooms = docs#rooms, stage = docs#stage,
          people = docs#people, residents = docs#residents, prefs = docs#prefs,
          placed = placedOf(docs#look, docs#lights, docs#stage), textures = texturesOf(docs#stage, docs#residents),
          colliderMesh = ColliderMesh.boxesMesh(docs#stage#boxes), bodyMesh = ColliderMesh.bodyMesh(Walker.bodyOf(WalkDoc.rec(docs#walk))) }

    /// 点滅する管の、自分で光る絵の上の範囲（管の真ん中から長さの半分・太さの半分）。
    def masksOf(lights: LightsDoc.Doc): List[Stage.LampMask] =
        Flicker.flickering(LightsDoc.rec(lights)#lamps) |> List.map(e -> {
            let (i, l) = e;
            { x = l#x, y = l#y, z = l#z, hx = 0.34, hy = 0.07, hz = 0.08, levelParam = Flicker.levelParam(i),
              glowParam = if (l#flicker == LightsDoc.FlickerKind.Sputter) Some(Flicker.glowParam(i)) else None }
        })

    def placedOf(look: LookDoc.Doc, lights: LightsDoc.Doc, stage: Stage.Loaded): List[Stage.Group] =
        let c = LightsDoc.rec(lights)#flash#color;
        let glow = LightsDoc.rec(lights)#flash#tubeGlow;
        let masks = masksOf(lights);
        stage#parts |> List.flatMap(part ->
            Stage.groupsOf(stage#rooms, part, Stage.placedOf(LookDoc.rec(look)#lightmapIntensity, (c#r * glow, c#g * glow, c#b * glow), masks, part)))

    /// 全部の部品と住人の絵（同じ絵は 1 枚に）。
    def texturesOf(stage: Stage.Loaded, residents: List[People.Person]): List[Texture3d.Texture3d] =
        List.append(stage#parts |> List.flatMap(Stage.texturesOf), residents |> List.flatMap(People.texturesOf))
            |> List.map(t -> (Texture3d.name(t), t)) |> List.toMap |> Map.valuesOf

    /// 置く物の元の束の数（読み込みの幕の裏で 1 コマに 1 つずつ GPU へ上げる）。
    pub def partCount(res: Res): Int32 = List.length(res#placed)

    /// 歩く・扉を回す規則が読む、動かない物の束。
    /// 部屋にいる住人のカプセルの箱は、常に効く箱に足す。
    pub def playEnv(res: Res): PlayStep.Env =
        { boxes = List.append(res#stage#boxes, People.residentBoxes(res#residents |> List.map(p -> p#entry))), rooms = res#stage#rooms, walk = WalkDoc.rec(res#walk), doors = RoomsDoc.rec(res#rooms)#door }

    /// GPU に登録するアトラスの論理名（羽虫のビルボードがこの名前で待ち合わせる）。
    pub def atlasName(): String = "px"

    /// 「中の色 → (明るい色, 暗い色)」の対応。文字は sprite.json の legend に合わせる。
    def shadeRamp(): PxShade.Ramp = Map#{ 'a' => ('A', 'd') }

    /// 読み込んだドット絵に仕上げを掛ける（読み込み直後の 1 回だけ）。
    def shaded(theme: ThemeDoc.Doc, doc: PxSpriteDoc.Doc): PxSpriteDoc.Doc =
        PxShade.shadeDoc(ThemeDoc.rec(theme)#shade, shadeRamp(), doc)

    /// ドット絵を 1 枚のアトラスにまとめ、GPU キャッシュ用の鍵と対で返す（鍵に画素のハッシュを混ぜ、絵を替えたら上げ直させる）。
    def bakedOf(theme: ThemeDoc.Doc, sprites: PxSpriteDoc.Doc): (PxSpriteAtlas.Baked, String) =
        let baked = PxSpriteAtlas.bake(sprites, key -> ThemeDoc.resolver(theme, key));
        let h = baked#pixels |> Vector.foldLeft((acc, px) -> acc * 31 + px, 17);
        (baked, "${atlasName()}:${Int32.toString(baked#side)}:${Int32.toString(h)}")

    // ── Doc の差し替え（保存即反映。Controls.docTable の reload） ──

    pub def withSample(sample: SampleDoc.Doc, res: Res): Res = { sample = sample | res }

    pub def withKeys(keys: KeysDoc.Doc, res: Res): Res = { keys = keys | res }

    pub def withWalk(walk: WalkDoc.Doc, res: Res): Res = { walk = walk, bodyMesh = ColliderMesh.bodyMesh(Walker.bodyOf(WalkDoc.rec(walk))) | res }

    pub def withSound(sound: SoundDoc.Doc, res: Res): Res = { sound = sound | res }

    pub def withTour(tour: TourDoc.Doc, res: Res): Res = { tour = tour | res }

    pub def withRooms(rooms: RoomsDoc.Doc, res: Res): Res = { rooms = rooms | res }

    pub def withPeople(people: PeopleDoc.Doc, res: Res): Res = { people = people | res }

    /// 光の倍率と点滅する管の範囲が置く物の元に入っているので、作り直す。
    pub def withLook(look: LookDoc.Doc, res: Res): Res = { look = look, placed = placedOf(look, res#lights, res#stage) | res }

    pub def withLights(lights: LightsDoc.Doc, res: Res): Res = { lights = lights, placed = placedOf(res#look, lights, res#stage) | res }

    pub def withTheme(theme: ThemeDoc.Doc, sprites: PxSpriteDoc.Doc, res: Res): Res = withShadedSprites(theme, sprites, res)

    pub def withSprites(sprites: PxSpriteDoc.Doc, res: Res): Res = withShadedSprites(res#theme, sprites, res)

    def withShadedSprites(theme: ThemeDoc.Doc, sprites: PxSpriteDoc.Doc, res: Res): Res =
        let doc = shaded(theme, sprites);
        let (baked, key) = bakedOf(theme, doc);
        { theme = theme, sprites = doc, atlas = baked, atlasKey = key | res }
}
