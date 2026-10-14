# macOS with an Omarchy workflow

An Omarchy-inspired macOS setup built around native Spaces and Mission Control.
Hammerspoon handles tiling, a searchable command menu, keyboard shortcuts and mouse
gestures. Ghostty is the terminal.

## Keyboard shortcuts

**Control + Option** handles commands that conflict with standard macOS or application
shortcuts. Cmd+Space and Cmd+W retain their native behavior. Cmd+number and
Cmd+Shift+number are explicit exceptions that override application tab selection
and the default screenshot shortcuts.

| Shortcut | Action |
|---|---|
| Cmd + Return | Ghostty |
| Cmd + E | Finder |
| Cmd + Shift + Return | Google Chrome |
| Ctrl + Option + Space / K | Searchable command menu |
| Ctrl + Option + arrows | Focus a neighboring window on the current display |
| Ctrl + Option + L / Shift + L | Next / previous layout |
| Ctrl + Option + A / W | Tall / Wide |
| Ctrl + Option + F | Fill the working area with one window |
| Ctrl + Option + Shift + F | Floating layout for manual arrangement |
| Ctrl + Option + T | Toggle floating for the active window |
| Ctrl + Option + X | Exclude / include the focused app |
| Ctrl + Option + Shift + T | Enable / disable automatic tiling |
| Ctrl + Option + I / R | Show the layout / reflow windows |
| Ctrl + Option + Shift + ← / → | Swap with the previous / next window |
| Ctrl + Option + Shift + ↑ / ↓ | Move to the previous / next display |
| Ctrl + Option + M | Swap with the main window |
| Ctrl + Option + − / = | Shrink / expand the main pane |
| Cmd + 1–9 | Switch desktop on the focused window's display |
| Cmd + Shift + 1–9 | Move the window to a desktop on the same display and follow it |
| Cmd + scroll | Cycle desktops on the display under the pointer |
| Cmd + middle click | Mission Control |
| Cmd + Ctrl + scroll | Cycle windows on a display |
| Cmd + Ctrl + V | Clipboard history |
| F12 | Ghostty quick terminal |
| Cmd + Space | Native Spotlight |
| Cmd + W | Native window / tab closing |
| Screenshot in the command menu | Native screenshots / screen recording |

Cmd+number switches to an existing desktop. Cmd+Shift+number moves the active
window and follows it. If the destination does not exist, every missing desktop
up to that number is created. Moving from a display with two desktops to Desktop 5
creates desktops 3, 4 and 5. Creation briefly opens native Mission Control.
Desktop creation, window membership and the final active desktop are verified.

Desktop numbers are local to each display and skip fullscreen Spaces. Navigation
alone does not create desktops. Rapid keyboard navigation keeps the latest requested
destination. Cmd+scroll moves one desktop; further scroll events are ignored for one
second, and a second desktop is not queued while that transition is still running.
Moving affects the active window rather than all windows of its application. A failed
creation or move stops the operation and shows a notification.

Cmd+Shift+3/4/5 are reserved for moving windows. Screenshots and recording remain
available through the command menu or the macOS Screenshot app.

## Automatic tiling

- One standard window fills the working area with a 4 px outer margin.
- Windows have a 4 px gap between them.
- Two windows split the screen 50/50; additional windows stack in the secondary pane.
- Each display and each native desktop has its own arrangement.
- A window dragged to another display joins its active desktop and tiles with its windows.
- Tiling pauses while the left mouse button is held and resumes when dragging finishes.
- Window creation, closure, visibility and geometry events schedule tiling after a
  40 ms coalescing window. A 5-second fallback scan covers missed notifications.
- Tiling waits for desktop transfers and a short settling period after Space changes.
- Returning to a desktop preserves its window order and main pane.
- Windows that reject a requested size receive at most two attempts for an unchanged
  target and observed frame. Reflow (Ctrl + Option + R) explicitly retries.
- Layout cycle: Tall → Wide → Fullscreen → Floating.
- Dialogs, fullscreen/minimized windows, and explicitly floating windows do not
  occupy tiles.
- Hammerspoon, System Settings and KeePassXC are always excluded. Ctrl + Option + X
  excludes or includes the focused application, and the command menu action
  “Tiling — manage excluded apps” lists that app, the remembered apps and other
  running apps. Choices persist in `~/.config/mac-omarchy/tiling-excludes.json`
  (bundle id → name) and survive a Hammerspoon reload. Ctrl + Option + T still
  floats only the current window until reload.
- Existing native Shortcuts for arranging the last 2–4 windows are available from
  the menu after switching to Floating layout.

Cmd+scroll sends the real Dock shortcuts using keycodes and flags from the current
macOS settings. The pointer briefly moves to the destination display, then returns
unless the user has moved it. Enable **Move left/right a space** in
System Settings → Keyboard → Keyboard Shortcuts → Mission Control. Disable
**Automatically rearrange Spaces based on most recent use** and enable
**Displays have separate Spaces** for consistent per-display numbering.

