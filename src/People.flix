// People — 夜のアパートの住人（manifest.json の people）: 読み込み・置き場所・動きの時刻・起きた出来事・当たり判定・照らす灯り。
//
// 書き出しの座標は glTF（右手系）なので、置き場所は x を反転して engine の座標で持ち、向きは glTF の +Y まわりの角の符号を反転する
// （engine の Gltf は形を x の反転で読むので、同じ写し方にそろえる）。
// 動きの時刻は glTF の秒のまま（場面の fps へ直さない）。部屋にいる人は遊びの時計でループし、
// 階段の人は歩き出した時刻からの秒で 1 回だけ流れる（root motion。Root の動きが体を運び、置き場所は歩き出す所）。
// 読み込み（load）だけが IO で、ほかは純粋。
mod People {
    use fge::{
        AnimationClip3d, CharacterBody3d, CollisionShape3d, CollisionWorld3d, Color, DocJson, Gltf,
        ImageData, JsonCodec, LoadProgress, Log, Mat4, Model3d, Num, Pose3d, Scene3d, ShaderDoc,
        Skin3d, Texture3d, Vec3
    }
    use Util.Json.Json

    /// 動きの中の出来事 1 つ: 秒・名前（hit・stomp_l・step_r など）・足が着いた面（steel・concrete・ground。足音だけ）。
    pub type alias Event = { t = Float64, name = String, surface = Option[String] }

    /// 当たり判定のカプセル（足元から上へ）。
    pub type alias Capsule = { radius = Float64, height = Float64 }

    /// 住人 1 人（読む前の値。engine の座標）。room = 部屋の番号（階段の人は "stairs"）・
    /// position = 足元（root motion の人は歩き出す所）・yaw = 向き（ラジアン。0 で +Z）・
    /// loop = ループする動きか・duration = 動きの長さ（秒）・lights = 照らす灯り（使わない灯りは除いてある）・
    /// path = root motion の人の足元の道筋（秒・足元）。
    pub type alias Entry = { id = String, room = String, glb = String, position = Vec3.Vec3, yaw = Float64, loop = Bool, duration = Float64,
                             rootMotion = Bool, events = List[Event], capsule = Capsule, lights = List[Rooms.Light],
                             path = List[(Float64, Vec3.Vec3)] }

    /// 読み込んだ住人: 書き出しの値・形と絵・骨・動き。
    pub type alias Person = { entry = Entry, model = Model3d.Model3d, skin = Skin3d.Skin3d, clip = AnimationClip3d.AnimationClip3d }

    def pi(): Float64 = 3.141592653589793

    // ── manifest.json の people ──

    /// manifest.json の字から住人の並び（名前の順）。読めない人は捨てる。
    pub def entriesOf(text: String): List[Entry] =
        DocJson.parse(text)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(root -> Map.get("people", root))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(people -> Map.toList(people) |> List.filterMap(e -> {
                let (id, json) = e;
                JsonCodec.expectObject(json) |> Option.flatMap(entryOf(id))
            }))
            |> Option.getWithDefault(Nil)

    def objectOf(key: String, obj: Map[String, Json]): Map[String, Json] =
        Map.get(key, obj) |> Option.flatMap(JsonCodec.expectObject) |> Option.getWithDefault(Map.empty())

    def eventOf(obj: Map[String, Json]): Option[Event] =
        Map.get("t", obj) |> Option.flatMap(JsonCodec.expectFloat) |> Option.map(t ->
            { t = t, name = JsonCodec.stringOr("name", "", obj),
              surface = Map.get("surface", obj) |> Option.flatMap(JsonCodec.expectString) })

    def pathPointOf(obj: Map[String, Json]): Option[(Float64, Vec3.Vec3)] =
        forM (
            t <- Map.get("t", obj) |> Option.flatMap(JsonCodec.expectFloat);
            p <- Map.get("pos", obj) |> Option.flatMap(Rooms.pointOf)
        ) yield (t, p)

    def rowsOf(key: String, f: Map[String, Json] -> Option[a], obj: Map[String, Json]): List[a] =
        Map.get(key, obj) |> Option.flatMap(json -> JsonCodec.decodeList(JsonCodec.expectObject, json))
            |> Option.map(rows -> rows |> List.filterMap(f)) |> Option.getWithDefault(Nil)

