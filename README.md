# Night Apartment

夜の 4 階建てアパート（Blender で作った舞台・ベイクした光つき）を一人称で歩き回るゲーム。
道路から自販機の前・門・敷地・鉄の外階段・各階の外廊下まで歩ける。

## 始め方

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（読み込みの幕の後に、道路の端から歩き始める） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動（遊んだ操作を `debug/flow-record/latest.flow` に記録する） |
| `make check`  | 型検査だけ |
| `make test`   | テスト（舞台の読み込み・当たり判定・階段・自動の操縦・Doc の橋渡し） |
| `make video`  | 決めた道筋を歩く紹介の動画 → `debug/video/tour.mp4`（手順 `e2e/tour.flow`・道筋 `assets/tour.route.json`。音つき） |
| `make video FLOW=e2e/people.flow OUT=people` | 住人の動画 → `debug/video/people.mp4`（階段ですれ違う人・204・203・202 の住人。音つき） |
| `make people-stills` | 住人の 4 枚を Blender の目標（`renders/people/<名前>_game.png`）と同じ構図・同じ動きの秒で撮り、並べる → `debug/compare/person_<名前>.png` |
| `make stills` | 静止画の目標（`renders/CAM_*_final.png`）と同じ構図を GPU で撮る → `debug/stills/*.png` |
| `make render-all` | 決まった場面を SoftRaster で描く → `gallery/*.png`（CPU なので遅い） |
| `make sfx`    | 録音素材（`assets/sfx/src/`・出どころは `assets/sfx/CREDITS.md`）から音を作って `assets/sfx/` に書き、`project.json` の sounds をそろえる（`tools/sfx_build.py`・ffmpeg が要る） |
| `START="tour" make run` | 道筋を自動で歩く所から起動する（重さを測る時など） |
| `START="at x=-11.9 y=3.1 z=0.66 yaw=90" make run` | 好きな所に立って起動する（`src/Starts.flix`。`t=` で住人の動きの秒・`stairs=` で階段の人・`diag=1` で F3 の表示） |

### 操作

W A S D で歩く・Shift で走る・← → で向きを変える・E で向いている玄関の扉を開け閉め・R V で見上げ見下ろし・
窓をクリックするとマウスを窓にキャプチャして、マウスを動かすと視点が回る（真ん中に小さな点が出る。Esc で放す）・
キャプチャしていない時は右下のスピーカーの印か M で音量の窓（全体・環境音・効果音。↑↓ で行・←→ で音量・Esc か窓の外で閉じる。値は `saves/audio.json` に残る）・
キャプチャしていない時の Esc で終了の確認・F で手の灯り・C で当たり判定の箱を重ねて描く・F3 で 1 コマの重さ（GPU の時間を含む）を左上に出す
（出している間は `debug/diagnostics.txt` にも書く）。
割り当ては `assets/player.keys.json`。マウスの感度と上下の反転は `assets/walk.kind.json` の `mouseSensitivity`・`invertY`。

## 舞台

`assets/apartment` は Blender の書き出しのフォルダ（`/Users/abab/Desktop/horror_apartment/export`）への symlink（git に入れない）。
書き出しの場所は `assets/stage.kind.json` の `dir`。`manifest.json` の部品を全部読み、lightmap（`TEXCOORD_1`）と
自分で光る絵（蛍光灯・自販機）を付けて engine の Scene3d 1 つで描く。当たり判定は `collision.glb` の箱
（斜めの手すりは、縦の短い箱の列に置き換えて使う。`Collider.railSegments`）。

## 住人

`manifest.json` の `people` の 4 人（`src/People.flix`）。置き場所・向き・動き（glTF の秒のまま）・出来事の秒・カプセル・照らす灯りは書き出しが正。
203 の揺れる老人・204 の壁に頭を打つ男性・202 の地団駄の女性は、部屋を描く時だけ描き、遊びの時計でループする。
外階段の人は、足元が `people.kind.json` の範囲（1 階の段板 A の下）に入ったら 1 回だけ流れ（root motion）、歩き去ったら消えたまま。
立っている 3 人のカプセル（を囲む縦の箱）と歩いている階段の人は、体の押し出しに入る。
頭を打つ音（`hit`）・地団駄（`stomp_l` / `stomp_r`）・階段の人の足音（`step_l` / `step_r` と面）は出来事の秒に鳴り、人ごとのバス（`p_<人>`）で
耳からの距離で小さく、別の部屋や閉じた扉の向こうでは籠もらせる（`Sounds.mixerOf`）。

## 音

録音素材（Freesound の CC0）から `make sfx` で作る。出どころは `assets/sfx/CREDITS.md`。

- **響き**: engine にリアルタイムの響きが無いので、プレイヤーが鳴らす一発の音（足音・扉・手の灯り）は、場所ごと（屋外・外廊下・外階段・部屋）の
  実在の場所のインパルス応答を書き出しの時に畳み込んだ版（`<名前>_<場所>.wav`）を作り、耳のいる場所で選ぶ（`Soundscape.spaceAt`）。
- **足音**: 面（コンクリート・鉄・土・畳・板の間。`night.sound.json` の surfaces）ごとに 4 本の差分があり、続けて同じ音にならない。
- **環境音**: 屋外の夜（遠くの車と虫）・外廊下の蛍光灯のうなり（点いている管の近くだけ）・外階段の風・部屋の中の音（冷蔵庫・時計・換気扇。部屋ごと）を、
  ずっと小さく鳴らし、場所の境目ではなめらかに移る（`Soundscape.weightsAt`）。部屋の中では屋外の音の高い音を削る。
