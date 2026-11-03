// 舞台の読み込みのテスト: manifest.json の部品の一覧・lightmap の島の間・当たり判定の箱・lightmap つきで置けるか。
// 期待値は書き出しの manifest.json の値（部品の数・小物の部品の島の間）と Blender の寸法から。
mod TestStage {
    use fge::{LoadProgress, Mesh3d, Scene3d}

    def manifest(): String \ Fs.FileRead = Fs.FileRead.read("assets/apartment/manifest.json") |> Result.getWithDefault("")

    /// manifest.json の部品は 24 個（2 階の 4 部屋・扉・建物の裏・裏の空き地を足した書き出し）で、
    /// 外廊下の小物（bld_props）は自分で光る絵を持ち、lightmap の島の間は UV の 0.00195。
    @Test
    def testManifestListsEveryPart(): Unit \ {Assert, Fs.FileRead} =
        let entries = Stage.entriesOf(manifest()) |> Result.getWithDefault(Nil);
        let props = List.find(e -> e#name == "bld_props", entries);
        Assert.assertEq(expected = (24, Some((true, 0.00195))),
            (List.length(entries), props |> Option.map(e -> (Option.nonEmpty(e#emissive), e#gapUv))))

    /// 壊れた manifest は Err（黙って空の舞台にしない）。
    @Test
    def testBrokenManifestIsErr(): Unit \ Assert =
        Assert.assertEq(expected = true, Result.isErr(Stage.entriesOf("{ not json")))

    /// 当たり判定の箱は manifest の 234 個から、斜めの手すり 9 本（3 階ぶん × 3 本）を縦の箱 6 本ずつに置き換えた 234 - 9 + 9 × 6 = 279 個。
    @Test
    def testSlantedRailsAreSplit(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = 279, List.length(TestKit.boxes()))

    /// 段板の箱は傾いている（3 本の向きのどれも真上を向かない）。段板 A の 1 階は (-17.69, 0.96, -0.78) のあたり。
    @Test
    def testFlightBoxIsTilted(): Unit \ {Assert, Fs.FileRead} =
        let flight = TestKit.boxes() |> List.find(bx -> Float64.abs(bx#center#x + 17.69) < 0.05 and Float64.abs(bx#center#y - 0.96) < 0.1);
        Assert.assertEq(expected = Some(true),
            flight |> Option.map(bx -> Float64.abs(bx#ax#y) < 0.98 and Float64.abs(bx#ay#y) < 0.98 and Float64.abs(bx#az#y) < 0.98))

    /// 小さい部品 1 つ（far_ground）だけを読むと、2 本目の uv と lightmap を持ち、置いた物に lightmap が付く（知らせが出ない）。
    @Test
    def testPartLoadsWithLightmap(): Unit \ {Assert, Fs.FileRead, IO} =
        let others = Stage.entriesOf(manifest()) |> Result.getWithDefault(Nil) |> List.map(e -> e#name) |> List.filter(n -> n != "far_ground");
        let doc = StageDoc.Doc.Doc({ skip = others | StageDoc.rec(StageDoc.defaults()) });
        let loaded = LoadProgress.runNoop(() -> Stage.load(doc));
        let placed = loaded#parts |> List.flatMap(Stage.placedOf(3.0, (1.0, 1.0, 1.0), Nil));
        let inst = placed |> List.map(Stage.instanceOf(Map.empty()));
        Assert.assertEq(expected = (1, true, true, Nil),
            (List.length(loaded#parts), List.forAll(p -> Option.nonEmpty(Mesh3d.uvs2(p#mesh)), placed),
             List.forAll(i -> Option.nonEmpty(Scene3d.lightmapOf(i)), inst), inst |> List.filterMap(Scene3d.lightmapWarning)))
}
