// ZOrder — 画面全体の重なりの層（奥から手前）。Unity の Sorting Layer と同じ考え方。
// 新しい層は case を足し、zRange に範囲を書く（書き忘れは match の網羅で止まる）。
// 使い方の全文は engine の engine_world/src/SortingLayer.flix 冒頭と docs/z-bands.md。
mod ZOrder {

    use fge::SortingLayer

    pub enum Layer with Eq, ToString {
        case Scene    // 一人称の場面（後処理の面 1 枚）
        case Loading  // 起動の読み込みの幕
        case Hud      // マウスをキャプチャしている間の真ん中の点・F3 の診断
        case Volume   // マウスを放している間の隅の音量の印と、開いた音量の窓
        case Prompt   // 終了の確認の窓（どれよりも手前）
    }

    instance SortingLayer[Layer] {
        pub def zRange(layer: Layer): (Int32, Int32) =
            match layer {
                case Layer.Scene   => (0, 199)
                case Layer.Loading => (200, 249)
                case Layer.Hud     => (250, 259)
                case Layer.Volume  => (260, 289)
                case Layer.Prompt  => (300, 309)
            }
    }

    /// 奥から手前へ全部の層（F8 の注釈の文脈・表のテストが使う）。
    pub def layers(): List[Layer] = Layer.Scene :: Layer.Loading :: Layer.Hud :: Layer.Volume :: Layer.Prompt :: Nil
}
