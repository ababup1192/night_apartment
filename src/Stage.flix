// Stage — 舞台（Blender の書き出し）を読んで、Scene3d に置く物へ組む。
//
// 書き出しのフォルダの manifest.json が部品の一覧: 部品ごとの glb（TEXCOORD_0 = 材質の絵・TEXCOORD_1 = lightmap）・
// lightmap の PNG（linear = 2 × sRGB の逆。倍率は LookDoc の lightmapIntensity）・自分で光る絵（/40 で書いてある）・
// lightmap の UV の島の間（mip のレベルの上限を決める）。当たり判定は collision.glb の箱。
// 読み込みは「ファイルを順に読む → 絵と形を並列に解く」の 2 段で、起動画面のバーを進める（LoadProgress）。
// 2 階の部屋（manifest の rooms）は Rooms が読み、部屋の部品はその部屋を描く時だけ・扉の部品は扉ごとに分けて扉の角で回して置く（Group）。
mod Stage {
    use fge::{
        CollisionShape3d, DocJson, Gltf, ImageData, JsonCodec, LoadProgress, Log, Mat4, Mesh3d,
        Model3d, Ray3d, Scene3d, ShaderDoc, Texture3d
    }
    use fge::ShaderDoc.{BinOp, Field, Shade}
    use Util.Json.Json

    /// manifest.json の部品 1 つ（読む前）。gapUv = lightmap の島の間（UV の割合）。
    pub type alias Entry = { name = String, glb = String, lightmap = Option[String], emissive = Option[String], gapUv = Float64, alpha = Bool }

    /// 読み込んだ部品。gapPx = 読んだ lightmap の絵の上での島の間（px）。
    pub type alias Part = { name = String, model = Model3d.Model3d, lightmap = Option[Texture3d.Texture3d],
                            emissive = Option[Texture3d.Texture3d], gapPx = Int32, alpha = Bool }

    /// 読み込んだ舞台: 部品・常に効く当たり判定の箱（扉の板を除く）・2 階の部屋・E で調べる時の当たり判定のノードの的（扉の板を除く）。
    pub type alias Loaded = { parts = List[Part], boxes = List[CollisionShape3d.Box3d], rooms = List[Rooms.Room],
                              things = List[(Inspect.Key, Ray3d.RayTarget)] }

    /// 読む前のバイト（ファイルを読む段の結果）。
    type alias Raw = { entry = Entry, glb = Result[String, Vector[Int8]], lightmap = Option[Vector[Int8]], emissive = Option[Vector[Int8]] }

    // ── manifest.json ──

    /// manifest.json の字から部品の一覧（名前の順）。読めない時は Err。glb の無い行は捨てる。
    pub def entriesOf(text: String): Result[String, List[Entry]] =
        DocJson.parse(text)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(root -> Map.get("parts", root))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(parts -> Map.toList(parts) |> List.filterMap(e -> {
                let (name, json) = e;
                JsonCodec.expectObject(json) |> Option.flatMap(entryOf(name))
            }))
            |> Option.toOk("manifest.json を読めない（parts が無い）")