Window movement uses a small local module calling the newer SkyLight bridged API
inside Hammerspoon, with its existing Accessibility permission. The result is
verified through actual Space membership. This uses a private macOS API without
Dock injection or SIP changes; validate it after major macOS upgrades. Do not run
Amethyst or Tiles alongside this tiler.

## Appearance and startup

The Catppuccin Mocha/Latte menu actions change the system appearance and wallpaper.
Ghostty, Zed and VS Code follow the system theme. The font is JetBrainsMono Nerd
Font Mono. Ghostty and Hammerspoon start at login using local LaunchAgents.

## Files and setup

Install or re-apply everything with the idempotent installer, and update an
existing checkout with the updater:

```sh
./install.sh            # first install or re-apply (safe to re-run)
./install.sh --dry-run  # print planned writes, change nothing
./update.sh             # git pull --ff-only, then re-run install.sh --update
```

The installer checks prerequisites (Homebrew, `git`, `python3`, Xcode Command
Line Tools), backs up existing targets (see Backups and rollback), runs
`brew bundle`, copies the managed files below, merges only the appearance keys
from `config/editor-appearance.json` into existing Zed/VS Code settings,
builds the native module with `bin/build-space-move` (requires Apple's
command-line developer tools and Hammerspoon in `/Applications`), applies the
Dock/Spaces and symbolic-hotkey settings described above, loads both
LaunchAgents, and reloads Hammerspoon. Hammerspoon's Accessibility permission
cannot be granted by script: the installer opens the System Settings pane and,
in an interactive terminal, waits for you to grant it. Useful flags:
`--yes` (non-interactive; a diverged Ghostty config is kept local and the repo
version is saved as `config.ghostty.repo` next to it), `--skip-brew`,
`--skip-system`, and `--skip-launchagents`. To do it manually instead, back up
existing settings, copy the files below yourself, and merge the editor
appearance settings into your existing configuration.

| Source | Active location / purpose |
|---|---|
| config/hammerspoon/init.lua | ~/.hammerspoon/init.lua |
| config/omarchy.lua, desktops.lua, tiler.lua, mission-control.lua | ~/.hammerspoon/ |
| config/hammerspoon/space-move.m | Source for the local native module |
| bin/build-space-move | Builds ~/.hammerspoon/bin/space-move.so |
| config/ghostty.config | ~/.config/ghostty/config.ghostty |
| config/catppuccin-zed.json | ~/.config/zed/themes/catppuccin.json |
| config/editor-appearance.json | Appearance settings to merge into editor settings |
| config/mocha.png, config/latte.png | ~/.hammerspoon/omarchy-assets/ |
| config/local.mac-omarchy.*.plist | ~/Library/LaunchAgents/ |

`config/legacy/` contains inactive Amethyst configuration and the older Spaces helper.
Build the native module with `./bin/build-space-move` (requires Apple's command-line
developer tools and Hammerspoon installed in `/Applications`). Reload the configuration
using Hammerspoon's **Reload Config** command.

Run the behavioral tests with Lua:

```sh
lua tests/tiler.lua
lua tests/desktops.lua
lua tests/mission-control.lua
lua tests/omarchy.lua
```

## Backups and rollback

Every `install.sh`/`update.sh` run first backs up the files it may replace to
`~/.config/mac-omarchy/backups/<timestamp>-install` (or `-update`), mirroring
their paths under `home/` and exporting the Dock and symbolic-hotkey plists
under `plists/`; the latest path is recorded in the gitignored
`backup-location.txt`. Local state is never overwritten or backed up as a
replacement target: `~/.hammerspoon/clipboard_history.json` and
`~/.config/mac-omarchy/tiling-excludes.json` are untouched. Clipboard history
is not included in this repository.

To roll back, copy the files from the backup's `home/` tree back over `$HOME`
(or restore the Hammerspoon configuration to `~/.hammerspoon/init.lua` and
reload it), restore the exported plists with `defaults import com.apple.dock
<backup>/plists/com.apple.dock.plist` and likewise for
`com.apple.symbolichotkeys`, and restore editor settings and your previous
system appearance/wallpaper as needed. Move the LaunchAgent files out of
`~/Library/LaunchAgents` and log out to remove their login startup behavior.
Existing applications are retained.
The disabled Amethyst LaunchAgent is stored locally at
`~/.config/mac-omarchy/local.mac-omarchy.amethyst.disabled.plist`.

## References

- [Hammerspoon](https://www.hammerspoon.org/docs/) — window, screen, Space and event APIs.
- [Hammerspoon issue 3897](https://github.com/Hammerspoon/hammerspoon/issues/3897) — macOS 27 Mission Control AX structure; the local adapter reads WindowManager.
- [Hammerspoon issue 3636](https://github.com/Hammerspoon/hammerspoon/issues/3636) — legacy moveWindowToSpace can report success without moving the window.
- [yabai Space manager](https://github.com/asmvik/yabai/blob/master/src/space_manager.c) — reference for the newer bridged Space API.
- [Catppuccin for Zed](https://github.com/catppuccin/zed) — theme, MIT license (see LICENSE.catppuccin).
- [Ghostty documentation](https://ghostty.org/docs/config) — terminal configuration.
