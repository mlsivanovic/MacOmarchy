#!/bin/zsh
# MacOmarchy updater — pull the latest revision, then re-apply install.sh.
set -eu
project_dir=${0:A:h}
cd "$project_dir"

command -v git >/dev/null 2>&1 || { print -u2 "[mac-omarchy] ERROR: 'git' not found in PATH"; exit 1; }
[[ -d "$project_dir/.git" ]] || { print -u2 "[mac-omarchy] ERROR: $project_dir is not a git checkout"; exit 1; }

if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "[mac-omarchy] ERROR: working tree has uncommitted changes; commit or stash them before updating:"
  git status --short >&2
  exit 1
fi

# Forward installer flags (--dry-run, --yes, --skip-*) after an optional `--`.
args=("$@")
if [[ "${args[1]:-}" == "--" ]]; then
  args=("${args[2,-1]}")
fi

print "[mac-omarchy] git pull --ff-only"
git pull --ff-only

exec "$project_dir/install.sh" --update "${args[@]}"
