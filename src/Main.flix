// エントリーポイント。App の組み立ては Game（flow の入口 E2e とテストも同じ物を使う）。
// ここで足すのは main だけが知る物（GPU のアトラス・Pass の計画・終了の確認・注釈・デバッグの印）。
// 起動の読み込み（Doc と舞台の glb・絵）は LoadProgress で区切り、起動画面のバーを進める。

use fge::{App, LwjglLayer, Resources}

def main(): Unit \ IO =
    if (LwjglLayer.ensureMainThread()) ()
    else {
        run {
            App.loadAndLaunch(() -> Game.appWithLoading(Controls.loadDocs())
                // 羽虫の粒のドット絵を GPU へ上げる（鍵が同じ間は上げ直さない）。
                |> App.withSpriteAtlases(Resources.read((res, _) ->
                    { texture = Res.atlasName(), key = res#atlasKey, baked = res#atlas } :: Nil))
                // 3D の場面・ブルーム・後処理を先に Pass へ描き、本編の面が読み返す。読み込み中は部品を 1 つずつ GPU へ上げる Pass。
                |> App.withPassPlan(Resources.read((res, w) -> View.passPlan(res, w)))
                // 窓の閉じるボタンも Esc と同じ確認へ回し、はいを選んだら終わる。
                |> App.withCloseRequest(Resources.mapWorld((_, w) -> World.askQuit(w)))
                |> App.withAnnotationContext(Resources.read((res, w) ->
                    { facts = ("状態", E2e.fingerprint(res, w)) :: Nil,
                      layers = ZOrder.layers(), hudLayers = (Nil: List[ZOrder.Layer]) }))
                // 遊ぶ人が変えた音量を saves/audio.json に残す（次の起動で Controls.loadDocs が読み戻す）。
                |> App.addOutput(Resources.liftOutput({ keyOf = w -> AudioPrefs.toText(World.prefsOf(w)), write = w -> AudioPrefs.save(World.prefsOf(w)), onJump = App.OnJump.Skip }))
                |> App.onRenderRequest(SceneRender.allShots)
                |> App.withDebug(App.debugFromEnv()))
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
    }


