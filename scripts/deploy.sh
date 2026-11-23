#!/usr/bin/env bash
# Install this project's addons into a local WoW client; saved variables are untouched.
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
for addon in MediaLab MediaLab_Export MediaLab_Icons MediaLab_Models; do
    target="$addons_dir/$addon"
    [[ ! -L "$target" ]] || { echo "Refusing to replace a symlink: $target" >&2; exit 1; }
    [[ ! -d "$target" || -f "$target/$addon.toc" ]] || {
        echo "Refusing to replace a folder without $addon.toc: $target" >&2; exit 1
    }
    rsync "${flags[@]}" "$project_dir/$addon/" "$target/"
done
if $dry_run; then echo "Dry run only; nothing was copied to $addons_dir."; exit 0; fi
echo "MediaLab, MediaLab_Export, MediaLab_Icons and MediaLab_Models installed in $addons_dir."
echo "Restart WoW if an addon or file is new; otherwise type /reload. Open it with /mlab."
