#!/usr/bin/env bash
# Dev tool (Windows + Git Bash): regenerate the README pictures in docs/.
# Runs statusline.sh on demo data in a throwaway HOME (so no real paths end up
# in the pictures), renders the ANSI output with tools/render.ps1, and builds
# the glitch GIF with ffmpeg.
#
#   PLEX_DIR=/c/fonts/plex NERD_FONT=/c/fonts/MesloLGSNerdFont-Regular.ttf tools/make-shots.sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${PLEX_DIR:?set PLEX_DIR to a folder with IBMPlexMono-Regular.ttf and -Bold.ttf}"
: "${NERD_FONT:?set NERD_FONT to a Nerd Font .ttf}"
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed for the GIF"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
DEMO_HOME="$W/home"; REPO="$DEMO_HOME/code/neon-city"
mkdir -p "$REPO" "$DEMO_HOME/.claude"
git -C "$REPO" init -q -b main
printf 'night city\n' > "$REPO/README.md"
git -C "$REPO" -c user.name=demo -c user.email=demo@example.com add . >/dev/null
git -C "$REPO" -c user.name=demo -c user.email=demo@example.com commit -qm init
printf 'rain\n' >> "$REPO/README.md"      # one modified file -> dirty marker

NOW=$(date +%s)
json() {  # json CONTEXT% 5H% 7D%
  MSYS_NO_PATHCONV=1 jq -nc --arg cwd "$REPO" --argjson c "$1" --argjson f "$2" --argjson w "$3" --argjson n "$NOW" '{
    session_id: "demo", model: {display_name: "Opus 5.5"}, version: "2.3.1",
    workspace: {current_dir: $cwd}, context_window: {used_percentage: $c}, effort: {level: "high"},
    rate_limits: {five_hour: {used_percentage: $f, resets_at: ($n + 9000)},
                  seven_day: {used_percentage: $w, resets_at: ($n + 300000)}}}'
}
shot() {  # shot OUT BG [env...]: run the script, render one PNG
  local out="$1" bg="$2"; shift 2
  json 33 23 41 | env HOME="$DEMO_HOME" CC_TEMPLATE= "$@" bash "$ROOT/statusline.sh" > "$W/frame.ans"
  render "$W/frame.ans" "$out" "$bg" 0
}
render() {
  pwsh -NoProfile -File "$(cygpath -w "$ROOT/tools/render.ps1")" -AnsiFile "$(cygpath -w "$1")" -Out "$(cygpath -w "$2")" \
    -Background "$3" -Columns "$4" -PlexDir "$(cygpath -w "$PLEX_DIR")" -NerdFont "$(cygpath -w "$NERD_FONT")" >/dev/null
}

mkdir -p "$ROOT/docs"
shot "$ROOT/docs/breach.png"         '#050508' CC_THEME=breach CC_ICONS=netrunner CC_TEXT=cool CC_MOTION=min
shot "$ROOT/docs/breach-plain.png"   '#050508' CC_THEME=breach CC_ICONS=slash CC_TEXT=gray CC_MOTION=min
shot "$ROOT/docs/replicant.png"      '#05090b' CC_THEME=replicant CC_MOTION=min
shot "$ROOT/docs/rghton.png"         '#0c0c0c' CC_THEME=monokai

# levels: fine / warning / critical, header-less
for lv in "33 23 41" "76 72 41" "94 93 41"; do
  set -- $lv
  json "$1" "$2" "$3" | env HOME="$DEMO_HOME" CC_THEME=breach CC_ICONS=netrunner CC_TEXT=cool CC_MOTION=min bash "$ROOT/statusline.sh" | sed -n '3,4p'
done > "$W/levels.ans"
render "$W/levels.ans" "$ROOT/docs/breach-levels.png" '#050508' 0

# glitch GIF: real FULL-motion runs, one frame each
mkdir -p "$W/gif"; i=0; glitches=0
while [ "$i" -lt 14 ]; do
  json 33 23 41 | env HOME="$DEMO_HOME" CC_THEME=breach CC_ICONS=netrunner CC_TEXT=cool CC_MOTION=full bash "$ROOT/statusline.sh" > "$W/g.ans"
  # alternate frames with the sign intact (calm, or a colour glitch) and frames
  # where letters moved or broke, so a short GIF shows the effect
  calm=0; sed 's/\x1b\[[0-9;]*m//g' "$W/g.ans" | head -1 | grep -q 'BREACH_PROTOCOL' && calm=1
  want_calm=$(( i % 2 == 0 ))
  [ "$calm" = "$want_calm" ] || continue
  render "$W/g.ans" "$(printf '%s/gif/f%02d.png' "$W" "$i")" '#050508' 90
  i=$((i + 1))
done
ffmpeg -loglevel error -y -framerate 1.4 -i "$W/gif/f%02d.png" \
  -vf "scale=iw/2:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=none" \
  -loop 0 "$ROOT/docs/breach-glitch.gif"
ls -la "$ROOT/docs"