    def entryOf(id: String, obj: Map[String, Json]): Option[Entry] =
        let anim = objectOf("animation", obj);
        let cap = objectOf("capsule", obj);
        let used = rowsOf("lights", o -> if (JsonCodec.stringOr("use", "", o) == "none") None else Some(o), obj);
        forM (
            glb <- Map.get("glb", obj) |> Option.flatMap(JsonCodec.expectString);
            position <- Map.get("position", obj) |> Option.flatMap(Rooms.pointOf)
        ) yield
            { id = id, room = JsonCodec.stringOr("room", "", obj), glb = glb, position = position,
              yaw = 0.0 - JsonCodec.floatOr("yaw_deg", 0.0, obj) * pi() / 180.0,
              loop = JsonCodec.boolOr("loop", true, anim), duration = JsonCodec.floatOr("duration_s", 0.0, anim),
              rootMotion = JsonCodec.boolOr("root_motion", false, obj), events = rowsOf("events", eventOf, anim),
              capsule = { radius = JsonCodec.floatOr("radius", 0.2, cap), height = JsonCodec.floatOr("height", 1.6, cap) },
              lights = used |> List.filterMap(Rooms.lightOf), path = rowsOf("path", pathPointOf, obj) }

    // ── 読み込み ──

    /// 書き出しのフォルダ dir の manifest.json の住人を全部読む（絵は limits まで縮める）。読めない人は理由を 1 行出して置かない。
    pub def load(dir: String, limits: Gltf.TextureLimits): List[Person] \ Fs.FileRead + IO + LoadProgress =
        let dec = LoadProgress.imageDecoder();
        let text = Fs.FileRead.read("${dir}/manifest.json") |> Result.getWithDefault("");
        let raws = entriesOf(text) |> LoadProgress.mapWithProgress("reading people...", e ->
            (e, Fs.FileRead.readBytes("${dir}/${e#glb}") |> Result.mapErr(err -> "${e#glb}: 読めない（${err}）")));
        raws
            |> LoadProgress.parMapWithProgress("decoding people...", raw -> decode(dec, limits, raw))
            |> List.filterMap(r -> match r {
                case Ok(p)    => Some(p)
                case Err(why) => Log.warnThen("[people] ${why}", None)
            })

