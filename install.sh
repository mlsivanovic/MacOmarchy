#!/bin/zsh
# MacOmarchy installer — idempotent. See README.md "Files and setup".
set -eu

project_dir=${0:A:h}
mode=install
dry_run=0
assume_yes=0
skip_brew=0
skip_system=0
skip_launchagents=0

usage() {
  print "Usage: ./install.sh [--dry-run] [--yes] [--update] [--skip-brew] [--skip-system] [--skip-launchagents]"
  print "  --dry-run           print planned writes, change nothing"
  print "  --yes               non-interactive (Ghostty divergence keeps local file)"
  print "  --update            label the backup '-update' (used by update.sh)"
  print "  --skip-brew         skip 'brew bundle'"
  print "  --skip-system       skip Dock/Spaces/symbolic-hotkey settings"
  print "  --skip-launchagents skip LaunchAgent (re)loading"
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes|-y) assume_yes=1 ;;
    --update) mode=update ;;
    --skip-brew) skip_brew=1 ;;
    --skip-system) skip_system=1 ;;
    --skip-launchagents) skip_launchagents=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
  shift
done

log() { print "[mac-omarchy] $*"; }
die() { print -u2 "[mac-omarchy] ERROR: $*"; exit 1; }

# ---------------------------------------------------------------- preflight
(( dry_run )) && log "dry-run: no files, settings, or agents will be changed"
for cmd in git python3; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found in PATH"
done
if (( ! skip_brew )); then
  command -v brew >/dev/null 2>&1 || die "Homebrew not found — install from https://brew.sh, then re-run"
fi
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools missing — run 'xcode-select --install', then re-run"
log "macOS $(sw_vers -productVersion) · project $project_dir · mode $mode"

# ------------------------------------------------------------------- backup
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="$HOME/.config/mac-omarchy/backups/${timestamp}-${mode}"
hammerspoon_dir="$HOME/.hammerspoon"
ghostty_dst="$HOME/.config/ghostty/config.ghostty"
zed_settings="$HOME/.config/zed/settings.json"
vscode_settings="$HOME/Library/Application Support/Code/User/settings.json"

backup_one() { # $1 = live file; mirror its $HOME-relative path in the backup
  local src="$1"
  [[ -e "$src" ]] || return 0
  local dest="$backup_dir/home/${src#$HOME/}"
  mkdir -p "${dest:h}"
  cp -p "$src" "$dest"
}

if (( dry_run )); then
  log "would back up existing targets to $backup_dir"
else
  mkdir -p "$backup_dir/home" "$backup_dir/plists"
  backup_one "$hammerspoon_dir/init.lua"
  backup_one "$hammerspoon_dir/omarchy.lua"
  backup_one "$hammerspoon_dir/desktops.lua"
  backup_one "$hammerspoon_dir/tiler.lua"
  backup_one "$hammerspoon_dir/mission-control.lua"
  backup_one "$ghostty_dst"
  backup_one "$HOME/.config/zed/themes/catppuccin.json"
  backup_one "$zed_settings"
  backup_one "$vscode_settings"
  backup_one "$HOME/Library/LaunchAgents/local.mac-omarchy.hammerspoon.plist"
  backup_one "$HOME/Library/LaunchAgents/local.mac-omarchy.ghostty.plist"
  defaults export com.apple.dock "$backup_dir/plists/com.apple.dock.plist" >/dev/null 2>&1 || true
  defaults export com.apple.symbolichotkeys "$backup_dir/plists/com.apple.symbolichotkeys.plist" >/dev/null 2>&1 || true
  print "$backup_dir" > "$project_dir/backup-location.txt"
  log "backup: $backup_dir"
fi

# ------------------------------------------------------------- dependencies
if (( skip_brew )); then
  log "skipping brew bundle"
elif (( dry_run )); then
  log "would run: brew bundle --file=$project_dir/Brewfile"
else
  brew bundle --file="$project_dir/Brewfile"
fi

# --------------------------------------------------------- managed files
deploy() { # $1 = repo-relative source, $2 = absolute destination
  local src="$project_dir/$1" dst="$2"
  [[ -f "$src" ]] || die "missing source $src"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    log "unchanged $dst"
    return 0
  fi
  if (( dry_run )); then
    log "would copy $1 -> $dst"
    return 0
  fi
  mkdir -p "${dst:h}"
  cp -p "$src" "$dst"
  log "installed $dst"
}