    def entryOf(name: String, obj: Map[String, Json]): Option[Entry] =
        let str = key -> Map.get(key, obj) |> Option.flatMap(JsonCodec.expectString);
        let textures = Map.get("textures", obj) |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectString, json)) |> Option.getWithDefault(Nil);
        let margin = Map.get("uv_margin", obj) |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(m -> JsonCodec.floatOr("lightmap", 0.0035, m)) |> Option.getWithDefault(0.0035);
        str("glb") |> Option.map(glb ->
            { name = name, glb = glb, lightmap = str("lightmap_png"),
              emissive = List.find(String.endsWith(suffix = "_emit.png"), textures),
              gapUv = margin, alpha = Map.memberOf("alpha", obj) })

    // ── 読み込み ──

    /// 書き出しのフォルダから部品と当たり判定を全部読む。読めない部品は理由を 1 行出して置かない。
    pub def load(doc: StageDoc.Doc): Loaded \ Fs.FileRead + IO + LoadProgress =
        let d = StageDoc.rec(doc);
        let dec = LoadProgress.imageDecoder();
        let path = (rel: String) -> "${d#dir}/${rel}";
        LoadProgress.report("reading manifest...", 0, 0);
        let manifest = Fs.FileRead.read(path("manifest.json")) |> Result.mapErr(e -> "${e}");
        let entries = match manifest |> Result.flatMap(entriesOf) {
            case Ok(es)   => es |> List.filter(e -> not List.memberOf(e#name, d#skip))
            case Err(why) => Log.warnThen("[stage] ${path("manifest.json")}: ${why}", Nil)
        };
        let optBytes = (rel: Option[String]) -> rel |> Option.flatMap(r -> Fs.FileRead.readBytes(path(r)) |> Result.toOption);
        let raws = entries |> LoadProgress.mapWithProgress("reading stage...", e ->
            { entry = e, glb = Fs.FileRead.readBytes(path(e#glb)) |> Result.mapErr(err -> "${path(e#glb)}: 読めない（${err}）"),
              lightmap = optBytes(e#lightmap), emissive = optBytes(e#emissive) });
        let collision = Fs.FileRead.readBytes(path("collision.glb")) |> Result.mapErr(err -> "${err}");
        let parts = raws
            |> LoadProgress.parMapWithProgress("decoding stage...", decodePart(dec, d))
            |> List.filterMap(r -> match r {
                case Ok(p)    => Some(p)
                case Err(why) => Log.warnThen("[stage] ${why}", None)
            });
        LoadProgress.report("reading collision...", 0, 0);
        let (rooms, statics) = match collision |> Result.flatMap(Gltf.fromGlb) {
            case Ok(model) => Rooms.layoutOf(Result.getWithDefault("", manifest), model)
            case Err(why)  => Log.warnThen("[stage] collision.glb: ${why}", (Nil, Nil))
        };
        let checked = rooms |> List.map(r -> if (hasDoorShape(parts, r)) r else Log.warnThen("[stage] ${r#id}: 扉の形のノード（${r#door#node}）が部品 ${r#doorPart} に無い（扉が回らない）", r));
        { parts = parts, boxes = Collider.boxesOfNodes(statics), rooms = checked, things = Inspect.nodeTargets(statics) }

    /// 部屋 r の扉の部品に、扉の形のノード（manifest の door.node）があるか（扉の部品を読めなかった時は真 — 部品の知らせが先に出ている）。
    def hasDoorShape(parts: List[Part], r: Rooms.Room): Bool =
        match List.find(p -> p#name == r#doorPart, parts) {
            case Some(p) => Option.nonEmpty(Model3d.findNode(r#door#node, p#model))
            case None    => true
        }

    /// 1 つの部品のバイトを形と絵へ解く（並列に回す。IO だけ）。
    def decodePart(dec: ImageData.ImageDecoder, d: StageDoc.Rec, raw: Raw): Result[String, Part] \ IO =
        let limits = { baseColor = d#baseColorMax, normal = d#normalMax };
        let picture = (bytes: Option[Vector[Int8]], maxSide: Int32) ->
            bytes |> Option.flatMap(b -> Texture3d.decodeUsing(dec, b) |> Result.toOption) |> Option.map(Texture3d.limitSize(maxSide));
        let e = raw#entry;
        raw#glb |> Result.flatMap(bytes -> Gltf.fromGlbTexturedUsing(dec, limits, bytes) |> Result.mapErr(why -> "${e#glb}: ${why}"))
            |> Result.map(model -> {
                let lightmap = picture(raw#lightmap, d#lightmapMax);
                let width = lightmap |> Option.map(Texture3d.width) |> Option.getWithDefault(0);
                { name = e#name, model = model, lightmap = lightmap, emissive = picture(raw#emissive, d#emissiveMax),
                  gapPx = Int32.max(1, Float64.tryToInt32(Float64.round(e#gapUv * Int32.toFloat64(width))) |> Option.getWithDefault(1)),
                  alpha = e#alpha }
            })

    // ── 場面に置く物 ──

    /// 点滅する蛍光灯 1 本ぶんの、自分で光る絵の上の範囲（管の真ん中と半分の大きさ）と、その管の明るさを渡す Param の名前。
    /// glowParam = 点きかけの管が瞬いた時に、管の形に足す光の Param の名前（None なら足さない）。
    pub type alias LampMask = { x = Float64, y = Float64, z = Float64, hx = Float64, hy = Float64, hz = Float64,
                                levelParam = String, glowParam = Option[String] }

    /// 場面に置く物の元: 形・材質（自分で光る絵込み）・lightmap・形の出たノードの名前。毎コマは材質の Param だけを替えて置く（instanceOf）。
    pub type alias Placed = { mesh = Mesh3d.Mesh3d, material = Scene3d.Material3d, lightmap = Option[Scene3d.Lightmap], emissive = Bool,
                              node = Option[String] }

    /// 部品の形を置く物の元にする。lightmap の倍率は intensity・自分で光る絵は emission（点滅の範囲 masks を掛け、線形の倍率 emissionIntensity で光らせる）。
    pub def placedOf(intensity: Float64, emissionIntensity: Float64, glowColor: (Float64, Float64, Float64), masks: List[LampMask], part: Part): List[Placed] =
        let emission = part#emissive |> Option.map(t -> emissionOf(Texture3d.name(t), glowColor, masks));
        let names = part#model#nodes |> List.map(n -> n#name) |> List.toVector;
        part#model#parts |> List.map(mp -> {
            let base = materialOf(part, mp);
            let lit = emission |> Option.map(s -> base |> Scene3d.withEmission(s) |> Scene3d.withEmissionIntensity(emissionIntensity)) |> Option.getWithDefault(base);
            { mesh = mp#mesh, material = lit,
              lightmap = part#lightmap |> Option.map(lm -> { intensity = intensity, maxLevels = Scene3d.lightmapLevelsForGap(part#gapPx) | Scene3d.lightmap(Texture3d.name(lm)) }),
              emissive = Option.nonEmpty(emission), node = mp#node |> Option.flatMap(i -> Vector.nth(i, names)) }
        })

    /// 形 1 つの材質: glb の材質（無ければ engine の見本）。抜きのある部品（manifest の alpha）は、glb で半透明（BLEND）の網は
    /// 裏から見ても見えるよう両面にし、ほかは α の半分で抜く。
    /// WhyNot: 金網を半透明から抜きへ戻さない — 網の目の縁を α で溶かすのが人の注文。MSAA の α の覆い（cutout だけに効く）は効かず、
    /// 深度を書かないので網どうしが重なる構図では前後が崩れうる（今の 2 枚は離れて置かれている）。
    def materialOf(part: Part, mp: Model3d.ModelPart): Scene3d.Material3d =
        let base = mp#material |> Option.getWithDefault(Scene3d.material(ShaderDoc.demoSurface()));
        let blended = Scene3d.materialFieldsOf(base)#blend;
        if (not part#alpha) base
        else if (blended) Scene3d.withDoubleSided(true, base)
        else Scene3d.withCutout(true, base)

    /// 置く物の元の束の描き方。Always = いつも描く・Room = その部屋を描く時だけ・Door = その部屋の扉の角に回して描く。
    pub enum Role with Eq, ToString {
        case Always
        case Room(String)
        case Door(String)
    }

    /// 描き方の同じ置く物の元の束。
    pub type alias Group = { role = Role, items = List[Placed] }

    /// 部品 1 つの置く物の元を束に分ける: 部屋の部品は 1 束・扉の部品は扉ごと（形のノードの名前が manifest の door.node の部屋）・ほかは 1 束。
    pub def groupsOf(rooms: List[Rooms.Room], part: Part, placed: List[Placed]): List[Group] =
        match Rooms.roomOfPart(rooms, part#name) {
            case Some(id) => { role = Role.Room(id), items = placed } :: Nil
            case None =>
                let doors = placed |> List.map(p -> (Rooms.doorOfNode(rooms, part#name, p#node), p));
                if (List.forAll(e -> Option.isEmpty(fst(e)), doors)) { role = Role.Always, items = placed } :: Nil
                else doors |> List.map(fst) |> List.distinct |> List.map(id ->
                    { role = id |> Option.map(Role.Door) |> Option.getWithDefault(Role.Always),
                      items = doors |> List.filter(e -> fst(e) == id) |> List.map(snd) })
        }

    /// 置く物の元を、自分で光る絵の Param（倍率と点滅する管の明るさ）を渡して置く。
    pub def instanceOf(params: Map[String, Float64], p: Placed): Scene3d.Instance3d = instanceAt(params, Mat4.identity(), p)

    /// instanceOf の、形を行列 m で動かして置く版（回る扉）。
    pub def instanceAt(params: Map[String, Float64], m: Mat4.Mat4, p: Placed): Scene3d.Instance3d =
        let material = if (p#emissive) Scene3d.withParams(params, p#material) else p#material;
        let inst = Scene3d.meshInstance(p#mesh, m) |> Scene3d.withMaterial(material);
        p#lightmap |> Option.map(lm -> Scene3d.withLightmap(lm, inst)) |> Option.getWithDefault(inst)

    /// 部品が読む絵（材質の絵・法線マップ・lightmap・自分で光る絵）。
    pub def texturesOf(part: Part): List[Texture3d.Texture3d] =
        List.flatten(part#model#textures :: Option.toList(part#lightmap) :: Option.toList(part#emissive) :: Nil)

    def k(v: Float64): Field = Field.Const(v)
    def mul(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Mul, a = a, b = b })
    def add(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Add, a = a, b = b })
    def sub(a: Field, b: Field): Field = Field.Bin({ op = BinOp.Sub, a = a, b = b })

    /// 箱の中で 1・外で 0（world の点が真ん中から各軸で半分の大きさの中にあるか）。
    def maskOf(m: LampMask): Field =
        let inside = (axis: ShaderDoc.Axis3, c: Float64, h: Float64) ->
            Field.Bin({ op = BinOp.Step, a = Field.Un({ op = ShaderDoc.UnOp.Abs, of = sub(Field.World({ axis = axis }), k(c)) }), b = k(h) });
        mul(inside(ShaderDoc.Axis3.X, m#x, m#hx), mul(inside(ShaderDoc.Axis3.Y, m#y, m#hy), inside(ShaderDoc.Axis3.Z, m#z, m#hz)))

    /// 自分で光る色: 絵 ×（点滅する管の範囲だけその管の明るさ）＋ 点きかけの管が瞬いた時の光。倍率は材質の emissionIntensity。
    /// WhyNot: 倍率を色の式の中で掛けない — 色は画面の値として線形へ戻されるので、1 を超える値は 2.2 乗で伸び、倍率を変えた時の明るさの変わり方が読めない。
    /// WhyNot: 点滅を絵ごと差し替えない — 部品 1 つに管が 5 本並んでいて、絵を替えると全部が一緒に消える。
    def emissionOf(texture: String, glowColor: (Float64, Float64, Float64), masks: List[LampMask]): Shade =
        let tex = (chan: ShaderDoc.TexChan) -> Field.Sampler({ filter = ShaderDoc.FilterMode.Linear, of = Field.Tex({ name = texture, chan = chan }) });
        let dim = masks |> List.foldLeft((acc, m) -> sub(acc, mul(maskOf(m), sub(k(1.0), Field.Param({ name = m#levelParam })))), k(1.0));
        let glow = masks |> List.foldLeft((acc, m) -> match m#glowParam {
            case Some(p) => add(acc, mul(maskOf(m), Field.Param({ name = p })))
            case None    => acc
        }, k(0.0));
        let (gr, gg, gb) = glowColor;
        let chan = (c: ShaderDoc.TexChan, g: Float64) -> add(mul(tex(c), dim), mul(glow, k(g)));
        Shade.Rgb({ r = chan(ShaderDoc.TexChan.R, gr), g = chan(ShaderDoc.TexChan.G, gg), b = chan(ShaderDoc.TexChan.B, gb) })
}
