# ゲーム開発の入口。
#   make        … ゲームを起動する（ウィンドウが開く）
#   make help   … 共通の口の一覧（run / test / check / 描き出し / status …）
#   make palette … Studio 用の色の写し(assets/night_apartment.palette.json)を無条件に作り直す
#
# エンジンや java の場所はマシンごとに違うので、git に入れない local.mk に書く
# （make new-game / Studio が生成する。別のマシンで clone したら 1 度だけ書き直す）:
#   ENGINE := /abs/path/to/flix_game_engine   （Studio 同梱なら …/resources/engine）
#   JAVA   := /abs/path/to/java.exe           （Windows のみ。Studio 同梱 JRE の java.exe）
# 既定の ../.. は「テンプレを engine リポの中でそのまま動かす」ための値。
-include local.mk
ENGINE ?= ../..

# Studio 用の色の写し。入力（テーマ・sprite の Doc と、色を解く側のコード）が
# 写しより新しいときだけ作り直す。flix run は 1 回ごとにパッケージ全体をコンパイルし直すので、
# render のたびに無条件で走らせると、絵を描くのと同じだけのコンパイル時間を二重に払う。
# 入力の洗い出しに漏れがあったときは `make palette` で無条件に作り直す。
PALETTE      := assets/night_apartment.palette.json
PALETTE_DEPS := assets/night_apartment.theme.json assets/night_apartment.sprite.json \
                src/Palette.flix src/ThemeDoc.flix
# 描き出せる場面の名前（source of truth は SceneRender.shotNames。ここは使い方に出す写し）。
# 場面を足したら SceneRender.shotNames と一緒にここも足す。
SHOTS := wide vending corridor stairs loading quit volume

# ENGINE の場所が違うと include ごと落ち、make は「そんなファイルは無い」としか言わない。
# 先に自前で見て、直し方の 1 行を出してから止める（この検査が無いと make status も塞がる）。
ifeq ($(shell test -f "$(ENGINE)/mk/game.mk" && echo ok),)
$(error ENGINE が見当たりません ($(ENGINE)/mk/game.mk が無い) — local.mk に「ENGINE := /abs/path/to/flix_game_engine」を書くか、make <対象> ENGINE=... で指定してください。Studio 同梱なら …/resources/engine)
endif

# 共通の口（run / test / check / 描き出し / status …）はエンジンが持つ。
# 写しではないので、エンジンを上げると直しがそのまま届く。
# include は make の構文でクォートが効かず、空白でパスが分割される。
# Studio 同梱の engine は "/Applications/Flix GE Studio.app/…" と空白を含むので、
# 空白を退避してから渡す（レシピの中の $(ENGINE) は "" で括ってあるのでそのままでよい）。
space := $(subst ,, )
include $(subst $(space),\$(space),$(ENGINE))/mk/game.mk

# コミットで .flix か lint/ を触ったら、lint/rules.flix の決まり（依存の向き・View が World を受けない・テストの形）も見る。
# flixlint を取れない時（オフラインの初回など）は止めずに知らせる（make lint-flixlint で後から流せる）。
.PHONY: precommit-local
precommit-local:
	@if grep -qE '\.flix$$|^lint/' "$(STAGED_FILE)"; then \
	  fge=bin/fge; [ -x "$$fge" ] || fge="$(ENGINE)/bin/fge"; \
	  if "$$fge" flixlint-prepare > /dev/null; then $(MAKE) --no-print-directory lint-flixlint; \
	  else echo "[pre-commit] flixlint を用意できないので lint/rules.flix の検査は飛ばします（後で make lint-flixlint）"; fi; \
	fi

# 夜のアパートを歩く紹介の動画 = debug/video/tour.mp4（960×540）。手順は e2e/tour.flow（撮るのは mark in_ / out_ の間だけ）。
# 手順と出力の名前は替えられる: make video FLOW=e2e/stills.flow OUT=stills
VIDEO_FLOW = $(or $(FLOW),e2e/tour.flow)
VIDEO_OUT = $(or $(OUT),tour)
VIDEO_FPS ?= 30
VIDEO_X264 ?= -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p
.PHONY: video
video:
	rm -rf debug/video/$(VIDEO_OUT) debug/video/$(VIDEO_OUT).mp4
	VIDEO_FPS=$(VIDEO_FPS) VIDEO_FLOW=$(VIDEO_FLOW) VIDEO_OUT=$(VIDEO_OUT) VIDEO_X264="$(VIDEO_X264)" $(HEADLESS_RUN) VideoRender.frames
	@if [ -f debug/video/$(VIDEO_OUT)/f0000.png ]; then \
	  ffmpeg -y -loglevel error -framerate $(VIDEO_FPS) -i debug/video/$(VIDEO_OUT)/f%04d.png \
	    -f f64be -ar 44100 -ac 2 -i debug/video/$(VIDEO_OUT)/audio.f64 $(VIDEO_X264) -c:a aac -b:a 160k -shortest \
	    -movflags +faststart debug/video/$(VIDEO_OUT).mp4; fi
	@echo "[video] debug/video/$(VIDEO_OUT).mp4"

