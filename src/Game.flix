// Game — App の組み立て。実機の起動（Main）・flow の入口（E2e）・テスト・描き出し・動画が同じ物を使う。
// Doc と舞台は App を組む前に読み、その値から描く元（Res）を作る（壊れていても defaults で必ず起動する）。
// App の w は描く元と遊びの状態（World）の組（Resources.With）で、系・絵・問いは Resources の口で両方を受ける。
//
// ── ゲームループの全体像（App.game の 1 レコード）──
//   init    = 出発点の組（描く元 Res と初期の World）。
//   update  = 毎フレームの更新（入力 → 次の World。秒は遊びの時計 = App.addClock が先に進める）。
//   view    = (Res, World) → 「何をどこに描くか」。Pass の計画（3D の場面・ブルーム・後処理）は Main の withPassPlan。
//   音      = 起きた音（足音・扉・住人・機械の動き出し）は withAudio・続く音（場所の環境音・置いてある物の音）は withSustained・
//             種類ごとの音量（Doc と遊ぶ人の音量）と住人の音の距離と壁は withMixer（Sounds）。
mod Game {
    use fge::{App, Resources}

    /// 遊びから始める App（flow・テスト・描き出し・動画）。
    pub def app(docs: Res.Docs): App.App[Resources.With[Res.Res, World.World], {}] = appFrom(World.initial, docs)

    /// 読み込みの幕から始める App（実機の起動）。幕の裏で舞台の部品を GPU へ上げてから歩き始める。
    pub def appWithLoading(docs: Res.Docs): App.App[Resources.With[Res.Res, World.World], {}] = appFrom(World.loading, docs)

    def appFrom(start: Res.Res -> World.World, docs: Res.Docs): App.App[Resources.With[Res.Res, World.World], {}] =
        let res = Res.build(docs);
        App.game({
            init = Resources.of(res, start(res)),
            update = Resources.system(Controls.step),
            view = Resources.view(View.frame),
            reloads = Nil
        })
            |> Resources.addClock({ clockOf = w -> w#play, withClock = (c, w) -> { play = c | w }, paceOf = (_, w) -> World.paceOf(w) })
            |> App.withDocTable(Controls.docTable())
            |> App.withAudio(ws -> Resources.read((r, after) -> Resources.read((_, before) -> Sounds.events(r, before, after), ws#before), ws#after))
            |> App.withSustained(Resources.read(Sounds.hums))
            |> App.withMixer(Resources.read(Sounds.mixerOf))
            // 窓を押すとマウスをキャプチャして視点を回す（Esc で放す。放している時の Esc は終了の確認で、既定の Esc の終了は使わない）。
            |> App.withMouseCapture(Resources.read((_, w) -> World.isLooking(w)))
            |> App.quitWhen((_, h) -> Resources.read((_, w) -> World.isQuitting(w), h))
            // F3 で出す 1 コマの重さ（GPU の時間を含む）。
            |> App.withDiagnostics
            // 好きな場面から起動する・テストと flow が場面を名前で組む（START="tour" など）。
            |> App.withStarts(Starts.all() |> List.map(Resources.liftStart))
            |> App.withFlow(E2e.table())
            |> App.withFingerprint(Resources.read(E2e.fingerprint))
            |> App.withStatusLine(Resources.read(E2e.fingerprint))
            |> App.onRenderRequest(SceneRender.allShots)
}
