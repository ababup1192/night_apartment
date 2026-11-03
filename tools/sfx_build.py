#!/usr/bin/env python3
"""夜のアパートの音を、録音素材（assets/sfx/src/）から assets/sfx/*.wav へ作る（make sfx）。

素材の出どころとライセンスは assets/sfx/CREDITS.md、素材の一覧表は assets/sfx/src/sources.tsv。
加工は ffmpeg だけで行う（切り出し・高い音や低い音を削る・正規化・響きの畳み込み・継ぎ目のないループ）。
同じ素材と同じ ffmpeg なら、何度流しても同じ WAV になる。

  一発の音  … 切り出して -1 dBFS のピークへそろえる。プレイヤーが鳴らす音は、場所ごと（屋外・外廊下・
              外階段・部屋）のインパルス応答で畳み込んだ版を <名前>_<場所>.wav として作る（エンジンには
              リアルタイムの響きが無いので、響きは書き出しの時に畳み込む）。
  ループ    … 素材の落ち着いた区間を切り、頭と尻を重ねて継ぎ目を消し、RMS をそろえる（ピークは -1 dBFS 以下）。
              smpl チャンク（ループ点 = 全体）を付ける。
"""
import array
import cmath
import glob
import math
import json
import os
import re
import shutil
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "sfx", "src")
OUT = os.path.join(ROOT, "assets", "sfx")
TMP = os.path.join(ROOT, "build", "sfx")
RATE = 44100
PEAK_DB = -1.0

# 響きを畳み込む場所: インパルス応答の素材・響きの大きさ（乾いた音の RMS からの dB）・高い音を削る所（Hz）。
SPACES = {
    "outdoor":  {"ir": "ir_outdoor",   "wet_db": -15.0, "lowpass": 7000},
    "corridor": {"ir": "ir_corridor",  "wet_db": -8.0,  "lowpass": 9000},
    "stairs":   {"ir": "ir_stairwell", "wet_db": -10.0, "lowpass": 8000},
    "room":     {"ir": "ir_bedroom",   "wet_db": -13.0, "lowpass": 9000},
}
ALL_SPACES = list(SPACES)


def shot(name, src, start, dur, af="", spaces=None, gain_db=0.0):
    return {"name": name, "src": src, "start": start, "dur": dur, "af": af, "spaces": spaces, "gain_db": gain_db}


def loop(name, layers, length, xfade=2.0, channels=2, rms_db=-26.0):
    return {"name": name, "layers": layers, "length": length, "xfade": xfade, "channels": channels, "rms_db": rms_db}


def layer(src, start, gain_db=0.0, af=""):
    return {"src": src, "start": start, "gain_db": gain_db, "af": af}


# 足音の切り出し: (素材, 立ち上がりの秒の列, 長さ, 足すフィルタ)
STEP_HP = "highpass=f=70,afftdn=nr=10:nf=-50"
FOOTSTEPS = {
    "concrete": ("step_concrete", [3.27, 8.69, 12.67, 18.15], 0.34, STEP_HP),
    "metal":    ("step_metal",    [0.88, 2.59, 4.21, 7.34],   0.60, STEP_HP),
    "dirt":     ("step_dirt",     [5.63, 7.40, 22.49, 8.76],  0.32, STEP_HP),
    "tatami":   ("step_carpet",   [1.28, 15.02, 16.99, 19.27], 0.38, STEP_HP + ",lowpass=f=3500"),
    "wood":     ("step_wood",     [1.29, 2.78, 4.76, 5.76],   0.40, STEP_HP),
}

SHOTS = []
for surface, (src, onsets, dur, af) in FOOTSTEPS.items():
    for i, t in enumerate(onsets, 1):
        SHOTS.append(shot(f"step_{surface}_{i}", src, t, dur, af, ALL_SPACES))

