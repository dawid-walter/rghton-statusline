#!/usr/bin/env bash
# rghtON statusline for Claude Code, by Dawid Walter. MIT licence.
# Requires: bash (3.2+; 4.2+ is faster), jq, git. Windows: Git Bash.
#
# Every option is a one-word file in ~/.claude (or an environment variable
# with the same effect for one session):
#
#   statusline_theme   (CC_THEME)   rghtON colour themes: monokai (default),
#                      dracula, nord, gruvbox, solarized, catppuccin,
#                      tokyo-night, one-dark, rose-pine, cyberpunk
#                      full looks:  breach (cyberpunk HUD with a glitching sign),
#                                   replicant (Blade Runner noir: neon sign, rain)
#                      herdr:       follow the theme of the layout shown in
#                                   herdr-app (breach-protocol / replicant,
#                                   anything else -> rghtON)
#   statusline_icons   (CC_ICONS)   breach line icons: slash (default), chip, bus,
#                      pixel, tag, gauge, typo, arrow; with a Nerd Font also
#                      netrunner, terminal
#   statusline_text    (CC_TEXT)    breach text colours: gray (default), cool, cyan
#   statusline_motion  (CC_MOTION)  full (default) or min: no glitch, rain, shimmer
#   statusline_timezone             zone for reset times (default: local time)
#   statusline_template (CC_TEMPLATE) rghtON header: rghtON (default), smootH
#
# breach / replicant read their colours from herdr-app's theme files when they
# exist (~/.config/herdr-app/themes/<name>.json, or $HERDR_APP_DIR), and use
# the same colours built in otherwise.

INPUT=$(cat)