deploy_hammerspoon() {
  deploy "config/hammerspoon/init.lua" "$hammerspoon_dir/init.lua"
  deploy "config/omarchy.lua"          "$hammerspoon_dir/omarchy.lua"
  deploy "config/desktops.lua"         "$hammerspoon_dir/desktops.lua"
  deploy "config/tiler.lua"            "$hammerspoon_dir/tiler.lua"
  deploy "config/mission-control.lua"  "$hammerspoon_dir/mission-control.lua"
  deploy "config/mocha.png"            "$hammerspoon_dir/omarchy-assets/mocha.png"
  deploy "config/latte.png"            "$hammerspoon_dir/omarchy-assets/latte.png"
  deploy "config/catppuccin-zed.json"  "$HOME/.config/zed/themes/catppuccin.json"
  deploy "config/local.mac-omarchy.hammerspoon.plist" "$HOME/Library/LaunchAgents/local.mac-omarchy.hammerspoon.plist"
  deploy "config/local.mac-omarchy.ghostty.plist"     "$HOME/Library/LaunchAgents/local.mac-omarchy.ghostty.plist"
}

deploy_ghostty() {
  local src="$project_dir/config/ghostty.config"
  if [[ ! -f "$ghostty_dst" ]]; then
    deploy "config/ghostty.config" "$ghostty_dst"
    return 0
  fi
  if cmp -s "$src" "$ghostty_dst"; then
    log "unchanged $ghostty_dst"
    return 0
  fi
  # Locally diverged: never overwrite silently.
  log "Ghostty config differs from repo:"
  diff -u "$ghostty_dst" "$src" || true
  if (( dry_run )); then
    log "would prompt keep-local vs overwrite (default keep-local)"
    return 0
  fi
  cp -p "$src" "$ghostty_dst.repo"
  log "repo version saved alongside as $ghostty_dst.repo"
  if (( assume_yes )) || [[ ! -t 0 ]]; then
    log "non-interactive: keeping local Ghostty config"
    return 0
  fi
  local answer=""
  read "answer?Keep local file? [Y/n] "
  if [[ "$answer" == [nN]* ]]; then
    cp -p "$src" "$ghostty_dst"
    log "installed repo Ghostty config (local copy is in $backup_dir)"
  else
    log "keeping local Ghostty config"
  fi
}

deploy_hammerspoon
deploy_ghostty

# ------------------------------------------------------------ editor merge
# Merge only the keys from config/editor-appearance.json; preserve other
# settings and, when already merged, leave the file (and its comments) alone.
if (( dry_run )); then
  log "would merge config/editor-appearance.json into Zed and VS Code settings (if present)"
else
  python3 - "$project_dir/config/editor-appearance.json" "$zed_settings" "$vscode_settings" <<'PY'
import json, re, sys
from pathlib import Path

def strip_jsonc(text):
    out, i, in_str = [], 0, False
    while i < len(text):
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < len(text):
                out.append(text[i + 1]); i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if c == '"': in_str = True; out.append(c); i += 1; continue
        if text.startswith("//", i):
            j = text.find("\n", i); i = len(text) if j < 0 else j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); i = len(text) if j < 0 else j + 2; continue
        out.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

def deep_merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        merged = dict(base)
        for k, v in overlay.items():
            merged[k] = deep_merge(merged[k], v) if k in merged else v
        return merged
    return overlay

appearance = json.loads(Path(sys.argv[1]).read_text())
for key, path in (("zed", Path(sys.argv[2])), ("vscode", Path(sys.argv[3]))):
    desired = appearance.get(key, {})
    if not path.exists():
        # Only create settings for an editor whose config dir already exists,
        # except Zed whose theme dir this installer just populated.
        if key == "vscode" and not path.parent.exists():
            print(f"[mac-omarchy] skip VS Code merge (not installed: {path.parent} missing)")
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(desired, indent=2) + "\n")
        print(f"[mac-omarchy] created editor settings {path}")
        continue
    try:
        current = json.loads(strip_jsonc(path.read_text()))
    except Exception as e:
        print(f"[mac-omarchy] WARNING: cannot parse {path} ({e}); skipping merge, file untouched")
        continue
    if deep_merge(current, desired) == current:
        print(f"[mac-omarchy] unchanged {path}")
    else:
        path.write_text(json.dumps(deep_merge(current, desired), indent=2) + "\n")
        print(f"[mac-omarchy] merged appearance keys into {path} (backup in backups dir; comments not preserved)")
PY
fi

# ------------------------------------------------------------ native module
if (( dry_run )); then
  log "would build space-move.so via bin/build-space-move"
