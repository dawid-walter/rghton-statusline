#!/usr/bin/env bash
# Install the rghtON statusline for Claude Code on Linux / macOS (also WSL).
#
#   ./install.sh                         breach look, cool text, refresh every 3 s
#   ./install.sh --theme replicant
#   ./install.sh --icons netrunner       needs a Nerd Font in your terminal
#   ./install.sh --dry-run               show what would change, change nothing
#   ./install.sh --uninstall             put back what was there before
#
# Options: --theme breach|replicant|herdr|rghton  --icons slash|chip|bus|pixel|tag|
#          gauge|typo|arrow|netrunner|terminal  --text gray|cool|cyan
#          --motion full|min  --refresh SECONDS (0 = only on Claude Code events)
#          --claude-dir DIR (default ~/.claude)
#
# What it touches: <claude-dir>/rghton-statusline/ (the script, backups, state),
# the statusLine entry of <claude-dir>/settings.json (nothing else in that file),
# and the one-word option files <claude-dir>/statusline_{theme,icons,text,motion}.
set -eu

NAME=rghton-statusline
THEME=breach; ICONS=slash; TEXT=cool; MOTION=full; REFRESH=3
CLAUDE_DIR="$HOME/.claude"; DRY=0; UNINSTALL=0

die() { echo "error: $*" >&2; exit 1; }
in_list() { local v="$1"; shift; for x in "$@"; do [ "$x" = "$v" ] && return 0; done; return 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --theme)      THEME="${2:-}"; shift ;;
    --icons)      ICONS="${2:-}"; shift ;;
    --text)       TEXT="${2:-}"; shift ;;
    --motion)     MOTION="${2:-}"; shift ;;
    --refresh)    REFRESH="${2:-}"; shift ;;
    --claude-dir) CLAUDE_DIR="${2:-}"; shift ;;
    --dry-run)    DRY=1 ;;
    --uninstall)  UNINSTALL=1 ;;
    -h|--help)    sed -n '2,19p' "$0"; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
  shift
done

in_list "$THEME" breach replicant herdr rghton || die "--theme must be breach, replicant, herdr or rghton"
in_list "$ICONS" slash chip bus pixel tag gauge typo arrow netrunner terminal || die "unknown --icons $ICONS"
in_list "$TEXT" gray cool cyan || die "--text must be gray, cool or cyan"
in_list "$MOTION" full min || die "--motion must be full or min"
case "$REFRESH" in ''|*[!0-9]*) die "--refresh must be a whole number of seconds" ;; esac

command -v jq >/dev/null 2>&1 || die "jq is missing. Install it first: brew install jq  /  sudo apt install jq"
command -v git >/dev/null 2>&1 || echo "note: git is missing, the branch will not be shown"

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$CLAUDE_DIR/$NAME"
SETTINGS="$CLAUDE_DIR/settings.json"
STAMP="$(date +%Y%m%d-%H%M%S)"
OPTS="theme icons text motion"

run() { if [ "$DRY" = 1 ]; then echo "would: $*"; else "$@"; fi; }
say() { echo "$*"; }

write_settings() {  # write_settings JQ_FILTER [jq args...]: rewrite settings.json through jq
  local filter="$1"; shift
  local src="$SETTINGS"; [ -f "$src" ] || src=/dev/null
  if [ "$DRY" = 1 ]; then
    echo "would set in $SETTINGS:"
    if [ -f "$SETTINGS" ]; then jq "$@" "$filter | {statusLine}" "$SETTINGS"; else jq -n "$@" "{} | $filter | {statusLine}"; fi
    return
  fi
  local tmp="$SETTINGS.tmp.$$"
  if [ -f "$SETTINGS" ]; then jq "$@" "$filter" "$SETTINGS" > "$tmp"; else jq -n "$@" "{} | $filter" > "$tmp"; fi
  mv "$tmp" "$SETTINGS"
}

if [ "$UNINSTALL" = 1 ]; then
  [ -d "$DEST" ] || die "nothing to uninstall: $DEST does not exist"
  if [ -f "$SETTINGS" ]; then
    run cp "$SETTINGS" "$DEST/backup/settings.$STAMP.before-uninstall.json"
    if [ -f "$DEST/previous-statusLine.json" ] && [ "$(cat "$DEST/previous-statusLine.json")" != "null" ]; then
      write_settings '.statusLine = $prev' --argjson prev "$(cat "$DEST/previous-statusLine.json")"
      say "statusLine: restored the one you had before"
    else
      write_settings 'del(.statusLine)'
      say "statusLine: removed (there was none before)"
    fi
  fi
  for o in $OPTS; do
    f="$CLAUDE_DIR/statusline_$o"; p="$DEST/previous-$o"
    if [ -f "$p" ]; then run cp "$p" "$f"; elif [ -f "$DEST/had-no-$o" ]; then run rm -f "$f"; fi
  done
  run rm -f "$DEST/statusline.sh" "$DEST/previous-statusLine.json" "$DEST"/previous-* "$DEST"/had-no-*
  say "uninstalled. Backups stay in $DEST/backup (delete the folder when you no longer need them)."
  exit 0
fi

# ── install ──────────────────────────────────────────────────────────────────
run mkdir -p "$DEST/backup"
run cp "$HERE/statusline.sh" "$DEST/statusline.sh"
run chmod +x "$DEST/statusline.sh"

# remember what was there before, only on the first install
if [ -f "$SETTINGS" ]; then
  run cp "$SETTINGS" "$DEST/backup/settings.$STAMP.json"
  if [ ! -f "$DEST/previous-statusLine.json" ]; then
    if [ "$DRY" = 1 ]; then echo "would save the current statusLine to $DEST/previous-statusLine.json"
    else jq '.statusLine // null' "$SETTINGS" > "$DEST/previous-statusLine.json"; fi
  fi
elif [ ! -f "$DEST/previous-statusLine.json" ]; then
  [ "$DRY" = 1 ] || echo null > "$DEST/previous-statusLine.json"
fi
for o in $OPTS; do
  f="$CLAUDE_DIR/statusline_$o"
  [ -f "$DEST/previous-$o" ] || [ -f "$DEST/had-no-$o" ] && continue
  if [ -f "$f" ]; then run cp "$f" "$DEST/previous-$o"; else run touch "$DEST/had-no-$o"; fi
done

# options
set_opt() {  # set_opt NAME VALUE (empty VALUE = remove the file, i.e. the default)
  local f="$CLAUDE_DIR/statusline_$1"
  if [ -z "$2" ]; then run rm -f "$f"
  elif [ "$DRY" = 1 ]; then echo "would write '$2' to $f"
  else printf '%s\n' "$2" > "$f"; fi
}
case "$THEME" in rghton) set_opt theme "" ;; *) set_opt theme "$THEME" ;; esac
set_opt icons "$ICONS"; set_opt text "$TEXT"; set_opt motion "$MOTION"

# settings.json: only the statusLine entry
CMD="bash \"$DEST/statusline.sh\""
write_settings '.statusLine = ({type: "command", command: $cmd, padding: 0} + (if $ri > 0 then {refreshInterval: $ri} else {} end))' \
  --arg cmd "$CMD" --argjson ri "$REFRESH"

if [ "$DRY" = 1 ]; then say "dry run: nothing was changed"; exit 0; fi
say "installed: theme $THEME, icons $ICONS, text $TEXT, motion $MOTION, refresh ${REFRESH}s"
say "Claude Code picks it up on the next refresh; restart open sessions if it does not."