- **置いてある物**: 室外機 18 台・給湯器 18 台・自販機・電柱の変圧器・電線の風切り・換気扇のフード・隣の生活音を、置き場所（`night.sound.json` の spots。
  horror_apartment の scripts の置き方の式から）から距離で小さくして鳴らす。数が多い物は近い数台だけ。室外機と給湯器は物ごとに周期をずらして、
  全部が同時には動かない（動き出しに一発の音：室外機の起動・給湯器の点火）。遠くの電車と救急車はごく稀に。
- **音量**: 種類ごとのバス（足音・扉・手の灯り・環境音…）に Doc の大きさと遊ぶ人の音量（全体・環境音・効果音）を掛ける（`Sounds.mixerOf`）。

## 構成

| ファイル | 中身 |
|---|---|
| `src/Stage.flix` | manifest を読み、部品の glb・lightmap・発光の絵を並列に解き、置く物の元にする |
| `src/Collider.flix` | 当たり判定の箱（向きのある箱）・体の球の押し出し・真下の床 |
| `src/Walker.flix` | 一人称の体（足の着き方は `Footing` の enum）と、1 コマ進める純粋な規則（細かく区切って進む） |
| `src/Pilot.flix` | 道筋を歩く自動の操縦（動画・flow・テスト） |
| `src/Flicker.flix` | 蛍光灯の点滅の形（時刻だけで決まる） |
| `src/World.flix` | 遊びの状態（読み込みの幕と歩いている間）・遊びの時計（`PlayClock`） |
| `src/StageView.flix` | 一人称の場面（空・舞台・手の灯り・瞬いた光・羽虫・霧・当たり判定の表示） |
| `src/PostView.flix` | ブルーム・トーンマップ・ビネット・粒・色調・FXAA |
| `src/LoadingView.flix` | 読み込みの幕（幕の裏で部品を 1 コマに 1 つずつ GPU へ上げる。`View.warmPlan`） |
| `src/People.flix` | 住人の読み込み・動きの秒と出来事・カプセルの箱・照らす灯り |
| `src/Sounds.flix` / `src/Soundscape.flix` | どの音をいつ・どれだけ鳴らすか（バス・響きの版の選び方）/ 場所と時刻の規則（耳のいる場所・足元の面・置いてある物がいつ動くか） |
| `src/AudioPrefs.flix` / `src/VolumeView.flix` | 遊ぶ人の音量（保存と読み戻し）/ 右下の音量の印と窓 |
| `tools/sfx_build.py` | 録音素材から音を作る（切り出し・正規化・場所ごとの響きの畳み込み・ループ） |
| `src/render/VideoRender.flix` / `SceneRender.flix` | 動画 / 静止画の描き出し |

## Doc（保存即反映）

| Doc | 中身 |
|---|---|
| `assets/walk.kind.json` | 歩く速さ・走る速さ・向きを変える速さ・マウスの感度と上下の反転・目の高さ・体の大きさ・段の高さ・歩ける範囲 |
| `assets/night.look.json` | ベイクした光の倍率・発光の倍率・空と霧・露出・ブルーム・ビネット・粒・色調 |
| `assets/night.lights.json` | 手の灯り（縁で暗くなり始める角 `innerConeDeg`）・点滅の光・羽虫・外廊下の蛍光灯 20 本（状態と点滅の形） |
| `assets/night.sound.json` | 足音の面と響きの場所の範囲・場所の環境音と部屋の中の音の大きさ・一発の音の大きさ・置いてある物（室外機・給湯器・自販機・変圧器・電線・換気扇・隣の生活音）の大きさと動く周期と置き場所・ごく稀な遠くの音 |
| `assets/tour.route.json` | 紹介の動画で歩く道筋 |
| `assets/people.kind.json` | 住人を照らす灯りの強さ・階段の人が歩き出す範囲と秒・住人の音の大きさと壁の籠もり・絵の上限 |
| `assets/stage.kind.json` | 書き出しのフォルダと絵の上限（起動の時だけ読む） |
| `assets/player.keys.json` | キーの割り当て |

## 挟まった時（遊んでいて壁や手すりに引っかかった・抜けた）

1. `make debug` で遊ぶ。起動から全部のフレームが `debug/flow-record/latest.flow` に記録される（F8 のチケットにも `record.flow` が入る）。
2. 挟まったら、そこで F8 を押してチケットを残すか、そのままウィンドウを閉じる。
3. 記録を `e2e/stuck-<場所>.flow` へ写し、`make flow FLOW=e2e/stuck-<場所>.flow` で同じ所に着くことを確かめる
   （指紋は足元の cm と足の着き方。`C` キーの当たり判定の表示で、どの箱に当たっているかを見る）。
4. 挟まった所の足元・向き・走っていたか・1 コマの秒を `test/WalkCases.flix` の `edges()` に 1 行足す
   （`dash("<場所>", x, 足元の高さ, z, 向き)`）。`make test` で `TestWalkProperty.testEdgeCasesNeverPenetrate` が落ちるのを確かめてから、
   `src/Collider.flix` か `src/Walker.flix` を直す。
5. 階段や坂で起きたなら、`test/TestWalk.flix` に「その段を上り下りして床の高さに着く」1 本も足す。