elif [[ -d /Applications/Hammerspoon.app ]]; then
  "$project_dir/bin/build-space-move" "$hammerspoon_dir/bin"
  [[ -f "$hammerspoon_dir/bin/space-move.so" ]] || die "space-move.so was not built"
  log "built $hammerspoon_dir/bin/space-move.so"
else
  log "WARNING: /Applications/Hammerspoon.app missing; skipping native module build"
fi

# ----------------------------------------------------------- system settings
apply_system_settings() {
  defaults write com.apple.dock mru-spaces -bool false
  defaults write com.apple.spaces spans-displays -bool false
  python3 - "$HOME/Library/Preferences/com.apple.symbolichotkeys.plist" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    print("[mac-omarchy] no symbolichotkeys plist; skipping hotkey step")
    sys.exit(0)
try:
    data = plistlib.loads(p.read_bytes())
    keys = data.get("AppleSymbolicHotKeys", {})
    changed = False
    # Enable Move left/right a space (79-81); free Cmd+Shift+3/4 (28/30) for
    # window moves. Leave 29/31 (remapped screenshots) and all else untouched.
    for hid in ("79", "80", "81"):
        if hid in keys and keys[hid].get("enabled") is not True:
            keys[hid]["enabled"] = True; changed = True
    for hid in ("28", "30"):
        if hid in keys and keys[hid].get("enabled") is not False:
            keys[hid]["enabled"] = False; changed = True
    if changed:
        p.write_bytes(plistlib.dumps(data))
        print("[mac-omarchy] updated symbolic hotkeys 79-81 on, 28/30 off")
    else:
        print("[mac-omarchy] symbolic hotkeys already correct")
except Exception as e:
    print(f"[mac-omarchy] WARNING: hotkey step aborted, plist untouched: {e}")
PY
  killall Dock >/dev/null 2>&1 || true
  killall cfprefsd >/dev/null 2>&1 || true
  log "system settings applied (a logout may be needed for Space settings)"
}

if (( skip_system )); then
  log "skipping system settings"
elif (( dry_run )); then
  log "would set com.apple.dock mru-spaces=false, com.apple.spaces spans-displays=false, symbolic hotkeys 79-81 on / 28,30 off"
else
  apply_system_settings
fi

# -------------------------------------------------------------- LaunchAgents
load_agent() { # $1 = plist path, $2 = label
  local plist="$1" label="$2"
  if (( dry_run )); then
    log "would (re)load LaunchAgent $label"
    return 0
  fi
  launchctl bootout "gui/$UID/$label" >/dev/null 2>&1 || true
  if ! launchctl bootstrap "gui/$UID" "$plist" >/dev/null 2>&1; then
    launchctl load "$plist" >/dev/null 2>&1 || log "WARNING: could not load $label"
  fi
  launchctl list | grep -q "$label" && log "LaunchAgent loaded: $label" || log "WARNING: $label not listed by launchctl"
}

if (( skip_launchagents )); then
  log "skipping LaunchAgents"
else
  load_agent "$HOME/Library/LaunchAgents/local.mac-omarchy.hammerspoon.plist" "local.mac-omarchy.hammerspoon"
  load_agent "$HOME/Library/LaunchAgents/local.mac-omarchy.ghostty.plist" "local.mac-omarchy.ghostty"
fi

# ------------------------------------------------- permissions and reload
if (( dry_run )); then
  log "would check Hammerspoon Accessibility and reload its config"
else
  hs_bin=$(command -v hs || true)
  if [[ -n "$hs_bin" ]]; then
    if [[ "$("$hs_bin" -c 'hs.accessibilityState()' 2>/dev/null || true)" != "true" ]]; then
      log "Hammerspoon needs Accessibility: System Settings → Privacy & Security → Accessibility"
      open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
      if (( ! assume_yes )) && [[ -t 0 ]]; then
        read "REPLY?Grant Hammerspoon Accessibility, then press Return to continue (or Ctrl-C to stop) "
      else
        log "non-interactive: continuing without waiting for Accessibility"
      fi
    fi
    "$hs_bin" -c 'hs.reload()' >/dev/null 2>&1 || open -g -a Hammerspoon || true
    log "Hammerspoon reload requested"
  else
    open -g -a Hammerspoon >/dev/null 2>&1 || true
    log "hs CLI not found; opened Hammerspoon — use its Reload Config command if needed"
  fi
fi

log "done ($mode). Backup: ${backup_dir} (dry-run made no changes)"