# GPU で塗った静止画（静止画の目標と同じ構図）= debug/stills/*.png。e2e/stills.flow の各構図で 1 秒ずつ撮り、各区間の最後のコマを抜く。
.PHONY: stills
stills:
	$(MAKE) --no-print-directory video FLOW=e2e/stills.flow OUT=stills VIDEO_FPS=10
	@mkdir -p debug/stills
	@n=0; for name in wide vending corridor stairs; do \
	  ffmpeg -y -loglevel error -i debug/video/stills.mp4 -vf "select=eq(n\\,$$((n*10+9)))" -vframes 1 debug/stills/$$name.png; n=$$((n+1)); done
	@echo "[stills] debug/stills/"

# 録音素材（assets/sfx/src/・出どころは assets/sfx/CREDITS.md）から音を作って assets/sfx/ へ書き、
# project.json の sounds を作った音の名前にそろえる（切り出し・正規化・場所ごとの響きの畳み込み・継ぎ目のないループ。
# 手順は tools/sfx_build.py。ffmpeg が要る。同じ素材なら何度流しても同じ WAV）。
.PHONY: sfx
sfx:
	python3 -I tools/sfx_build.py

# 2 階の部屋の中の 4 枚（Blender の書き出しだけで描いた目標 renders/game_check/room_*.png と同じ構図）= debug/stills/room_<番号>.png。
# 目標と左右に並べた絵を debug/compare/room_<番号>.png に置く（左 = ゲーム・右 = 目標）。目標の場所は ROOM_TARGETS で替えられる。
ROOM_TARGETS ?= /Users/abab/Desktop/horror_apartment/renders/game_check
.PHONY: room-stills
room-stills:
	$(MAKE) --no-print-directory video FLOW=e2e/room_stills.flow OUT=room_stills VIDEO_FPS=10
	@mkdir -p debug/stills debug/compare
	@n=0; for id in 202 203 204 205; do \
	  ffmpeg -y -loglevel error -i debug/video/room_stills.mp4 -vf "select=eq(n\\,$$((n*10+9)))" -vframes 1 debug/stills/room_$$id.png; \
	  if [ -f "$(ROOM_TARGETS)/room_$$id.png" ]; then \
	    ffmpeg -y -loglevel error -i debug/stills/room_$$id.png -i "$(ROOM_TARGETS)/room_$$id.png" \
	      -filter_complex "[0:v]scale=960:540[a];[1:v]scale=960:540[b];[a][b]hstack" debug/compare/room_$$id.png; fi; \
	  n=$$((n+1)); done
	@echo "[room-stills] debug/stills/room_*.png・debug/compare/room_*.png"

# 住人の 4 枚（Blender の書き出しだけで描いた目標 renders/people/<名前>_game.png と同じ構図・同じ動きの秒）= debug/stills/person_<名前>.png。
# 目標と左右に並べた絵を debug/compare/person_<名前>.png に置く（左 = ゲームの真ん中を 3:4 に切った物・右 = 目標）。
PEOPLE_TARGETS ?= /Users/abab/Desktop/horror_apartment/renders/people
.PHONY: people-stills
people-stills:
	$(MAKE) --no-print-directory video FLOW=e2e/people_stills.flow OUT=people_stills VIDEO_FPS=10
	@mkdir -p debug/stills debug/compare
	@n=0; for id in swayer headbanger stomper stairwalker; do \
	  ffmpeg -y -loglevel error -i debug/video/people_stills.mp4 -vf "select=eq(n\\,$$((n*10+9)))" -vframes 1 debug/stills/person_$$id.png; \
	  if [ -f "$(PEOPLE_TARGETS)/$${id}_game.png" ]; then \
	    ffmpeg -y -loglevel error -i debug/stills/person_$$id.png -i "$(PEOPLE_TARGETS)/$${id}_game.png" \
	      -filter_complex "[0:v]scale=960:540,crop=405:540[a];[1:v]scale=405:540[b];[a][b]hstack" debug/compare/person_$$id.png; fi; \
	  n=$$((n+1)); done
	@echo "[people-stills] debug/stills/person_*.png・debug/compare/person_*.png"
