// PlayClock — 遊びの時計の名前（engine の docs/clock.md）。歩く・自動の操縦・点滅・羽虫はこの時計の秒で進む。
// 終了の確認の窓が出ている間は止まる（World.paceOf）。止める理由は Halt。
mod PlayClock {
    /// 遊びの時計の名前（時刻 Clock.Time[Play] と時計 Clock.Clock[Play] の型に付ける）。
    pub enum Play

    /// 遊びの時計を止める理由。
    pub enum Halt with Eq, ToString {
        case AskingQuit
    }
}