# ── Parse JSON ──────────────────────────────────────────────────────────────
# One jq call for every field (each process start costs ~30 ms on Windows,
# which matters with statusLine.refreshInterval). Fields are split on \x1f so
# empty values survive.
IFS=$'\x1f' read -r MODEL VERSION CWD PCT COST DUR_MS API_MS L_ADD L_REM VIM_MODE EFFORT SESSION_ID \
  RL_5H RL_5H_RESET RL_7D RL_7D_RESET RL_SPEND RL_SPEND_RESET < <(
  printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // "Unknown"), (.version // "?"), (.workspace.current_dir // "."),
    ((.context_window.used_percentage // 0) | floor),
    (.cost.total_cost_usd // 0), (.cost.total_duration_ms // 0), (.cost.total_api_duration_ms // 0),
    (.cost.total_lines_added // 0), (.cost.total_lines_removed // 0),
    (.vim.mode // ""), (.effort.level // ""), (.session_id // ""),
    (.rate_limits.five_hour.used_percentage // ""), (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""), (.rate_limits.seven_day.resets_at // ""),
    (.rate_limits.spend_limit.used_percentage // ""), (.rate_limits.spend_limit.resets_at // "")
  ] | map(tostring) | join("\u001f")')
PCT=${PCT:-0}

# ── Portability: Git Bash (Windows), Linux, macOS (bash 3.2, BSD date) ───────
# Fast builtins where bash has them (EPOCHSECONDS / EPOCHREALTIME need 5.0,
# printf %()T needs 4.2); date(1) otherwise, GNU or BSD flavour.
NOW=${EPOCHSECONDS:-$(date +%s)}
if [ -n "${EPOCHREALTIME:-}" ]; then NOW_MS=${EPOCHREALTIME#*[.,]}; NOW_MS=$((10#${NOW_MS:0:3})); else NOW_MS=$((RANDOM % 1000)); fi
SL_TMP="${TMPDIR:-/tmp}"; SL_TMP="${SL_TMP%/}"
SL_FAST_T=0
if [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }; then SL_FAST_T=1; fi
[ -n "${SL_COMPAT:-}" ] && SL_FAST_T=0   # test hook: force the date(1) path
fmt_epoch() {  # fmt_epoch VAR epoch strftime [zone]: local time, or the zone if given
  local out=""
  if [ -z "${4:-}" ] && [ "$SL_FAST_T" = 1 ]; then printf -v "$1" "%($3)T" "$2"; return; fi
  if [ -z "${SL_DATE:-}" ]; then if date -d @0 +%s >/dev/null 2>&1; then SL_DATE=gnu; else SL_DATE=bsd; fi; fi
  if [ "$SL_DATE" = gnu ]; then
    if [ -n "${4:-}" ]; then out=$(TZ="$4" date -d "@$2" "+$3" 2>/dev/null); else out=$(date -d "@$2" "+$3" 2>/dev/null); fi
  else
    if [ -n "${4:-}" ]; then out=$(TZ="$4" date -r "$2" "+$3" 2>/dev/null); else out=$(date -r "$2" "+$3" 2>/dev/null); fi
  fi
  printf -v "$1" '%s' "$out"
}
# Directory for display. Home becomes ~ in both spellings (/c/Users/x and
# C:\Users\x on Windows). Backslashes are doubled because every line is printed
# with echo -e, which would read a Windows path's "\c" as "stop output" (losing
# the rest of the line and its newline) and "\t" as a tab.
display_path() {  # sets DISPLAY_PATH, no subshell
  local p="${CWD/#$HOME/\~}"
  [ -n "${USERPROFILE:-}" ] && p="${p/#"$USERPROFILE"/\~}"
  DISPLAY_PATH="${p//\\/\\\\}"
}

# ── Theme selection ───────────────────────────────────────────────────────────
THEME_FILE="$HOME/.claude/statusline_theme"
THEME="${CC_THEME:-}"
[ -z "$THEME" ] && [ -f "$THEME_FILE" ] && THEME=$(cat "$THEME_FILE" | tr -d '[:space:]')
[ -z "$THEME" ] && THEME="monokai"

# ── herdr: follow the theme of the layout shown in herdr-app ─────────────────
# THEME=herdr reads ~/.config/herdr-app/shared.json (active layout) and that
# layout's theme. replicant / breach-protocol get their own look; any other
# herdr theme falls back to monokai. Cached 5 s.
HERDR_DIR="${HERDR_APP_DIR:-$HOME/.config/herdr-app}"
[ "$THEME" = "breach" ] && THEME="breach-protocol"
if [ "$THEME" = "herdr" ]; then
  HCACHE="$SL_TMP/cc_statusline_herdr_theme"
  HTHEME=""; HTS=0
  [ -f "$HCACHE" ] && read -r HTS HTHEME < "$HCACHE"
  case "$HTS" in ''|*[!0-9]*) HTS=0 ;; esac
  if [ $(( NOW - HTS )) -gt 5 ]; then
    HTHEME=""
    LAY=$(jq -r '.layout // empty' "$HERDR_DIR/shared.json" 2>/dev/null)
    [ -n "$LAY" ] && HTHEME=$(jq -r '.theme | if type == "object" then (.dark // .light) else . end // empty' "$HERDR_DIR/layouts/$LAY.json" 2>/dev/null)
    echo "$NOW $HTHEME" > "$HCACHE"
  fi
  case "$HTHEME" in
    replicant|breach-protocol) THEME="$HTHEME" ;;
    *) THEME="monokai" ;;
  esac
fi

# ── Template selection ────────────────────────────────────────────────────────
TMPL_FILE="$HOME/.claude/statusline_template"
TMPL="${CC_TEMPLATE:-}"
[ -z "$TMPL" ] && [ -f "$TMPL_FILE" ] && TMPL=$(cat "$TMPL_FILE" | tr -d '[:space:]')
case "$THEME" in replicant|breach-protocol) [ -z "$TMPL" ] && TMPL="$THEME" ;; esac
[ -z "$TMPL" ] && TMPL="rghtON"

R='\033[0m'
BD='\033[1m'

case "$THEME" in
  dracula)
    # https://draculatheme.com/contribute
    PINK='\033[38;2;255;121;198m'    # #ff79c6  header
    YELLOW='\033[38;2;241;250;140m'  # #f1fa8c  czas
    GREEN='\033[38;2;80;250;123m'    # #50fa7b  katalog / sync
    CYAN='\033[38;2;139;233;253m'    # #8be9fd  branch
    ORANGE='\033[38;2;255;184;108m'  # #ffb86c  koszt
    RED='\033[38;2;255;85;85m'       # #ff5555  błędy
    PURPLE='\033[38;2;189;147;249m'  # #bd93f9  vim mode
    DIM='\033[38;2;98;114;164m'      # #6272a4  separatory
    ;;
  nord)
    # https://www.nordtheme.com/docs/colors-and-palettes
    PINK='\033[38;2;180;142;173m'    # #b48ead  header
    YELLOW='\033[38;2;235;203;139m'  # #ebcb8b  czas
    GREEN='\033[38;2;163;190;140m'   # #a3be8c  katalog / sync
    CYAN='\033[38;2;136;192;208m'    # #88c0d0  branch
    ORANGE='\033[38;2;208;135;112m'  # #d08770  koszt
    RED='\033[38;2;191;97;106m'      # #bf616a  błędy
    PURPLE='\033[38;2;180;142;173m'  # #b48ead  vim mode
    DIM='\033[38;2;76;86;106m'       # #4c566a  separatory
    ;;
  gruvbox)
    # https://github.com/morhetz/gruvbox
    PINK='\033[38;2;251;73;52m'      # #fb4934  header
    YELLOW='\033[38;2;250;189;47m'   # #fabd2f  czas
    GREEN='\033[38;2;184;187;38m'    # #b8bb26  katalog / sync
    CYAN='\033[38;2;142;192;124m'    # #8ec07c  branch
    ORANGE='\033[38;2;254;128;25m'   # #fe8019  koszt
    RED='\033[38;2;251;73;52m'       # #fb4934  błędy
    PURPLE='\033[38;2;211;134;155m'  # #d3869b  vim mode
    DIM='\033[38;2;146;131;116m'     # #928374  separatory
    ;;
  solarized)
    # https://ethanschoonover.com/solarized/
    PINK='\033[38;2;211;54;130m'     # #d33682  header
    YELLOW='\033[38;2;181;137;0m'    # #b58900  czas
    GREEN='\033[38;2;133;153;0m'     # #859900  katalog / sync
    CYAN='\033[38;2;42;161;152m'     # #2aa198  branch
    ORANGE='\033[38;2;203;75;22m'    # #cb4b16  koszt
    RED='\033[38;2;220;50;47m'       # #dc322f  błędy
    PURPLE='\033[38;2;108;113;196m'  # #6c71c4  vim mode
    DIM='\033[38;2;88;110;117m'      # #586e75  separatory
    ;;
  catppuccin)
    # https://github.com/catppuccin/catppuccin (Mocha)
    PINK='\033[38;2;203;166;247m'    # #cba6f7  mauve — header
    YELLOW='\033[38;2;249;226;175m'  # #f9e2af  yellow
    GREEN='\033[38;2;166;227;161m'   # #a6e3a1  green
    CYAN='\033[38;2;137;220;235m'    # #89dceb  sky
    ORANGE='\033[38;2;250;179;135m'  # #fab387  peach
    RED='\033[38;2;243;139;168m'     # #f38ba8  red
    PURPLE='\033[38;2;180;190;254m'  # #b4befe  lavender
    DIM='\033[38;2;108;112;134m'     # #6c7086  overlay
    ;;
  tokyo-night)
    # https://github.com/enkia/tokyo-night-vscode-theme
    PINK='\033[38;2;187;154;247m'    # #bb9af7  header
    YELLOW='\033[38;2;224;175;104m'  # #e0af68  yellow
    GREEN='\033[38;2;158;206;106m'   # #9ece6a  green
    CYAN='\033[38;2;125;207;255m'    # #7dcfff  cyan
    ORANGE='\033[38;2;255;158;100m'  # #ff9e64  orange
    RED='\033[38;2;247;118;142m'     # #f7768e  red
    PURPLE='\033[38;2;187;154;247m'  # #bb9af7  purple
    DIM='\033[38;2;86;95;137m'       # #565f89  dim
    ;;
  one-dark)
    # https://github.com/atom/atom (One Dark)
    PINK='\033[38;2;198;120;221m'    # #c678dd  header
    YELLOW='\033[38;2;229;192;123m'  # #e5c07b  yellow
    GREEN='\033[38;2;152;195;121m'   # #98c379  green
    CYAN='\033[38;2;86;182;194m'     # #56b6c2  cyan
    ORANGE='\033[38;2;209;154;102m'  # #d19a66  orange
    RED='\033[38;2;224;108;117m'     # #e06c75  red
    PURPLE='\033[38;2;198;120;221m'  # #c678dd  purple
    DIM='\033[38;2;92;99;112m'       # #5c6370  dim
    ;;
  rose-pine)
    # https://rosepinetheme.com (Main)
    PINK='\033[38;2;235;188;186m'    # #ebbcba  rose — header
    YELLOW='\033[38;2;246;193;119m'  # #f6c177  gold
    GREEN='\033[38;2;156;207;216m'   # #9ccfd8  foam
    CYAN='\033[38;2;156;207;216m'    # #9ccfd8  foam
    ORANGE='\033[38;2;246;193;119m'  # #f6c177  gold
    RED='\033[38;2;235;111;146m'     # #eb6f92  love
    PURPLE='\033[38;2;196;167;231m'  # #c4a7e7  iris
    DIM='\033[38;2;110;106;134m'     # #6e6a86  muted
    ;;
  cyberpunk)
    # Neon cyberpunk palette
    PINK='\033[38;2;255;0;124m'      # #ff007c  hot pink — header
    YELLOW='\033[38;2;243;249;157m'  # #f3f99d  neon yellow
    GREEN='\033[38;2;90;247;142m'    # #5af78e  neon green
    CYAN='\033[38;2;87;199;255m'     # #57c7ff  neon blue
    ORANGE='\033[38;2;255;108;193m'  # #ff6cc1  pink-orange
    RED='\033[38;2;255;92;87m'       # #ff5c57  neon red
    PURPLE='\033[38;2;157;101;255m'  # #9d65ff  electric purple
    DIM='\033[38;2;104;104;104m'     # #686868  dim
    ;;
  replicant)
    # Blade Runner noir — herdr "replicant" theme (Megagency palette)
    PINK='\033[38;2;255;46;136m'     # #ff2e88  magenta — alarm / calls
    YELLOW='\033[38;2;255;181;71m'   # #ffb547  amber — main neon
    GREEN='\033[38;2;255;181;71m'    # #ffb547  amber (no green in the city)
    CYAN='\033[38;2;155;92;255m'     # #9b5cff  violet — branch
    ORANGE='\033[38;2;255;90;31m'    # #ff5a1f  orange — warning
    RED='\033[38;2;255;46;136m'      # #ff2e88  magenta — danger
    PURPLE='\033[38;2;155;92;255m'   # #9b5cff  violet
    DIM='\033[38;2;110;86;100m'      # #6e5664  wet asphalt
    ;;
  monokai|*)
    # Monokai Pro (domyślny)
    PINK='\033[38;2;255;97;136m'     # #ff6188  header
    YELLOW='\033[38;2;255;216;102m'  # #ffd866  czas
    GREEN='\033[38;2;169;220;118m'   # #a9dc76  katalog / sync
    CYAN='\033[38;2;120;220;232m'    # #78dce8  branch
    ORANGE='\033[38;2;252;152;103m'  # #fc9867  koszt
    RED='\033[38;2;255;85;85m'       # #ff5555  błędy
    PURPLE='\033[38;2;171;157;242m'  # #ab9df2  vim mode
    DIM='\033[38;2;117;113;94m'      # #75715e  separatory
    ;;
