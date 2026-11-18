#!/usr/bin/env bash
# Install this project's addon into a local WoW client; saved variables are untouched.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
addons_dir="${WOW_ADDONS_DIR:-}"
if [[ -z "$addons_dir" && -f "$project_dir/.deploy-target" ]]; then
    IFS= read -r addons_dir < "$project_dir/.deploy-target" || true
fi
addons_dir="${addons_dir%/}"
[[ "$addons_dir" == */Interface/AddOns && -d "$addons_dir" ]] || {
    echo "Set WOW_ADDONS_DIR or .deploy-target to an existing Interface/AddOns folder." >&2
    exit 1
}
flags=(--recursive --links --times --delete --itemize-changes)
dry_run=false
for argument in "$@"; do
    case "$argument" in
        --dry-run) flags+=(--dry-run); dry_run=true ;;
        *) echo "Unknown argument: $argument" >&2; exit 1 ;;
    esac
done
target="$addons_dir/MediaLab"
[[ ! -L "$target" ]] || { echo "Refusing to replace a symlink: $target" >&2; exit 1; }
[[ ! -d "$target" || -f "$target/MediaLab.toc" ]] || {
    echo "Refusing to replace a folder without MediaLab.toc: $target" >&2; exit 1
}
rsync "${flags[@]}" "$project_dir/MediaLab/" "$target/"
if $dry_run; then echo "Dry run only; nothing was copied to $target."; exit 0; fi
echo "MediaLab installed at $target."
echo "Restart WoW if the addon is new; otherwise type /reload. Open it with /mlab."