    /// glb のバイトを形・骨・動きへ解く（骨か動きの無い glb は Err）。
    def decode(dec: ImageData.ImageDecoder, limits: Gltf.TextureLimits, raw: (Entry, Result[String, Vector[Int8]])): Result[String, Person] \ IO =
        let (e, bytes) = raw;
        bytes |> Result.flatMap(b -> Gltf.fromGlbTexturedUsing(dec, limits, b) |> Result.mapErr(why -> "${e#glb}: ${why}"))
            |> Result.flatMap(model -> {
                let clip = Map.valuesOf(model#clips) |> List.head;
                match (model#skin, clip) {
                    case (Some(skin), Some(c)) => Ok({ entry = e, model = model, skin = skin, clip = c })
                    case _                     => Err("${e#glb}: 骨か動きが無い")
                }
            })

    // ── 動きの時刻と出来事 ──

    /// 部屋にいる人（ループする・その場で動く）か。
    pub def isResident(e: Entry): Bool = not e#rootMotion

    /// 動きの秒 t0 から t1 の間（t0 は含まず t1 は含む）に起きた出来事。ループする動きは t を長さで回して数える
    /// （1 コマが動きの長さより短い前提で、同じ出来事は 1 回まで）。
    pub def eventsBetween(e: Entry, t0: Float64, t1: Float64): List[Event] =
        if (t1 <= t0) Nil
        else e#events |> List.filter(ev -> {
            if (not e#loop or e#duration <= 0.0) ev#t > t0 and ev#t <= t1
            else {
                let k = Float64.floor((t1 - ev#t) / e#duration);
                let at = ev#t + k * e#duration;
                k >= 0.0 and at > t0
            }
        })

    /// root motion の人の、動きの秒 t の足元（道筋の点の間をなめらかにつなぐ。前と後ろは端の点）。
    pub def pathAt(e: Entry, t: Float64): Vec3.Vec3 =
        let pick = (acc: (Option[(Float64, Vec3.Vec3)], Option[(Float64, Vec3.Vec3)]), pt: (Float64, Vec3.Vec3)) -> {
            let (lo, hi) = acc;
            if (fst(pt) <= t) (Some(pt), hi) else (lo, if (Option.isEmpty(hi)) Some(pt) else hi)
        };
        match List.foldLeft(pick, (None, None), e#path) {
            case (Some((t0, a)), Some((t1, b))) =>
                let k = if (t1 - t0 <= 0.0) 0.0 else (t - t0) / (t1 - t0);
                Vec3.add(a, Vec3.mul(Vec3.sub(b, a), k))
            case (Some((_, a)), None) => a
            case (None, Some((_, b))) => b
            case (None, None)         => e#position
        }

    /// 動きの秒 t の足元（その場で動く人は置き場所のまま）。
    pub def feetAt(e: Entry, t: Float64): Vec3.Vec3 = if (e#rootMotion) pathAt(e, t) else e#position

    // ── 当たり判定 ──

    /// 足元 feet に立つカプセルを囲む縦の箱（向きは人の向き）。
    /// WhyNot: 丸い柱の押し出しを別に書かない — 体の押し出し・細かく区切って進む・食い込みの検査が全部箱の規則なので、
    /// 箱にすれば同じ道を通る（角が半径の 0.41 倍だけ外へ出る）。
    pub def capsuleBox(e: Entry, feet: Vec3.Vec3): CollisionShape3d.Box3d =
        let (s, c) = (Num.sin(e#yaw), Num.cos(e#yaw));
        let h = e#capsule#height / 2.0;
        { center = Vec3.v3(feet#x, feet#y + h, feet#z), ax = Vec3.v3(c, 0.0, 0.0 - s), ay = Vec3.v3(0.0, 1.0, 0.0),
          az = Vec3.v3(s, 0.0, c), half = Vec3.v3(e#capsule#radius, h, e#capsule#radius) }

    /// 部屋にいる人のカプセルの箱（いつも同じ所に立つので、常に効く箱に足す）。
    pub def residentBoxes(people: List[Entry]): List[CollisionShape3d.Box3d] =
        people |> List.filter(isResident) |> List.map(e -> capsuleBox(e, e#position))

    /// 部屋にいる人ごとの、カプセル（段の高さより上）が箱へ食い込む一番深い所（m。食い込まなければ 0）。書き出しの置き場所の確かめ。
    pub def placementOverlaps(world: CollisionWorld3d.CollisionWorld3d, stepHeight: Float64, people: List[Entry]): List[(String, Float64)] =
        people |> List.filter(isResident) |> List.map(e -> {
            let s = { stepHeight = stepHeight | CharacterBody3d.settings(e#capsule#radius, e#capsule#height) };
            (e#id, CharacterBody3d.overlapDepth(world, Nil, s, CharacterBody3d.bodyAt(e#position)))
        })

    // ── 階段の人が歩き出す所 ──

    /// 足元が歩き出す範囲の中か。
    pub def isInTrigger(a: PeopleDoc.Area, x: Float64, feet: Float64, z: Float64): Bool =
        x >= a#minX and x <= a#maxX and z >= a#minZ and z <= a#maxZ and feet >= a#minY and feet <= a#maxY

    // ── 描く ──

    /// 置く行列（足元へ動かし、向きへ回す）。
    def worldOf(e: Entry): Mat4.Mat4 = Mat4.mul(Mat4.translate(e#position), Mat4.rotateY(e#yaw))

    /// 動きの秒 t の姿勢。
    def poseAt(p: Person, t: Float64): Pose3d.Pose3d =
        Pose3d.compute(p#skin, AnimationClip3d.sample(p#skin, p#clip, t, p#entry#loop))

    /// 動きの秒 t の姿勢で置いた形（材質の無い primitive は頂点の色で）。
    pub def instancesAt(p: Person, t: Float64): List[Scene3d.Instance3d] =
        let pose = poseAt(p, t);
        let m = worldOf(p#entry);
        p#model#parts |> List.map(part -> {
            let material = part#material |> Option.getWithDefault(Scene3d.material(ShaderDoc.demoSurface()));
            Scene3d.meshInstance(part#mesh, m) |> Scene3d.withMaterial(material) |> Scene3d.withPose(pose)
        })

    /// 人の読む絵。
    pub def texturesOf(p: Person): List[Texture3d.Texture3d] = p#model#textures

    /// 人を照らす点光源: manifest の灯りのうち、部屋の灯り（skip の名前）と重ならない物。強さは Blender の W × gain を上限で抑える。
    /// WhyNot: 部屋の灯りと同じ名前の灯りを足さない — 同じ光が部屋の灯りとして既に入っていて、二重に照らす。
    pub def lightsOf(doc: PeopleDoc.Light, skip: Set[String], e: Entry): List[Scene3d.PointLight] =
        e#lights |> List.filter(l -> not Set.memberOf(l#name, skip)) |> List.map(l -> {
            let (r, g, b) = l#color;
            { position = l#position, color = Color.rgb(r, g, b), intensity = Float64.min(doc#maxIntensity, l#watts * doc#gain),
              range = l#range * doc#rangeScale }
        })
}