esac

BLUE='\033[38;2;97;175;239m'  # #6197ef  directory path

S="${DIM}│${R}"  # separator

# ── rghtON: per-letter color + shimmer animation ──────────────────────────────
build_rghtON() {
  local text="rghtON"
  local ms=$NOW_MS
  local shimmer_pos=$(( (ms / 150) % 6 ))

  # Cyberpunk neon colors, one per letter
  local c0='\033[38;2;255;0;124m'    # r — hot pink
  local c1='\033[38;2;90;247;142m'   # g — neon green
  local c2='\033[38;2;87;199;255m'   # h — neon blue
  local c3='\033[38;2;243;249;157m'  # t — neon yellow
  local c4='\033[38;2;157;101;255m'  # O — electric purple
  local c5='\033[38;2;255;108;193m'  # N — pink-orange
  local shimmer='\033[38;2;255;255;255m\033[1m'  # bright white bold flash

  local colors=("$c0" "$c1" "$c2" "$c3" "$c4" "$c5")
  local result=""
  local i
  for i in 0 1 2 3 4 5; do
    local char="${text:$i:1}"
    if [ "$i" -eq "$shimmer_pos" ]; then
      result="${result}${shimmer}${char}${R}"
    else
      result="${result}${colors[$i]}${char}${R}"
    fi
  done
  echo -n "$result"
}

# ── Vim mode indicator ───────────────────────────────────────────────────────
VIM=""
case "$VIM_MODE" in
  NORMAL) VIM=" ${PURPLE}[NRM]${R}" ;;
  INSERT) VIM=" ${CYAN}[INS]${R}" ;;
esac

# ── Effort level indicator ───────────────────────────────────────────────────
EFFORT_LABEL=""
[ -n "$EFFORT" ] && EFFORT_LABEL=" ${DIM}(${ORANGE}${EFFORT}${DIM})${R}"

# ── Context bar (48 chars) ───────────────────────────────────────────────────
BAR_W=48
FILL=$(( PCT * BAR_W / 100 ))
[ "$FILL" -gt "$BAR_W" ] && FILL=$BAR_W
EMPTY=$(( BAR_W - FILL ))

if   [ "$PCT" -ge 90 ]; then BC="$RED"
elif [ "$PCT" -ge 70 ]; then BC="$ORANGE"
elif [ "$PCT" -ge 50 ]; then BC="$YELLOW"
else                         BC="$GREEN"; fi

BAR=""
i=0; while [ $i -lt $FILL ];  do BAR="${BAR}▰"; i=$((i+1)); done
i=0; while [ $i -lt $EMPTY ]; do BAR="${BAR}▱"; i=$((i+1)); done