SHOTS += [
    # 玄関の鉄の扉: 開ける（ノブを回して掛け金が外れ、蝶番が軋む）・閉め始めの軋み・閉まり切った重い音
    shot("door_open", "door_front_latch", 10.90, 3.20, "highpass=f=60", ALL_SPACES),
    shot("door_creak", "door_metal_spring", 0.25, 2.55, "highpass=f=90,lowpass=f=6000", ALL_SPACES, -4.0),
    shot("door_shut", "door_heavy_close", 0.00, 3.00, "highpass=f=40", ALL_SPACES),
    # 手の灯りのスイッチ
    shot("flash_on", "flashlight_click2", 0.00, 0.20, "highpass=f=300", ALL_SPACES),
    shot("flash_off", "flashlight_click", 0.00, 0.26, "highpass=f=300", ALL_SPACES),
    # 外廊下の蛍光灯が瞬く時のジジッ（点滅の形が光った時に、近い管から）
    shot("fluo_zap_1", "fluo_buzzclicks", 0.45, 0.50, "highpass=f=120", ["corridor"]),
    shot("fluo_zap_2", "fluo_buzzclicks", 1.75, 0.50, "highpass=f=120", ["corridor"]),
    shot("fluo_zap_3", "fluo_buzzclicks", 2.95, 0.75, "highpass=f=120", ["corridor"]),
    shot("fluo_zap_4", "fluo_buzzclicks", 19.30, 0.60, "highpass=f=120", ["corridor"]),
    # 機械の一発: 室外機が回り出す・給湯器の点火
    shot("m_ac_start", "ac_startup", 0.00, 4.00, "highpass=f=40,afade=t=out:st=2.6:d=1.4", ["outdoor"]),
    shot("m_heater_ignite", "water_heater", 1.30, 4.70, "highpass=f=40,afade=t=out:st=3.4:d=1.3", ["corridor"]),
    # ごく稀な遠くの音（屋外の響きを付け、高い音を削って遠くに）
    shot("far_train", "train_distant", 12.0, 50.0, "highpass=f=50,lowpass=f=2500,afade=t=in:d=8,afade=t=out:st=38:d=12", ["outdoor"]),
    shot("far_siren", "siren_distant", 0.50, 21.0, "highpass=f=200,lowpass=f=3000,afade=t=in:d=4,afade=t=out:st=15:d=6", ["outdoor"]),
    # 住人: 壁越しに頭を打つ（鈍い）・地団駄（床を踏む・下の階へ低く響く）
    shot("p_headbanger_hit_1", "res_wall_thumps", 6.92, 0.85, "highpass=f=45,lowpass=f=1600", ["room"], 0.0),
    shot("p_headbanger_hit_2", "res_wall_thumps", 17.49, 0.85, "highpass=f=45,lowpass=f=1600", ["room"], 0.0),
    shot("p_headbanger_hit_3", "res_wall_thumps", 25.13, 0.85, "highpass=f=45,lowpass=f=1600", ["room"], 0.0),
    shot("p_stomper_stomp_l", "res_floor_stomps", 6.14, 0.65, "highpass=f=35,lowpass=f=2500", ["room"]),
    shot("p_stomper_stomp_r", "res_floor_stomps", 4.92, 0.65, "highpass=f=35,lowpass=f=2500", ["room"]),
    # 外階段の人の足音（面ごと）
    shot("p_stairwalker_step_steel_l", "step_metal2", 9.85, 0.50, "highpass=f=70", ["stairs"]),
    shot("p_stairwalker_step_steel_r", "step_metal2", 14.36, 0.50, "highpass=f=70", ["stairs"]),
    shot("p_stairwalker_step_concrete_l", "res_sneaker_stone", 5.36, 0.40, "highpass=f=70", ["stairs"]),
    shot("p_stairwalker_step_concrete_r", "res_sneaker_stone", 8.33, 0.40, "highpass=f=70", ["stairs"]),
    shot("p_stairwalker_step_ground_l", "step_dirt", 16.03, 0.30, "highpass=f=70", ["outdoor"]),
    shot("p_stairwalker_step_ground_r", "step_dirt", 22.49, 0.32, "highpass=f=70", ["outdoor"]),
]

# 住人と遠くの音は 1 つの場所の響きだけを畳み込み、名前に場所を付けない（鳴る場所が決まっているので）。
FIXED_SPACE = ("p_", "far_", "m_", "fluo_zap_")

