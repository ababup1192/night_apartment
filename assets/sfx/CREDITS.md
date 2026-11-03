# 音の素材の出どころ（assets/sfx/src/）

assets/sfx/*.wav は、下の録音素材から `make sfx`（tools/sfx_build.py）で作る。素材はすべて Freesound（https://freesound.org）の
**CC0 1.0（パブリックドメイン）** で、商用利用・改変・再配布ができ、表記の義務も無い（礼儀として作者を残す）。
CC BY・非商用・再配布不可の素材は使っていない。

- 取得: 2026-11-03。Freesound の検索で CC0 に絞り、音のページで CC0 であることを確かめてから、ページの試聴用の高音質版
  （`-hq.ogg`。元のファイルはログインが要るので取っていない）を落とした。
- 加工の共通: モノラル化（環境音のループはステレオのまま）・44.1 kHz・切り出し・低い音の削り（highpass）・必要な物は高い音の削り（lowpass）・
  足音などの一発の音は立ち上がりの前の雑音を落としてピーク -1 dBFS にそろえる・ループは頭と尻を重ねて継ぎ目を消し RMS をそろえる。
- プレイヤーが鳴らす一発の音（足音・扉・手の灯り）は、場所ごとのインパルス応答を畳み込んだ版を <名前>_<outdoor|corridor|stairs|room>.wav として作る。
- 畳の足音は、CC0 の畳の録音が見つからなかったので、カーペットの足音の高い音を削って代わりにしている。
- 室外機の 2 台目と給湯器の 2 台目のループは、同じ素材の別の区間を ±4 % 高さをずらして作った（近くで 2 台鳴っても同じ音が重ならない）。
- 細かい数（切る秒・フィルタ・響きの大きさ）は tools/sfx_build.py が正。

| ファイル | 出どころ | 作者 | ライセンス | 元の題 | 使い道と加工 |
|---|---|---|---|---|---|
| `amb_outdoor_traffic__fs333086.ogg` | https://freesound.org/people/memuse/sounds/333086/ | memuse | CC0 1.0 | california night time suburb ambience distant traffic.wav | amb_outdoor（ループ・4.5 秒目から 38.0 秒ぶん） |
| `amb_outdoor_crickets__fs699143.ogg` | https://freesound.org/people/roisin.gleeson/sounds/699143/ | roisin.gleeson | CC0 1.0 | Night_Suburb_Crickets_wind.wav | amb_outdoor（ループ・0.5 秒目から 38.0 秒ぶん） |
| `fluo_hum__fs383657.ogg` | https://freesound.org/people/deleted_user_7146007/sounds/383657/ | deleted_user_7146007 | CC0 1.0 | Fluorescent Light Hum | m_vending（ループ・1.0 秒目から 16.0 秒ぶん） |
| `fluo_faulty__fs125064.ogg` | https://freesound.org/people/EverydaySounds/sounds/125064/ | EverydaySounds | CC0 1.0 | Faulty Fluorescent Light Starter & Hum.wav | amb_corridor（ループ・5.5 秒目から 11.5 秒ぶん） |
| `fluo_buzzclicks__fs577277.ogg` | https://freesound.org/people/TRP/sounds/577277/ | TRP | CC0 1.0 | Fluorescent light fixture, buzz, clicks, noisy, lofi, 2011.wav | fluo_zap_1（0.45 秒目から 0.50 秒ぶん）<br>fluo_zap_2（1.75 秒目から 0.50 秒ぶん）<br>fluo_zap_3（2.95 秒目から 0.75 秒ぶん）<br>fluo_zap_4（19.30 秒目から 0.60 秒ぶん） |
| `room_fridge__fs637570.ogg` | https://freesound.org/people/kyles/sounds/637570/ | kyles | CC0 1.0 | fridge refrigerator compressor light hum not active with nice airy kitchen tone +small perspective shifts.flac | room_fridge（ループ・17.5 秒目から 20.0 秒ぶん） |
| `room_clock__fs434841.ogg` | https://freesound.org/people/giddster/sounds/434841/ | giddster | CC0 1.0 | Kitchen Wall Clock Ticking 2 | room_clock（ループ・49.5 秒目から 12.0 秒ぶん） |
| `room_fan__fs584896.ogg` | https://freesound.org/people/KrystianPawlowski/sounds/584896/ | KrystianPawlowski | CC0 1.0 | bathroom ventilation fan.wav | room_fan（ループ・48.5 秒目から 20.0 秒ぶん） |
| `stairs_wind__fs50596.ogg` | https://freesound.org/people/Spandau/sounds/50596/ | Spandau | CC0 1.0 | stairwell_wind.aif | amb_stairs（ループ・7.0 秒目から 40.0 秒ぶん） |
| `step_concrete__fs459964.ogg` | https://freesound.org/people/florianreichelt/sounds/459964/ | florianreichelt | CC0 1.0 | Footsteps on concrete | step_concrete_1..4_<場所>（立ち上がり 3.27, 8.69, 12.67, 18.15 秒・0.34 秒ずつ） |
| `step_metal__fs452421.ogg` | https://freesound.org/people/sagamusix/sounds/452421/ | sagamusix | CC0 1.0 | Metal Stairs Foot Steps | step_metal_1..4_<場所>（立ち上がり 0.88, 2.59, 4.21, 7.34 秒・0.60 秒ずつ） |
| `step_metal2__fs451863.ogg` | https://freesound.org/people/kyles/sounds/451863/ | kyles | CC0 1.0 | footsteps shoes metal stairs up down resonate slow awkward with pants noise.flac | p_stairwalker_step_steel_l（9.85 秒目から 0.50 秒ぶん）<br>p_stairwalker_step_steel_r（14.36 秒目から 0.50 秒ぶん） |
| `step_dirt__fs352870.ogg` | https://freesound.org/people/PotatokingXII/sounds/352870/ | PotatokingXII | CC0 1.0 | Footsteps Dirt Gravel | p_stairwalker_step_ground_l（16.03 秒目から 0.30 秒ぶん）<br>p_stairwalker_step_ground_r（22.49 秒目から 0.32 秒ぶん） |
| `step_wood__fs505832.ogg` | https://freesound.org/people/jedg/sounds/505832/ | jedg | CC0 1.0 | Footsteps indoors wood floor.wav | step_wood_1..4_<場所>（立ち上がり 1.29, 2.78, 4.76, 5.76 秒・0.40 秒ずつ） |
| `door_metal_spring__fs429130.ogg` | https://freesound.org/people/leonelmail/sounds/429130/ | leonelmail | CC0 1.0 | Spring Loaded Metal Door Creak Open Close 02 | door_creak（0.25 秒目から 2.55 秒ぶん） |
| `res_wall_thumps__fs862895.ogg` | https://freesound.org/people/lreeve/sounds/862895/ | lreeve | CC0 1.0 | Hand thumps on wall | p_headbanger_hit_1（6.92 秒目から 0.85 秒ぶん）<br>p_headbanger_hit_2（17.49 秒目から 0.85 秒ぶん）<br>p_headbanger_hit_3（25.13 秒目から 0.85 秒ぶん） |
| `res_floor_stomps__fs478307.ogg` | https://freesound.org/people/_micro/sounds/478307/ | _micro | CC0 1.0 | Roomy Acoustic Floor Stomps Kick | p_stomper_stomp_l（6.14 秒目から 0.65 秒ぶん）<br>p_stomper_stomp_r（4.92 秒目から 0.65 秒ぶん） |
| `res_sneaker_stone__fs677069.ogg` | https://freesound.org/people/xkeril/sounds/677069/ | xkeril | CC0 1.0 | Footsteps stone + sneaker | p_stairwalker_step_concrete_l（5.36 秒目から 0.40 秒ぶん）<br>p_stairwalker_step_concrete_r（8.33 秒目から 0.40 秒ぶん） |
| `flashlight_click__fs187335.ogg` | https://freesound.org/people/baidonovan/sounds/187335/ | baidonovan | CC0 1.0 | Flashlight Clicking On.wav | flash_off（0.00 秒目から 0.26 秒ぶん） |
| `flashlight_click2__fs690300.ogg` | https://freesound.org/people/Ralph0o7/sounds/690300/ | Ralph0o7 | CC0 1.0 | Flashlight Switch Click | flash_on（0.00 秒目から 0.20 秒ぶん） |
| `ac_exterior__fs874837.ogg` | https://freesound.org/people/loganzsound/sounds/874837/ | loganzsound | CC0 1.0 | Exterior Air Conditioning Unit | m_ac_run_1（ループ・2.0 秒目から 12.0 秒ぶん）<br>m_ac_run_2（ループ・15.0 秒目から 12.0 秒ぶん） |
| `ac_startup__fs189985.ogg` | https://freesound.org/people/raygrote/sounds/189985/ | raygrote | CC0 1.0 | AC start up fan w comp.flac | m_ac_start（0.00 秒目から 4.00 秒ぶん）<br>m_ac_run_3（ループ・5.0 秒目から 11.0 秒ぶん） |
| `water_heater__fs423388.ogg` | https://freesound.org/people/keng-wai-chane-chick-te/sounds/423388/ | keng-wai-chane-chick-te | CC0 1.0 | HOME_WATER_HEATER_GAZ.wav | m_heater_ignite（1.30 秒目から 4.70 秒ぶん）<br>m_heater_burn_1（ループ・20.0 秒目から 14.0 秒ぶん）<br>m_heater_burn_2（ループ・36.0 秒目から 14.0 秒ぶん） |
| `vending_hum__fs730438.ogg` | https://freesound.org/people/HECKFRICKER/sounds/730438/ | HECKFRICKER | CC0 1.0 | Vending Machine Hum | m_vending（ループ・26.5 秒目から 16.0 秒ぶん） |
| `transformer__fs641208.ogg` | https://freesound.org/people/ideaph/sounds/641208/ | ideaph | CC0 1.0 | transformer at night.wav | m_transformer（ループ・20.5 秒目から 12.0 秒ぶん） |
| `powerline_wind__fs829000.ogg` | https://freesound.org/people/bruno.auzet/sounds/829000/ | bruno.auzet | CC0 1.0 | gusts on overhead power lines | m_wires（ループ・60.0 秒目から 30.0 秒ぶん） |
| `extractor_hood__fs472881.ogg` | https://freesound.org/people/bolkmar/sounds/472881/ | bolkmar | CC0 1.0 | Kitchen extractor fan | m_hood（ループ・1.0 秒目から 12.0 秒ぶん） |
| `train_distant__fs475501.ogg` | https://freesound.org/people/o_ciz/sounds/475501/ | o_ciz | CC0 1.0 | Train_distant_1.wav | far_train（12.0 秒目から 50.0 秒ぶん） |
| `siren_distant__fs469363.ogg` | https://freesound.org/people/brunoboselli/sounds/469363/ | brunoboselli | CC0 1.0 | Distant Ambulance Siren | far_siren（0.50 秒目から 21.0 秒ぶん） |
| `neighbors_wall__fs453486.ogg` | https://freesound.org/people/kyles/sounds/453486/ | kyles | CC0 1.0 | neighbours neighbors noisy heard through wall talking moving bumps  quebecois voices +door slam hallway Montreal, Canada.flac | m_neighbors（ループ・20.0 秒目から 60.0 秒ぶん） |
| `ir_outdoor__fs816877.ogg` | https://freesound.org/people/newlocknew/sounds/816877/ | newlocknew | CC0 1.0 | IR_Residential Area.5-Storey Residential Buildings 2_EM | 場所 outdoor の響き（インパルス応答。直接音の前を落とし 1.6 秒で切って、この場所の一発の音に畳み込む） |
| `ir_corridor__fs732132.ogg` | https://freesound.org/people/djericmark/sounds/732132/ | djericmark | CC0 1.0 | GARAGE 0.78s CORRIDOR-STAIRS IR REVERB | 場所 corridor の響き（インパルス応答。直接音の前を落とし 1.6 秒で切って、この場所の一発の音に畳み込む） |
| `ir_stairwell__fs818246.ogg` | https://freesound.org/people/thesummerblues1984/sounds/818246/ | thesummerblues1984 | CC0 1.0 | Stairwell impulse response | 場所 stairs の響き（インパルス応答。直接音の前を落とし 1.6 秒で切って、この場所の一発の音に畳み込む） |
| `ir_bedroom__fs465296.ogg` | https://freesound.org/people/Fission9/sounds/465296/ | Fission9 | CC0 1.0 | Bedroom Impulse Response | 場所 room の響き（インパルス応答。直接音の前を落とし 1.6 秒で切って、この場所の一発の音に畳み込む） |
| `door_heavy_close__fs406197.ogg` | https://freesound.org/people/kyles/sounds/406197/ | kyles | CC0 1.0 | door metal big heavy close kinda slam thud echo offmic.wav | door_shut（0.00 秒目から 3.00 秒ぶん） |
| `door_front_latch__fs453959.ogg` | https://freesound.org/people/kyles/sounds/453959/ | kyles | CC0 1.0 | door front residential heavy open close latch lock squeak from inside.flac | door_open（10.90 秒目から 3.20 秒ぶん） |
| `step_carpet__fs234855.ogg` | https://freesound.org/people/mlsulli/sounds/234855/ | mlsulli | CC0 1.0 | Footsteps_Carpet.wav | step_tatami_1..4_<場所>（立ち上がり 1.28, 15.02, 16.99, 19.27 秒・0.38 秒ずつ） |