# ── Git info (cached 5s for performance) ────────────────────────────────────
GIT_CACHE="$SL_TMP/cc_statusline_git_$(printf '%s' "$CWD" | cksum | cut -d' ' -f1)"
STALE=1; GKIND=""; GTS=0
[ -f "$GIT_CACHE" ] && IFS='|' read -r GTS GKIND BR MOD STG AHD BHD CMT_AGE < "$GIT_CACHE"
case "$GTS" in ''|*[!0-9]*) GTS=0 ;; esac
[ $(( NOW - GTS )) -le 5 ] && STALE=0

if [ "$STALE" = "1" ]; then
  if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    BR=$(git -C "$CWD" branch --show-current 2>/dev/null)
    MOD=$(git -C "$CWD" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    STG=$(git -C "$CWD" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    AHD=$(git -C "$CWD" rev-list @{u}..HEAD 2>/dev/null | wc -l | tr -d ' ')
    BHD=$(git -C "$CWD" rev-list HEAD..@{u} 2>/dev/null | wc -l | tr -d ' ')
    CMT_AGE=$(git -C "$CWD" log -1 --format="%ar" 2>/dev/null | sed 's/ ago//')
    GKIND=git
    printf "%s|git|%s|%s|%s|%s|%s|%s\n" \
      "$NOW" "$BR" "$MOD" "$STG" "${AHD:-0}" "${BHD:-0}" "$CMT_AGE" > "$GIT_CACHE"
  else
    GKIND=no
    echo "$NOW|no" > "$GIT_CACHE"
  fi
fi

GIT_BRANCH_SUFFIX=""
if [ "$GKIND" = git ]; then
  DIRTY=""
  [ "${MOD:-0}" -gt 0 ] || [ "${STG:-0}" -gt 0 ] && DIRTY="${YELLOW}*${R}"
  GIT_BRANCH_SUFFIX="  ${DIM}${S}${R}  ${CYAN} ${BR}${R}${DIRTY}"
fi

# ── Timing & cost ────────────────────────────────────────────────────────────
MINS=$(( DUR_MS / 60000 ))
SECS=$(( (DUR_MS % 60000) / 1000 ))
AMINS=$(( API_MS / 60000 ))
ASECS=$(( (API_MS % 60000) / 1000 ))
COST_FMT=$(awk "BEGIN{printf \"%.4f\", $COST}" 2>/dev/null || echo "0.0000")

# ── herdr templates: replicant (Blade Runner noir) / breach-protocol (rghtON in cyberpunk HUD colours)
# Colours come from the herdr theme file, so the status line matches the app.
# Written with as few subshells as possible: with statusLine.refreshInterval the
# script runs every second, and every fork costs ~10-30 ms on Windows.
# Self-contained; exits before the default lines.
if [ "$TMPL" = "replicant" ] || [ "$TMPL" = "breach-protocol" ]; then
  FLAVOR="$TMPL"
  # Built-in fallback = the theme files as shipped in the packages
  if [ "$FLAVOR" = "replicant" ]; then
    ACC=#ff9a3c SOL=#ffc58a HOT=#ff3d7f RNG=#5fbdb9 MUT=#7f8b8c DMC=#56625f OFF=#182a2c INKC=#ebe6dc DONE=#7fe0a6 BLU=#5a9fd4 VIO=#ff3d7f BBL=#8dc3ee BVI=#ff7aa8 BCY=#93dcd8
  else
    ACC=#fcee0a SOL=#fcee0a HOT=#ff003c RNG=#00f0ff MUT=#8d919c DMC=#7d8392 OFF=#1b3940 INKC=#f3f3ee DONE=#00e68a BLU=#3d8bff VIO=#d63bff BBL=#7ab0ff BVI=#e57dff BCY=#7ff8ff
  fi
  TF="$HERDR_DIR/themes/$FLAVOR.json"
  if [ -f "$TF" ]; then
    IFS=' ' read -r a s h g m d o k n bl vi b12 b13 b14 < <(jq -r '[.colors.accent, .colors.solid, .colors.blocked, .colors.ring, .colors.muted, .colors.dim, .colors.border, .colors.foreground, .colors.done, .ansi[4], .ansi[5], .ansi[12], .ansi[13], .ansi[14]] | map(. // "-") | join(" ")' "$TF" 2>/dev/null)
    ok() { [[ "$1" =~ ^#[0-9a-fA-F]{6}$ ]]; }
    ok "$a" && ACC=$a; ok "$s" && SOL=$s; ok "$h" && HOT=$h; ok "$g" && RNG=$g; ok "$m" && MUT=$m; ok "$d" && DMC=$d
    ok "$o" && OFF=$o; ok "$k" && INKC=$k; ok "$n" && DONE=$n; ok "$bl" && BLU=$bl; ok "$vi" && VIO=$vi; ok "$b12" && BBL=$b12; ok "$b13" && BVI=$b13; ok "$b14" && BCY=$b14
  fi
  fgv() { local x=${2#\#}; printf -v "$1" '\\033[38;2;%d;%d;%dm' $((16#${x:0:2})) $((16#${x:2:2})) $((16#${x:4:2})); }
  fgv C_ACC $ACC; fgv C_SOL $SOL; fgv C_HOT $HOT; fgv C_RNG $RNG; fgv C_MUT $MUT; fgv C_DIM $DMC
  fgv C_OFF $OFF; fgv C_INK $INKC; fgv C_OK $DONE; fgv C_BLU $BLU; fgv C_VIO $VIO; fgv C_BBL $BBL; fgv C_BVI $BVI; fgv C_BCY $BCY
  # "fine" level: replicant = light amber, breach = done green (like rghtON's green)
  if [ "$FLAVOR" = "replicant" ]; then C_LOW=$C_SOL; else C_LOW=$C_OK; fi
  lvlv() {  # lvlv VAR pct -> colour for fine / warning / critical
    if   (( $2 >= 90 )); then printf -v "$1" '%s' "$C_HOT"
    elif (( $2 >= 70 )); then printf -v "$1" '%s' "$C_ACC"
    else                      printf -v "$1" '%s' "$C_LOW"; fi
  }
  # Reset times in local time. A zone name is honoured only if zoneinfo has it
  # (Git Bash usually has none, and date would silently use UTC).
  RS_TZ="${TZ:-}"
  [ -z "$RS_TZ" ] && [ -f "$HOME/.claude/statusline_timezone" ] && read -r RS_TZ < "$HOME/.claude/statusline_timezone"
  [ -n "$RS_TZ" ] && [ ! -f "/usr/share/zoneinfo/$RS_TZ" ] && RS_TZ=""
  rtime() { fmt_epoch "$1" "$2" "$3" "$RS_TZ"; }  # rtime VAR epoch strftime

  MOTION="${CC_MOTION:-}"
  [ -z "$MOTION" ] && [ -f "$HOME/.claude/statusline_motion" ] && read -r MOTION < "$HOME/.claude/statusline_motion"
  [ "$MOTION" = "min" ] || MOTION="full"
  [ "$MOTION" = "min" ] && RANDOM=7   # decoration frozen in place
  MS=$NOW_MS

  # ── breach-protocol: rghtON's four lines, re-coloured from the herdr theme ──
  # Same order and wording as rghtON. Changes: colours from breach-protocol.json,
  # glyphs IBM Plex Mono has (no emoji / nerd-font branch / ▰▱). The six slashes
  # are a fixed strip of the whole palette. Only the BREACH_PROTOCOL sign moves:
  # in FULL about one refresh in three glitches (shift, split, corrupt or band),
  # always inside its own 15 characters, so nothing else on the line moves.
  # MIN: calm, no shimmer.
  if [ "$FLAVOR" = "breach-protocol" ]; then
    PAL=("$C_HOT" "$C_ACC" "$C_OK" "$C_RNG" "$C_BLU" "$C_VIO")
    # Text colours: CC_TEXT, else ~/.claude/statusline_text, else gray.
    # gray = original (white path, grey labels). cool / cyan colour the plain
    # text with non-signal hues only; green / yellow / red stay for the values.
    TEXTSET="${CC_TEXT:-}"
    [ -z "$TEXTSET" ] && [ -f "$HOME/.claude/statusline_text" ] && read -r TEXTSET < "$HOME/.claude/statusline_text"
    x=${RNG#\#}; printf -v C_DCY '\\033[38;2;%d;%d;%dm' $((16#${x:0:2} * 55 / 100)) $((16#${x:2:2} * 55 / 100)) $((16#${x:4:2} * 55 / 100))
    case "$TEXTSET" in
      cool) T_PATH=$C_BCY; T_LABEL="${BD}${C_BVI}"; T_LABEL2="${BD}${C_BVI}"; T_KEY=$C_BBL; T_NOTE=$C_BLU; T_DECO=$C_OFF ;;
      cyan) T_PATH=$C_BCY; T_LABEL="${BD}${C_RNG}"; T_LABEL2="${BD}${C_RNG}"; T_KEY=$C_RNG; T_NOTE=$C_DCY; T_DECO=$C_OFF ;;
      *)    T_PATH=$C_INK; T_LABEL="${BD}${C_MUT}"; T_LABEL2=$C_DIM; T_KEY=$C_MUT; T_NOTE=$C_DIM; T_DECO=$C_DIM ;;
    esac
    SLASH=""; for ((i = 0; i < 6; i++)); do SLASH="${SLASH}${PAL[$i]}/"; done
    WORD="BREACH_PROTOCOL"; WN=${#WORD}
    G=calm
    if [ "$MOTION" = "full" ] && [ $((RANDOM % 3)) -eq 0 ]; then
      case $((RANDOM % 4)) in 0) G=shift ;; 1) G=split ;; 2) G=corrupt ;; 3) G=band ;; esac
    fi
    # base colour per letter: yellow / cyan, "_" dim, one white shimmer (calm, FULL)
    SH=-1; [ "$MOTION" = "full" ] && [ "$G" = calm ] && SH=$(( (MS / 150) % WN ))
    GA=-1; GB=-1; GC=""; JUNK=(▓ ▒ ░ █ ▚ ▞ '#' '%')
    if [ "$G" = shift ] || [ "$G" = band ]; then
      GA=$((RANDOM % (WN - 4))); GB=$((GA + 2 + RANDOM % 4)); [ "$GB" -ge "$WN" ] && GB=$((WN - 1))
      if [ $((RANDOM % 2)) -eq 0 ]; then GC=$C_VIO; else GC=$C_OK; fi
    fi
    C1=$((RANDOM % WN)); C2=$((RANDOM % WN))
    W=""
    for ((i = 0; i < WN; i++)); do
      ch="${WORD:$i:1}"
      case "$G" in
        shift)    # a slice slips one place right: its letters show their left neighbour
          if [ "$i" -eq "$GA" ]; then W="${W}${C_DIM}▒"; continue; fi
          if [ "$i" -gt "$GA" ] && [ "$i" -le "$GB" ]; then W="${W}${BD}${GC}${WORD:$((i - 1)):1}${R}"; continue; fi ;;
        split)    # chromatic split: red / cyan
          if [ $((i % 2)) -eq 0 ]; then W="${W}${BD}${C_HOT}${ch}${R}"; else W="${W}${BD}${C_RNG}${ch}${R}"; fi; continue ;;
        corrupt)
          if [ "$i" -eq "$C1" ] || [ "$i" -eq "$C2" ]; then W="${W}${PAL[$((RANDOM % 6))]}${JUNK[$((RANDOM % 8))]}"; continue; fi ;;
        band)
          if [ "$i" -ge "$GA" ] && [ "$i" -le "$GB" ]; then W="${W}${BD}${GC}${ch}${R}"; continue; fi ;;
      esac
      if   [ "$i" -eq "$SH" ];     then W="${W}${BD}${C_INK}${ch}${R}"
      elif [ "$ch" = "_" ];        then W="${W}${C_DIM}_"
      elif [ $((i % 2)) -eq 0 ];   then W="${W}${BD}${C_ACC}${ch}${R}"
      else                              W="${W}${BD}${C_RNG}${ch}${R}"; fi
    done
    FILLER="${T_DECO}______________________________________"   # 38: header as wide as rghtON's
    BEFF=""; [ -n "$EFFORT" ] && BEFF=" ${T_NOTE}(${C_RNG}${EFFORT}${T_NOTE})${R}"
    BVIM=""
    case "$VIM_MODE" in
      NORMAL) BVIM=" ${C_RNG}[NRM]${R}" ;;
      INSERT) BVIM=" ${C_ACC}[INS]${R}" ;;
    esac
    # Icon set: CC_ICONS, else ~/.claude/statusline_icons, else "slash".
    # netrunner / terminal use Material Design Icons from a Nerd Font (not in
    # IBM Plex Mono; herdr falls back to an installed Nerd Font, e.g. MesloLGS NF).
    # Without a Nerd Font they show as boxes, so they are opt-in.
    ICONSET="${CC_ICONS:-}"
    [ -z "$ICONSET" ] && [ -f "$HOME/.claude/statusline_icons" ] && read -r ICONSET < "$HOME/.claude/statusline_icons"
    [ -z "$ICONSET" ] && ICONSET=slash
    I_MODEL=""; I_BR="↱"
    case "$ICONSET" in netrunner|terminal) I_MODEL="${C_ACC}󰚩 "; I_BR="󰘬" ;; esac
    echo -e "${SLASH}${R} ${BD}${C_ACC}CC·${VERSION}·${R}${W}${R} ${FILLER}${R} ${I_MODEL}${C_ACC}${MODEL}${R}${BEFF}${BVIM}"

    # Line icons: "slash" is the default. gauge, typo, arrow, chip, pixel, bus,
    # tag use only glyphs IBM Plex Mono has; netrunner, terminal need a Nerd Font.
    GAUGE=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
    printf -v P5 '%.0f' "${RL_5H:-0}"
    case "$ICONSET" in
      netrunner)  # server node, memory chip and power bolt lit by level; a skull when the 5h limit is near
             lvlv q "$PCT"; I_CTX="${q}󰍛"
             lvlv q "$P5"; if ((P5 >= 90)); then I_LIM="${C_HOT}󰚌"; else I_LIM="${q}󱐋"; fi
             I_DIR="${C_RNG}󰒋"; I_MOD="*" ;;
      terminal)  # console, memory module, hourglass
             lvlv q "$PCT"; I_CTX="${q}󰘚"; lvlv q "$P5"; I_LIM="${q}󰔟"
             I_DIR="${C_RNG}󰆍"; I_MOD="*" ;;
      slash) I_DIR="${C_HOT}//"; I_CTX="${C_ACC}//"; I_LIM="${C_RNG}//"; I_MOD="*" ;;
      gauge) k=$((PCT * 8 / 100)); ((k > 7)) && k=7; lvlv q "$PCT"; I_CTX="${q}${GAUGE[$k]}"
             k=$((P5 * 8 / 100)); ((k > 7)) && k=7; lvlv q "$P5"; I_LIM="${q}${GAUGE[$k]}"
             I_DIR="${C_ACC}▍"; I_MOD="±" ;;
      typo)  I_DIR="${C_RNG}§";  I_CTX="${C_RNG}∑"; I_LIM="${C_RNG}↻"; I_MOD="±" ;;
      arrow) I_DIR="${C_RNG}↳";  I_CTX="${C_RNG}⇄"; I_LIM="${C_RNG}↻"; I_MOD="*" ;;
      chip)  # netrunner hardware: data node, RAM chip (core = context level), power cells
             lvlv q "$PCT"; I_DIR="${C_RNG}╞${C_ACC}◊${C_RNG}╡"; I_CTX="${C_DIM}┫${q}█${C_DIM}┣"
             lvlv q "$P5"; n=$(( (P5 * 3 + 99) / 100 )); ((n < 1)) && n=1; ((n > 3)) && n=3
             I_LIM=""; CELL=(▂ ▄ ▆); for ((j = 0; j < 3; j++)); do if ((j < n)); then I_LIM="${I_LIM}${q}${CELL[$j]}"; else I_LIM="${I_LIM}${C_OFF}${CELL[$j]}"; fi; done
             I_MOD="*" ;;
      pixel) I_DIR="${C_RNG}▚▞"; I_CTX="${C_ACC}▙▟"; I_LIM="${C_VIO}▛▜"; I_MOD="*" ;;
      bus)   # a data bus running down from the header, nodes lit by level
             lvlv q "$PCT"; I_CTX="${C_RNG}┣━${q}◊"; lvlv q "$P5"; I_LIM="${C_RNG}┗━${q}◊"
             I_DIR="${C_RNG}┣━${C_ACC}◊"; I_MOD="*" ;;
      tag)   # solid HUD tags, dark text on palette colour
             printf -v TB '\\033[38;2;5;5;8m'
             I_DIR="${TB}\033[48;2;$((16#${RNG:1:2}));$((16#${RNG:3:2}));$((16#${RNG:5:2}))m NET \033[49m"
             I_CTX="${TB}\033[48;2;$((16#${ACC:1:2}));$((16#${ACC:3:2}));$((16#${ACC:5:2}))m MEM \033[49m"
             I_LIM="${TB}\033[48;2;$((16#${VIO:1:2}));$((16#${VIO:3:2}));$((16#${VIO:5:2}))m PWR \033[49m"
             I_MOD="*" ;;
      *)     I_DIR="${C_DIM}»";  I_CTX="${C_DIM}»"; I_LIM="${C_DIM}»"; I_MOD="*" ;;
    esac

    # Line 2: directory (+ branch)
    display_path
    L2="  ${I_DIR}${R} ${T_PATH}${DISPLAY_PATH}${R}"
    if [ -n "$GIT_BRANCH_SUFFIX" ]; then
      BDIRTY=""; { [ "${MOD:-0}" -gt 0 ] || [ "${STG:-0}" -gt 0 ]; } && BDIRTY="${C_ACC}${I_MOD}${R}"
      L2="${L2}  ${T_DECO}│${R}  ${C_RNG}${I_BR} ${BR}${R}${BDIRTY}"
    fi
    echo -e "$L2"

    # Line 3: context bar, 48 cells
    lvlv PC "$PCT"
    BF=$(( PCT * 48 / 100 )); [ "$BF" -gt 48 ] && BF=48
    printf -v ON '%*s' "$BF" ''; printf -v OFFC '%*s' $((48 - BF)) ''
    echo -e "  ${I_CTX}${R} ${T_LABEL}CONTEXT:${R} ${PC}${ON// /▌}${C_OFF}${OFFC// /▌}${R} ${BD}${PC}${PCT}%${R}"

    # Line 4: limits, worded like rghtON
    BU=()
    if [ -n "$RL_5H" ]; then
      printf -v P '%.0f' "$RL_5H"; rtime T "$RL_5H_RESET" '%H:%M'; lvlv q "$P"
      BU+=("${T_KEY}session(5h):${R}${q}${P}%${R}${T_NOTE}(reset ${T})${R}")
    fi
    if [ -n "$RL_7D" ]; then
      printf -v P '%.0f' "$RL_7D"; rtime T "$RL_7D_RESET" '%a %H:%M'; lvlv q "$P"
      BU+=("${T_KEY}weekly(7d):${R}${q}${P}%${R}${T_NOTE}(reset ${T})${R}")
    fi
    if [ -n "$RL_SPEND" ]; then
      printf -v P '%.0f' "$RL_SPEND"; rtime T "$RL_SPEND_RESET" '%a %H:%M'; lvlv q "$P"
      BU+=("${T_KEY}usage credit:${R}${q}${P}%${R}${T_NOTE}(reset ${T})${R}")
    fi
    if [ "${#BU[@]}" -gt 0 ]; then
      L4="  ${I_LIM}${R} ${T_LABEL2}LIMITS:${R} "
      for idx in "${!BU[@]}"; do
        [ "$idx" -gt 0 ] && L4="${L4} ${T_DECO}│${R} "
        L4="${L4}${BU[$idx]}"
      done
      echo -e "$L4"
    fi
    exit 0
  fi

  # ── replicant: neon sign + rain, SECTOR / MEMORY / LIFESPAN ──
  W_UNIT="UNIT"; W_DIR="SECTOR"; W_TAG="${C_ACC}中央区${R} "; W_BAR="MEMORY"; W_LIM="LIFESPAN"
  W_CTX_MAX="… like tears in rain"; W_LIM_MAX="TIME TO DIE"; CH_ON="━"; CH_OFF="─"
  # Neon sign; in FULL one tube sometimes flickers out
  SIGN="REPLICANT"; FLK=-1
  [ "$MOTION" = "full" ] && [ $((RANDOM % 3)) -eq 0 ] && FLK=$((RANDOM % 9))
  HEAD=""
  for ((i = 0; i < 9; i++)); do
    ch="${SIGN:$i:1}"
    if [ "$i" -eq "$FLK" ]; then HEAD="${HEAD}${C_DIM}${ch}${R}"; else HEAD="${HEAD}${BD}${C_ACC}${ch}${R}"; fi
    [ "$i" -lt 8 ] && HEAD="${HEAD} "
  done
  # Rain across the gap
  DECO=""
  for ((i = 0; i < 30; i++)); do
    case $((RANDOM % 9)) in
      0|1) DECO="${DECO}${C_RNG}╱" ;;
      2)   DECO="${DECO}${C_DIM}╱" ;;
      3)   DECO="${DECO}${C_OFF}·" ;;
      *)   DECO="${DECO} " ;;
    esac
  done

  EFF=""; [ -n "$EFFORT" ] && EFF=" ${C_DIM}·${R} ${C_ACC}${EFFORT}${R}"
  RVIM=""
  case "$VIM_MODE" in
    NORMAL) RVIM=" ${C_RNG}[NRM]${R}" ;;
    INSERT) RVIM=" ${C_ACC}[INS]${R}" ;;
  esac
  echo -e "${C_HOT}▌${R} ${HEAD}  ${DECO}${R}  ${C_MUT}${W_UNIT}${R} ${C_INK}${MODEL}${R}${EFF}  ${C_DIM}cc ${VERSION}${R}${RVIM}"

  # Directory + branch
  display_path
  SEC="  ${C_MUT}${W_DIR}${R} ${W_TAG}${C_ACC}${DISPLAY_PATH}${R}"
  if [ -n "$GIT_BRANCH_SUFFIX" ]; then
    RD=""; { [ "${MOD:-0}" -gt 0 ] || [ "${STG:-0}" -gt 0 ]; } && RD="${C_HOT}*${R}"
    SEC="${SEC}  ${C_DIM}│${R}  ${C_RNG}↱ ${BR}${R}${RD}"
  fi
  echo -e "$SEC"

  # Context bar: a neon tube heating along its length, solid -> accent -> blocked
  RW=48
  RF=$(( PCT * RW / 100 )); [ "$RF" -gt "$RW" ] && RF=$RW
  lvlv PC "$PCT"
  r1=$((16#${SOL:1:2})); g1=$((16#${SOL:3:2})); b1=$((16#${SOL:5:2}))
  r2=$((16#${ACC:1:2})); g2=$((16#${ACC:3:2})); b2=$((16#${ACC:5:2}))
  r3=$((16#${HOT:1:2})); g3=$((16#${HOT:3:2})); b3=$((16#${HOT:5:2}))
  TUBE=""
  for ((i = 0; i < RW; i++)); do
    if [ "$i" -lt "$RF" ]; then
      t=$(( i * 1000 / (RW - 1) ))
      if [ "$t" -lt 600 ]; then
        r=$(( r1 + (r2 - r1) * t / 600 )); g=$(( g1 + (g2 - g1) * t / 600 )); b=$(( b1 + (b2 - b1) * t / 600 ))
      else
        u=$(( t - 600 ))
        r=$(( r2 + (r3 - r2) * u / 400 )); g=$(( g2 + (g3 - g2) * u / 400 )); b=$(( b2 + (b3 - b2) * u / 400 ))
      fi
      TUBE="${TUBE}\033[38;2;${r};${g};${b}m${CH_ON}"
    else
      TUBE="${TUBE}${C_OFF}${CH_OFF}"
    fi
  done
  MAXT=""; [ "$PCT" -ge 90 ] && MAXT="  ${C_HOT}${W_CTX_MAX}${R}"
  echo -e "  ${C_MUT}${W_BAR}${R} ${TUBE}${R} ${BD}${PC}${PCT}%${R}${MAXT}"

  # Usage limits
  LP=(); DIE=""
  if [ -n "$RL_5H" ]; then
    printf -v P '%.0f' "$RL_5H"; rtime T "$RL_5H_RESET" '%H:%M'; lvlv q "$P"
    LP+=("${C_MUT}5h${R} ${q}${P}%${R} ${C_DIM}→ ${T}${R}")
    [ "$P" -ge 90 ] && DIE="  ${BD}${C_HOT}${W_LIM_MAX}${R}"
  fi
  if [ -n "$RL_7D" ]; then
    printf -v P '%.0f' "$RL_7D"; rtime T "$RL_7D_RESET" '%a %H:%M'; lvlv q "$P"
    LP+=("${C_MUT}7d${R} ${q}${P}%${R} ${C_DIM}→ ${T}${R}")
  fi
  if [ -n "$RL_SPEND" ]; then
    printf -v P '%.0f' "$RL_SPEND"; rtime T "$RL_SPEND_RESET" '%a %H:%M'; lvlv q "$P"
    LP+=("${C_MUT}credit${R} ${q}${P}%${R} ${C_DIM}→ ${T}${R}")
  fi
  if [ "${#LP[@]}" -gt 0 ]; then
    LINE="  ${C_MUT}${W_LIM}${R}  "
    for idx in "${!LP[@]}"; do
      [ "$idx" -gt 0 ] && LINE="${LINE}  ${C_DIM}│${R}  "
      LINE="${LINE}${LP[$idx]}"
    done
    echo -e "${LINE}${DIE}"
  fi
  exit 0
fi

# ── Print status lines ───────────────────────────────────────────────────────

# Header template
case "$TMPL" in
  smootH)
    echo -e "${DIM}__///${R}${BD}${PINK}AI STATUSLINE CC${R} ${DIM}v${VERSION}${R} ${DIM}______________________________________${R} ${YELLOW}${MODEL}${R}${EFFORT_LABEL}${VIM}"
    ;;
  rghtON|*)
    RGHTON=$(build_rghtON)
    echo -e "\033[38;2;255;85;85m/\033[38;2;255;152;103m/\033[38;2;255;216;102m/\033[38;2;169;220;118m/\033[38;2;120;220;232m/\033[38;2;171;157;242m/${R} ${BD}${RED}CC·${VERSION}·${RGHTON}·STATUSLINE${R} ${DIM}____________________________________${R} ${YELLOW}${MODEL}${R}${EFFORT_LABEL}${VIM}"
    ;;
esac

# Line 2: Directory (+ git branch, if inside a repo)
display_path
echo -e "  ${DIM}📂${R} ${BLUE}${DISPLAY_PATH}${R}${GIT_BRANCH_SUFFIX}"

# Line 3: Context bar
echo -e "  📊 ${BD}${DIM}CONTEXT:${R} ${BC}${BAR}${R} ${BD}${BC}${PCT}%${R}"

# ── Line 6: Usage limits (5h / 7d / spend) ──────────────────────────────────
# Timezone for reset times: $TZ env, else ~/.claude/statusline_timezone, else local time
TZ_FILE="$HOME/.claude/statusline_timezone"
DISPLAY_TZ="${TZ:-}"
[ -z "$DISPLAY_TZ" ] && [ -f "$TZ_FILE" ] && DISPLAY_TZ=$(cat "$TZ_FILE" | tr -d '[:space:]')
# Git Bash has no zoneinfo, so a zone name like Europe/Warsaw silently meant
# UTC (reset times an hour early). Use a name only if zoneinfo has it,
# otherwise the system's local time.
[ -n "$DISPLAY_TZ" ] && [ ! -f "/usr/share/zoneinfo/$DISPLAY_TZ" ] && DISPLAY_TZ=""

fmt_reset_time() {
  local ts="$1"
  [ -z "$ts" ] && return
  local t; fmt_epoch t "$ts" '%H:%M' "$DISPLAY_TZ"; printf '%s' "$t"
}

fmt_reset_daytime() {
  local ts="$1"
  [ -z "$ts" ] && return
  local t; fmt_epoch t "$ts" '%a %H:%M' "$DISPLAY_TZ"; printf '%s' "$t"
}

pct_color() {
  local p="$1"
  local pi; pi=$(awk "BEGIN{printf \"%d\", $p}")
  if   [ "$pi" -ge 90 ]; then echo "$RED"
  elif [ "$pi" -ge 70 ]; then echo "$ORANGE"
  elif [ "$pi" -ge 50 ]; then echo "$YELLOW"
  else                        echo "$GREEN"; fi
}

USAGE_PARTS=()

if [ -n "$RL_5H" ]; then
  C=$(pct_color "$RL_5H")
  RS=$(fmt_reset_time "$RL_5H_RESET")
  P=$(awk "BEGIN{printf \"%.0f\", $RL_5H}")
  USAGE_PARTS+=("${DIM}session(5h):${R}${C}${P}%${R}${DIM}(reset ${RS})${R}")
fi

if [ -n "$RL_7D" ]; then
  C=$(pct_color "$RL_7D")
  RS=$(fmt_reset_daytime "$RL_7D_RESET")
  P=$(awk "BEGIN{printf \"%.0f\", $RL_7D}")
  USAGE_PARTS+=("${DIM}weekly(7d):${R}${C}${P}%${R}${DIM}(reset ${RS})${R}")
fi

if [ -n "$RL_SPEND" ]; then
  C=$(pct_color "$RL_SPEND")
  RS=$(fmt_reset_daytime "$RL_SPEND_RESET")
  P=$(awk "BEGIN{printf \"%.0f\", $RL_SPEND}")
  USAGE_PARTS+=("${DIM}usage credit:${R}${C}${P}%${R}${DIM}(reset ${RS})${R}")
fi

if [ "${#USAGE_PARTS[@]}" -gt 0 ]; then
  LINE="  ${DIM}⏳ LIMITS:${R} "
  for idx in "${!USAGE_PARTS[@]}"; do
    [ "$idx" -gt 0 ] && LINE="${LINE} ${S} "
    LINE="${LINE}${USAGE_PARTS[$idx]}"
  done
  echo -e "$LINE"
fi

exit 0