LOOPS = [
    # 場所の環境音（ずっと小さく・低く）
    loop("amb_outdoor", [layer("amb_outdoor_traffic", 4.5, 0.0, "highpass=f=40,lowpass=f=9000"),
                         layer("amb_outdoor_crickets", 0.5, -7.0, "highpass=f=1500")], 38.0, 3.0, rms_db=-28.0),
    loop("amb_corridor", [layer("fluo_faulty", 5.5, 0.0, "highpass=f=60,lowpass=f=7000")], 11.5, 1.5, rms_db=-30.0),
    loop("amb_stairs", [layer("stairs_wind", 7.0, 0.0, "highpass=f=50,lowpass=f=5000")], 40.0, 4.0, rms_db=-28.0),
    loop("room_fridge", [layer("room_fridge", 17.5, 0.0, "highpass=f=35,lowpass=f=4000")], 20.0, 2.0, channels=1, rms_db=-30.0),
    loop("room_clock", [layer("room_clock", 49.5, 0.0, "highpass=f=300")], 12.0, 0.25, channels=1, rms_db=-32.0),
    loop("room_fan", [layer("room_fan", 48.5, 0.0, "highpass=f=60,lowpass=f=6000")], 20.0, 2.0, channels=1, rms_db=-30.0),
    # 置いてある物が鳴らす音（モノラル。音量は距離でゲームが決める）
    loop("m_ac_run_1", [layer("ac_exterior", 2.0, 0.0, "highpass=f=35")], 12.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_ac_run_2", [layer("ac_exterior", 15.0, 0.0, "highpass=f=35,asetrate=44100*0.96,aresample=44100")], 12.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_ac_run_3", [layer("ac_startup", 5.0, 0.0, "highpass=f=35")], 11.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_heater_burn_1", [layer("water_heater", 20.0, 0.0, "highpass=f=40")], 14.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_heater_burn_2", [layer("water_heater", 36.0, 0.0, "highpass=f=40,asetrate=44100*1.04,aresample=44100")], 14.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_vending", [layer("vending_hum", 26.5, 0.0, "highpass=f=40"),
                       layer("fluo_hum", 1.0, -9.0, "highpass=f=90")], 16.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_transformer", [layer("transformer", 20.5, 0.0, "highpass=f=45,lowpass=f=3000")], 12.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_wires", [layer("powerline_wind", 60.0, 0.0, "highpass=f=80")], 30.0, 4.0, channels=1, rms_db=-24.0),
    loop("m_hood", [layer("extractor_hood", 1.0, 0.0, "highpass=f=50,lowpass=f=4000")], 12.0, 2.0, channels=1, rms_db=-22.0),
    loop("m_neighbors", [layer("neighbors_wall", 20.0, 0.0, "highpass=f=80,lowpass=f=900")], 60.0, 4.0, channels=1, rms_db=-24.0),
]


def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"[sfx] ffmpeg が失敗: {' '.join(args)}\n{r.stderr[-2000:]}")
    return r


def ffmpeg(*args):
    return run(["ffmpeg", "-nostdin", "-hide_banner", "-v", "error", "-y", *args])


def source(key):
    hits = glob.glob(os.path.join(SRC, f"{key}__*.ogg"))
    if len(hits) != 1:
        sys.exit(f"[sfx] 素材 {key} が assets/sfx/src に 1 つだけ無い: {hits}")
    return hits[0]


def measure(path):
    """(RMS dB, ピーク dB)。全チャンネルを通した値。"""
    r = run(["ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-af", "astats=measure_perchannel=none", "-f", "null", "-"])
    rms = float(re.search(r"RMS level dB:\s*(-?[\d.]+|-inf)", r.stderr).group(1).replace("-inf", "-120"))
    peak = float(re.search(r"Peak level dB:\s*(-?[\d.]+|-inf)", r.stderr).group(1).replace("-inf", "-120"))
    return rms, peak


def gain(src, dst, db):
    ffmpeg("-i", src, "-af", f"volume={db:.3f}dB", "-ar", str(RATE), "-c:a", "pcm_s16le", dst)


WET_RATE = 22050   # 響きの成分は高い音を削るので、半分の速さで畳み込んで速くする
IR_MAX = 1.6       # 長い IR の尻（ほとんど雑音）は切る


def prepare_irs():
    """場所ごとの IR を、直接音の頭から WET_RATE のモノラルの列で返す。"""
    irs = {}
    for space, spec in SPACES.items():
        irs[space] = decode(source(spec["ir"]), WET_RATE,
                            f"silenceremove=start_periods=1:start_threshold=-45dB,atrim=end={IR_MAX},"
                            f"areverse,afade=t=in:d=0.2,areverse")
    return irs


