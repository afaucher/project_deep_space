# import_check.sh - Bash port of import_check.ps1. Detect and fix stale Godot
# import caches before a headless run. Source this from a caller that has set
# PROJECT_ROOT and GODOT_PATH, then call: import_if_stale
#
# Godot's headless CLI (--run-test, --check-only, etc.) trusts whatever is
# already sitting in .godot/imported/*.tres -- it does NOT compare source
# mtimes and reimport on load the way the editor's filesystem watcher does.
# Only an explicit `--headless --import` pass (or opening the project in the
# actual editor) regenerates that cache. So hand-editing any imported asset
# (a .dialogue file, most concretely -- see the M39 docking dialogue loop
# fix) outside the editor leaves every headless test silently running
# against the OLD compiled resource until someone thinks to reimport.
#
# Same logic as the PowerShell version: scan every *.import sidecar; mtime
# pre-filter catches candidates; source_md5 in the .md5 sidecar confirms
# real content changes so a plain `git checkout` (which touches mtimes
# without changing content) doesn't trigger a permanent reimport loop.

_imports_stale() {
    local project_root="$1"

    # A brand-NEW imported-type asset has no .import sidecar yet, so the
    # sidecar scan below can't see it. Check hand-authored imported
    # extensions (.dialogue is the only one in this project) up front.
    while IFS= read -r -d '' src; do
        if [[ ! -f "${src}.import" ]]; then
            return 0
        fi
    done < <(find "$project_root" -type d -name .godot -prune -o -type f -name '*.dialogue' -print0)

    while IFS= read -r -d '' imp; do
        local content src_rel src_path src_time
        content=$(cat "$imp") || continue

        src_rel=$(printf '%s\n' "$content" | grep -oP '^source_file="\K[^"]+' | head -1)
        [[ -z "$src_rel" ]] && continue
        src_path="$project_root/${src_rel#res://}"
        [[ ! -f "$src_path" ]] && continue
        src_time=$(stat -c %Y "$src_path")

        # Every compiled output path mentioned in the sidecar. Both
        # dest_files=[...] entries and the [remap] path= line point into
        # .godot/imported/.
        while IFS= read -r dest_rel; do
            local dest_path dest_time md5_path md5_content recorded actual
            dest_path="$project_root/${dest_rel#res://}"
            if [[ ! -f "$dest_path" ]]; then
                return 0
            fi
            dest_time=$(stat -c %Y "$dest_path")
            if (( src_time <= dest_time )); then
                continue
            fi

            # mtime says "maybe stale" -- confirm against the actual content
            # hash before trusting it.
            md5_path="${dest_path%.*}.md5"
            if [[ ! -f "$md5_path" ]]; then
                return 0
            fi
            md5_content=$(cat "$md5_path")
            recorded=$(printf '%s\n' "$md5_content" | grep -oP 'source_md5="\K[^"]+' | head -1)
            if [[ -z "$recorded" ]]; then
                return 0
            fi
            actual=$(md5sum "$src_path" | awk '{print $1}')
            if [[ "$actual" != "$recorded" ]]; then
                return 0
            fi
        done < <(printf '%s\n' "$content" | grep -oP '"res://\.godot/imported/[^"]+' | tr -d '"')
    done < <(find "$project_root" -type d -name .godot -prune -o -type f -name '*.import' -print0)

    return 1
}

import_if_stale() {
    local project_root="$1"
    local godot_path="$2"

    if _imports_stale "$project_root"; then
        printf '\033[33mStale imported resource cache detected (an imported asset -- e.g. a .dialogue file -- changed since it was last compiled). Reimporting...\033[0m\n'
        "$godot_path" --headless --path "$project_root" --import >/dev/null
        printf '\033[33mReimport complete.\033[0m\n'
    fi
}