def decode(path, rate, af=""):
    args = ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-ac", "1", "-ar", str(rate)]
    if af:
        args += ["-af", af]
    raw = subprocess.run(args + ["-f", "f32le", "-"], capture_output=True, check=True).stdout
    a = array.array("f")
    a.frombytes(raw)
    return list(a)


def encode(samples, rate, path):
    a = array.array("f", samples)
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "f32le", "-ar", str(rate), "-ac", "1", "-i", "-",
                    "-ar", str(RATE), "-c:a", "pcm_f32le", path], input=a.tobytes(), check=True)


def fft(x, inverse=False):
    n = len(x)
    if n == 1:
        return x
    even = fft(x[0::2], inverse)
    odd = fft(x[1::2], inverse)
    sign = 1 if inverse else -1
    tw = TWIDDLE.get((n, sign))
    if tw is None:
        tw = [cmath.exp(sign * 2j * math.pi * k / n) for k in range(n // 2)]
        TWIDDLE[(n, sign)] = tw
    t = [w * o for w, o in zip(tw, odd)]
    return [e + u for e, u in zip(even, t)] + [e - u for e, u in zip(even, t)]


TWIDDLE = {}
IR_SPECTRA = {}


def convolve(signal, space, ir):
    """FFT で畳み込む（ffmpeg 9.0.1 の afir は手元で無音を返したので使わない）。"""
    need = len(signal) + len(ir) - 1
    n = 1
    while n < need:
        n *= 2
    key = (space, n)
    if key not in IR_SPECTRA:
        IR_SPECTRA[key] = fft([complex(v) for v in ir] + [0j] * (n - len(ir)))
    spec = fft([complex(v) for v in signal] + [0j] * (n - len(signal)))
    out = fft([a * b for a, b in zip(spec, IR_SPECTRA[key])], inverse=True)
    return [v.real / n for v in out[:need]]


def build_shot(s, irs):
    dry = os.path.join(TMP, f"{s['name']}_dry.wav")
    fades = f"afade=t=in:d=0.004,afade=t=out:st={max(0.0, s['dur'] - 0.06):.3f}:d=0.06"
    chain = ",".join(x for x in (s["af"], fades) if x)
    cut = os.path.join(TMP, f"{s['name']}_cut.wav")
    ffmpeg("-ss", f"{s['start']:.3f}", "-t", f"{s['dur']:.3f}", "-i", source(s["src"]),
           "-ac", "1", "-ar", str(RATE), "-af", chain, "-c:a", "pcm_f32le", cut)
    if s["dur"] <= 1.0:
        # 立ち上がりの前の素材の雑音を落とす（踏んだ瞬間に鳴らないと足と音がずれて聞こえる）
        _, peak = measure(cut)
        ffmpeg("-i", cut, "-af", f"silenceremove=start_periods=1:start_threshold={peak - 30:.1f}dB:start_silence=0.008,afade=t=in:d=0.006",
               "-c:a", "pcm_f32le", dry)
    else:
        shutil.copy(cut, dry)
    fixed = s["name"].startswith(FIXED_SPACE)
    outs = []
    for space in (s["spaces"] or []):
        spec = SPACES[space]
        ir = irs[space]
        tail = len(ir) / WET_RATE
        padded = os.path.join(TMP, f"{s['name']}_{space}_pad.wav")
        wet = os.path.join(TMP, f"{s['name']}_{space}_wet.wav")
        ffmpeg("-i", dry, "-af", f"apad=pad_dur={tail:.3f}", "-c:a", "pcm_f32le", padded)
        raw_wet = os.path.join(TMP, f"{s['name']}_{space}_wetraw.wav")
        encode(convolve(decode(dry, WET_RATE), space, ir), WET_RATE, raw_wet)
        ffmpeg("-i", raw_wet, "-af", f"lowpass=f={spec['lowpass']}", "-c:a", "pcm_f32le", wet)
        dry_rms, _ = measure(dry)
        wet_rms, _ = measure(wet)
        wet_gain = 10 ** ((dry_rms + spec["wet_db"] - wet_rms) / 20)
        mixed = os.path.join(TMP, f"{s['name']}_{space}_mix.wav")
        ffmpeg("-i", padded, "-i", wet, "-filter_complex",
               f"[1:a]volume={wet_gain:.6f}[w];[0:a][w]amix=inputs=2:normalize=0:duration=longest,"
               "silenceremove=stop_periods=-1:stop_threshold=-70dB:stop_duration=0.2",
               "-c:a", "pcm_f32le", mixed)
        outs.append((s["name"] if fixed else f"{s['name']}_{space}", mixed))
    if not outs:
        outs.append((s["name"], dry))
    for name, path in outs:
        _, peak = measure(path)
        gain(path, os.path.join(OUT, f"{name}.wav"), PEAK_DB + s["gain_db"] - peak)
    return [n for n, _ in outs]


def build_loop(lp):
    n = int(round(lp["length"] * RATE))
    x = int(round(lp["xfade"] * RATE))
    total = (n + x) / RATE
    parts = []
    for i, ly in enumerate(lp["layers"]):
        seg = os.path.join(TMP, f"{lp['name']}_l{i}.wav")
        chain = ",".join(c for c in (ly["af"], f"volume={ly['gain_db']}dB") if c)
        ffmpeg("-ss", f"{ly['start']:.3f}", "-t", f"{total + 0.5:.3f}", "-i", source(ly["src"]),
               "-ac", str(lp["channels"]), "-ar", str(RATE), "-af", chain, "-c:a", "pcm_f32le", seg)
        parts.append(seg)
    seg = os.path.join(TMP, f"{lp['name']}_seg.wav")
    ins = sum((["-i", p] for p in parts), [])
    ffmpeg(*ins, "-filter_complex",
           f"{''.join(f'[{i}:a]' for i in range(len(parts)))}amix=inputs={len(parts)}:normalize=0:duration=longest,"
           f"atrim=end_sample={n + x}",
           "-c:a", "pcm_f32le", seg)
    looped = os.path.join(TMP, f"{lp['name']}_loop.wav")
    ffmpeg("-i", seg, "-filter_complex",
           f"[0:a]asplit=3[a][b][c];"
           f"[a]atrim=end_sample={x},asetpts=PTS-STARTPTS,afade=t=in:ss=0:ns={x}:curve=qsin[h];"
           f"[b]atrim=start_sample={n}:end_sample={n + x},asetpts=PTS-STARTPTS,afade=t=out:ss=0:ns={x}:curve=qsin[t];"
           f"[h][t]amix=inputs=2:normalize=0[j];"
           f"[c]atrim=start_sample={x}:end_sample={n},asetpts=PTS-STARTPTS[m];"
           f"[j][m]concat=n=2:v=0:a=1",
           "-c:a", "pcm_f32le", looped)
    rms, peak = measure(looped)
    db = min(lp["rms_db"] - rms, PEAK_DB - peak)
    dst = os.path.join(OUT, f"{lp['name']}.wav")
    gain(looped, dst, db)
    add_loop_points(dst)
    return lp["name"]


def add_loop_points(path):
    """WAV の後ろに smpl チャンク（全体を回るループ 1 本）を足す。"""
    data = bytearray(open(path, "rb").read())
    channels = struct.unpack_from("<H", data, 22)[0]
    frames = None
    pos = 12
    while pos + 8 <= len(data):
        cid, size = struct.unpack_from("<4sI", data, pos)
        if cid == b"data":
            frames = size // (2 * channels)
        pos += 8 + size + (size & 1)
    smpl = struct.pack("<9I", 0, 0, 1000000000 // RATE, 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
    data += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    struct.pack_into("<I", data, 4, len(data) - 8)
    open(path, "wb").write(bytes(data))


def register(names, loops):
    """project.json の sounds を作った音の名前にそろえる（論理名 = ファイル名の茎）。"""
    path = os.path.join(ROOT, "project.json")
    with open(path, encoding="utf-8") as f:
        project = json.load(f)
    project["sounds"] = [{"name": n, "path": f"assets/sfx/{n}.wav", "looping": n in loops} for n in sorted(names)]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(project, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main():
    if shutil.which("ffmpeg") is None:
        sys.exit("[sfx] ffmpeg が見つからない")
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    for old in glob.glob(os.path.join(OUT, "*.wav")):
        os.remove(old)
    irs = prepare_irs()
    names = []
    for s in SHOTS:
        names += build_shot(s, irs)
    for lp in LOOPS:
        names.append(build_loop(lp))
    register(names, {lp["name"] for lp in LOOPS})
    print(f"[sfx] {len(names)} 本 → assets/sfx/")


if __name__ == "__main__":
    main()
