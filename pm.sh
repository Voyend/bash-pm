### ~/bashlib/pm.sh
### Project Manager (pm) - lightweight project directory manager for Termux / bash

PM_DB="$HOME/.pm_projects"
PM_BACKUP="$HOME/.pm_projects.bak"
PM_LIB_DIR="$HOME/bashlib"
PM_LAST="$HOME/.pm_last"       
PM_NOTES="$HOME/.pm_notes"     
PM_HISTORY="$HOME/.pm_history"
PM_HISTORY_POS="$HOME/.pm_history_pos"

### create db and files if missing
mkdir -p "$PM_LIB_DIR"
[ ! -f "$PM_DB" ] && touch "$PM_DB"
[ ! -f "$PM_NOTES" ] && touch "$PM_NOTES"
[ ! -f "$PM_HISTORY" ] && touch "$PM_HISTORY"
[ ! -f "$PM_HISTORY_POS" ] && echo "0" > "$PM_HISTORY_POS"

### Colors
if command -v tput >/dev/null 2>&1; then
    _BOLD="$(tput bold)"
    _RESET="$(tput sgr0)"
    _RED="$(tput setaf 1)"
    _GREEN="$(tput setaf 2)"
    _YELLOW="$(tput setaf 3)"
    _BLUE="$(tput setaf 4)"
    _CYAN="$(tput setaf 6)"
else
    _BOLD="\033[1m"   _RESET="\033[0m"
    _RED="\033[31m"   _GREEN="\033[32m"
    _YELLOW="\033[33m" _BLUE="\033[34m"
    _CYAN="\033[36m"
fi

info()   { printf "%b%s%b\n" "$_BLUE"   " $*" "$_RESET"; }
ok()     { printf "%b%s%b\n" "$_GREEN"  " $*" "$_RESET"; }
warn()   { printf "%b%s%b\n" "$_YELLOW" " $*" "$_RESET"; }
err()    { printf "%b%s%b\n" "$_RED"    " $*" "$_RESET"; }
detail() { printf "%b%s%b\n" "$_CYAN"   " $*" "$_RESET"; }

### Resolve absolute path robustly
_resolve_path() {
    local p="$1"
    [ -z "$p" ] && return 1
    if [ -d "$p" ]; then
        if command -v realpath >/dev/null 2>&1; then
            realpath "$p" 2>/dev/null && return
        fi
        if command -v readlink >/dev/null 2>&1; then
            if readlink -f "$p" >/dev/null 2>&1; then
                readlink -f "$p" 2>/dev/null && return
            fi
        fi
        (cd "$p" 2>/dev/null && pwd -P) && return
    fi
    return 1
}

### Safe write (atomic via mktemp)
_pm_safe_replace() {
    local target_file="$1"
    local tmp
    tmp=$(mktemp) || { err "Failed to create temp file."; return 1; }
    cat > "$tmp" && mv "$tmp" "$target_file"
}

_pm_get_path() { grep "^$1=" "$PM_DB" 2>/dev/null | head -n1 | cut -d'=' -f2-; }
_pm_get_note() { grep "^$1=" "$PM_NOTES" 2>/dev/null | head -n1 | cut -d'=' -f2-; }

### Browser-style History Logic
_pm_record_history() {
    local name="$1"
    local pos total
    pos=$(cat "$PM_HISTORY_POS" 2>/dev/null || echo 0)
    total=$(wc -l < "$PM_HISTORY" 2>/dev/null || echo 0)

    # Truncate future history if we jumped back and are now branching
    if [ "$pos" -lt "$total" ] && [ "$pos" -gt 0 ]; then
        local tmp; tmp=$(mktemp)
        head -n "$pos" "$PM_HISTORY" > "$tmp" && mv "$tmp" "$PM_HISTORY"
    elif [ "$pos" -eq 0 ]; then
        > "$PM_HISTORY"
    fi

    local last_recorded=""
    [ "$pos" -gt 0 ] && last_recorded=$(tail -n 1 "$PM_HISTORY" 2>/dev/null)
    
    if [ "$last_recorded" != "$name" ]; then
        echo "$name" >> "$PM_HISTORY"
        pos=$((pos + 1))
        echo "$pos" > "$PM_HISTORY_POS"
    fi
    echo "$name" > "$PM_LAST" # maintain legacy support
}

_pm_nav_go() {
    local target_pos="$1"
    local total
    total=$(wc -l < "$PM_HISTORY" 2>/dev/null || echo 0)
    if [ "$total" -eq 0 ] || [ "$target_pos" -lt 1 ] || [ "$target_pos" -gt "$total" ]; then
        return 1
    fi
    
    local name; name=$(sed -n "${target_pos}p" "$PM_HISTORY")
    local path; path=$(_pm_get_path "$name")
    
    if [ -z "$path" ] || [ ! -d "$path" ]; then
        err "❌ Project '$name' missing or invalid path."
        return 1
    fi
    
    cd "$path" || return 1
    echo "$target_pos" > "$PM_HISTORY_POS"
    echo "$name" > "$PM_LAST"
    ok "📂 Navigated to '$name' → $path"
    
    local note; note=$(_pm_get_note "$name")
    [ -n "$note" ] && detail "   📝 $note"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_add() {
    local name="" path="" use_current=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --current) use_current=true ;;
            *) if [ -z "$name" ]; then name="$1"; elif [ -z "$path" ]; then path="$1"; fi ;;
        esac
        shift
    done

    if [ -z "$name" ]; then
        err "Usage: pm add [name] [path]"
        err "       pm add [name] --current"
        return 1
    fi

    if $use_current; then path="$PWD"; fi

    if [ -z "$path" ]; then
        err "Usage: pm add [name] [path]"
        return 1
    fi

    if [[ "$name" =~ [=[:space:]] ]]; then
        err "Project name cannot contain spaces or '='"
        return 1
    fi

    local real
    real=$(_resolve_path "$path") || { err "Directory not found: $path"; return 1; }
    if [ -z "$real" ]; then err "Failed to resolve path (empty)."; return 1; fi

    ( grep -v "^$name=" "$PM_DB" 2>/dev/null; echo "$name=$real" ) | _pm_safe_replace "$PM_DB"
    ok "✅ Project '$name' added → $real"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_list() {
    if [ ! -s "$PM_DB" ]; then info "No projects added yet."; return 0; fi
    info "📂 Registered projects:"
    while IFS='=' read -r name path; do
        [ -z "$name" ] && continue
        local indicator=""
        [ ! -d "$path" ] && indicator="  ${_RED}[missing]${_RESET}"
        printf "   ${_BOLD}%-20s${_RESET} → %s%b\n" "$name" "$path" "$indicator"
    done < "$PM_DB"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_remove() {
    local name="$1"
    if [ -z "$name" ]; then err "Usage: pm remove [name]"; return 1; fi
    if ! grep -q "^$name=" "$PM_DB" 2>/dev/null; then warn "Project '$name' not found."; return 1; fi
    
    grep -v "^$name=" "$PM_DB" | _pm_safe_replace "$PM_DB"
    grep -v "^$name=" "$PM_NOTES" | _pm_safe_replace "$PM_NOTES"
    
    if [ -f "$PM_LAST" ] && [ "$(cat "$PM_LAST")" = "$name" ]; then rm -f "$PM_LAST"; fi
    ok "🗑️  Project '$name' removed."
}

### ─────────────────────────────────────────────────────────────────────────────
pm_open() {
    local name="$1"

    if [ "$name" = "--last" ]; then
        if [ ! -f "$PM_LAST" ] || [ ! -s "$PM_LAST" ]; then
            warn "No last project recorded yet."
            return 1
        fi
        name="$(cat "$PM_LAST")"
        info "↩️  Resuming last project: '$name'"
    fi

    # Interactive Select / Fuzzy Find
    if [ -z "$name" ]; then
        if command -v fzf >/dev/null 2>&1; then
            name=$(awk -F= '{print $1}' "$PM_DB" 2>/dev/null | fzf --height 40% --reverse --prompt="pm open> ")
            [ -z "$name" ] && return 0
        else
            info "Select a project to open:"
            local opts=()
            while IFS='=' read -r n p; do [ -n "$n" ] && opts+=("$n"); done < "$PM_DB"
            [ ${#opts[@]} -eq 0 ] && { warn "No projects available."; return 0; }
            
            local PS3="Enter number (or hit Enter to cancel): "
            select sel in "${opts[@]}"; do
                if [ -n "$sel" ]; then name="$sel"; break; else return 0; fi
            done
        fi
    fi

    local path; path="$(_pm_get_path "$name")"
    if [ -z "$path" ]; then err "❌ Project '$name' not found."; return 1; fi
    if [ ! -d "$path" ]; then warn "⚠️  Saved path does not exist: $path"; return 1; fi

    cd "$path" || return 1
    _pm_record_history "$name"
    ok "📂 Opened project '$name' → $path"

    local note; note="$(_pm_get_note "$name")"
    [ -n "$note" ] && detail "   📝 $note"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_back() {
    local pos; pos=$(cat "$PM_HISTORY_POS" 2>/dev/null || echo 0)
    if [ "$pos" -le 1 ]; then warn "Already at the beginning of history."; return 1; fi
    _pm_nav_go $((pos - 1))
}

pm_forward() {
    local pos; pos=$(cat "$PM_HISTORY_POS" 2>/dev/null || echo 0)
    local total; total=$(wc -l < "$PM_HISTORY" 2>/dev/null || echo 0)
    if [ "$pos" -ge "$total" ]; then warn "Already at the end of history."; return 1; fi
    _pm_nav_go $((pos + 1))
}

### ─────────────────────────────────────────────────────────────────────────────
pm_rename() {
    local old="$1" new="$2"
    if [ -z "$old" ] || [ -z "$new" ]; then err "Usage: pm rename [old_name] [new_name]"; return 1; fi
    if ! grep -q "^$old=" "$PM_DB" 2>/dev/null; then err "Project '$old' not found."; return 1; fi
    if grep -q "^$new=" "$PM_DB" 2>/dev/null; then err "A project named '$new' already exists."; return 1; fi
    
    local old_path; old_path=$(_pm_get_path "$old")
    local old_note; old_note=$(_pm_get_note "$old")
    
    ( grep -v "^$old=" "$PM_DB" 2>/dev/null; echo "$new=$old_path" ) | _pm_safe_replace "$PM_DB"
    if [ -n "$old_note" ]; then
        ( grep -v "^$old=" "$PM_NOTES" 2>/dev/null; echo "$new=$old_note" ) | _pm_safe_replace "$PM_NOTES"
    fi

    if [ -f "$PM_LAST" ] && [ "$(cat "$PM_LAST")" = "$old" ]; then echo "$new" > "$PM_LAST"; fi
    ok "🔁 Renamed '$old' → '$new'"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_update() {
    local name="" path="" use_current=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --current) use_current=true ;;
            *) if [ -z "$name" ]; then name="$1"; elif [ -z "$path" ]; then path="$1"; fi ;;
        esac
        shift
    done

    if [ -z "$name" ]; then
        err "Usage: pm update [name] [new_path]"
        return 1
    fi

    if $use_current; then path="$PWD"; fi

    if [ -z "$path" ]; then
        err "Usage: pm update [name] [new_path]"
        return 1
    fi

    if ! grep -q "^$name=" "$PM_DB" 2>/dev/null; then err "Project '$name' not found."; return 1; fi

    local real; real=$(_resolve_path "$path") || { err "Directory not found: $path"; return 1; }
    if [ -z "$real" ]; then err "Failed to resolve path."; return 1; fi

    ( grep -v "^$name=" "$PM_DB" 2>/dev/null; echo "$name=$real" ) | _pm_safe_replace "$PM_DB"
    ok "✏️  Updated '$name' → $real"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_upgrade() {
    info "Fetching latest version of Project Manager..."
    local url="https://raw.githubusercontent.com/Voyend/bash-pm/main/pm.sh"
    local target="$HOME/bashlib/pm.sh"
    
    if curl -fsSL "$url" -o "$target.tmp"; then
        mv "$target.tmp" "$target"
        
        # Source the new version immediately into the current shell
        source "$target"
        ok "✨ pm updated successfully!"
    else
        err "Failed to download update."
        rm -f "$target.tmp"
        return 1
    fi
}

### ─────────────────────────────────────────────────────────────────────────────
pm_note() {
    local name="$1"; shift
    if [ -z "$name" ]; then
        err "Usage: pm note [name] [text]"
        err "       pm note [name] --clear"
        return 1
    fi
    if ! grep -q "^$name=" "$PM_DB" 2>/dev/null; then err "Project '$name' not found."; return 1; fi

    if [ "$1" = "--clear" ]; then
        grep -v "^$name=" "$PM_NOTES" | _pm_safe_replace "$PM_NOTES"
        ok "🗒️  Note cleared for '$name'."
        return 0
    fi

    if [ $# -eq 0 ]; then
        local note; note="$(_pm_get_note "$name")"
        if [ -n "$note" ]; then detail "📝 [$name] $note"
        else info "No note set for '$name'."; fi
        return 0
    fi

    local text="$*"
    ( grep -v "^$name=" "$PM_NOTES" 2>/dev/null; echo "$name=$text" ) | _pm_safe_replace "$PM_NOTES"
    ok "📝 Note saved for '$name'."
}

### ─────────────────────────────────────────────────────────────────────────────
pm_info() {
    local name="$1"
    if [ -z "$name" ]; then err "Usage: pm info [name]"; return 1; fi
    local path; path="$(_pm_get_path "$name")"
    if [ -z "$path" ]; then err "Project '$name' not found."; return 1; fi
    local note; note="$(_pm_get_note "$name")"
    
    local status="${_GREEN}exists${_RESET}"
    [ ! -d "$path" ] && status="${_RED}MISSING${_RESET}"

    local last_flag=""
    if [ -f "$PM_LAST" ] && [ "$(cat "$PM_LAST")" = "$name" ]; then last_flag=" (last opened)"; fi

    printf "%b%s%b%s\n" "$_BOLD" "$name" "$_RESET" "$last_flag"
    printf "  Path   : %s\n"       "$path"
    printf "  Status : %b\n"       "$status"
    [ -n "$note" ] && printf "  Note   : %s\n" "$note"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_search() {
    local kw="$1"
    if [ -z "$kw" ]; then err "Usage: pm search [keyword]"; return 1; fi
    local found=0
    while IFS='=' read -r name path; do
        [ -z "$name" ] && continue
        if [[ "$name" == *"$kw"* ]] || [[ "$path" == *"$kw"* ]]; then
            local indicator=""
            [ ! -d "$path" ] && indicator="  ${_RED}[missing]${_RESET}"
            printf "   ${_BOLD}%-20s${_RESET} → %s%b\n" "$name" "$path" "$indicator"
            found=1
        fi
    done < "$PM_DB"
    [ $found -eq 0 ] && warn "No projects matching '$kw'."
}

### ─────────────────────────────────────────────────────────────────────────────
pm_status() {
    if [ ! -s "$PM_DB" ]; then info "No projects added yet."; return 0; fi
    local ok_count=0 miss_count=0
    info "🔍 Project health check:"
    while IFS='=' read -r name path; do
        [ -z "$name" ] && continue
        if [ -d "$path" ]; then
            printf "  %b✔%b  %-20s → %s\n" "$_GREEN" "$_RESET" "$name" "$path"
            (( ok_count++ ))
        else
            printf "  %b✘%b  %-20s → %s  %b[missing]%b\n" "$_RED" "$_RESET" "$name" "$path" "$_RED" "$_RESET"
            (( miss_count++ ))
        fi
    done < "$PM_DB"
    echo ""
    printf "  %b%d OK%b  |  %b%d missing%b\n" "$_GREEN" "$ok_count" "$_RESET" "$_RED" "$miss_count" "$_RESET"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_export() {
    local out="${1:-$HOME/pm_export_$(date +%Y%m%d%H%M%S).txt}"
    cp "$PM_DB" "$out"
    ok "Exported DB → $out"
}

pm_import() {
    local f="$1"
    if [ -z "$f" ] || [ ! -f "$f" ]; then err "Usage: pm import [file]"; return 1; fi
    cp "$PM_DB" "$PM_BACKUP"
    cp "$f" "$PM_DB"
    ok "Imported projects from $f (backup saved to $PM_BACKUP)"
}

### ─────────────────────────────────────────────────────────────────────────────
pm_help() {
    cat <<EOF
${_BOLD}Usage: pm [command] [args]${_RESET}

${_BOLD}add${_RESET} [name] [path]            Add a new project
${_BOLD}add${_RESET} [name] --current         Add project using the current directory
${_BOLD}list${_RESET}                         List all projects (marks missing paths)
${_BOLD}remove${_RESET} [name]                Remove a project
${_BOLD}open${_RESET}                         Interactive menu / fuzzy find
${_BOLD}open${_RESET} [name]                  Open project (cd to path)
${_BOLD}open${_RESET} --last                  Re-open the last opened project
${_BOLD}back${_RESET}                         Go back in project history
${_BOLD}forward${_RESET}                      Go forward in project history
${_BOLD}rename${_RESET} [old] [new]           Rename a project
${_BOLD}update${_RESET} [name] [path]         Change a project's path
${_BOLD}update${_RESET} [name] --current      Change path to the current directory
${_BOLD}note${_RESET}  [name] [text]          Set a note/description for a project
${_BOLD}note${_RESET}  [name]                 Show the note for a project
${_BOLD}note${_RESET}  [name] --clear         Remove the note for a project
${_BOLD}info${_RESET}  [name]                 Show full details for a project
${_BOLD}search${_RESET} [keyword]             Filter projects by name or path
${_BOLD}status${_RESET}                       Health check — show which paths exist/missing
${_BOLD}export${_RESET} [file]                Export DB to file (default: ~/pm_export_*.txt)
${_BOLD}import${_RESET} [file]                Import DB from file (overwrites current DB)
${_BOLD}help${_RESET}                         Show this help
EOF
}

### ─────────────────────────────────────────────────────────────────────────────
pm() {
    case "$1" in
        add)    shift; pm_add    "$@" ;;
        list)          pm_list        ;;
        remove) shift; pm_remove "$@" ;;
        open)   shift; pm_open   "$@" ;;
        back)          pm_back        ;;
        forward)       pm_forward     ;;
        rename) shift; pm_rename "$@" ;;
        update) shift; pm_update "$@" ;;
        upgrade)       pm_upgrade     ;;
        note)   shift; pm_note   "$@" ;;
        info)   shift; pm_info   "$@" ;;
        search) shift; pm_search "$@" ;;
        status)        pm_status      ;;
        export) shift; pm_export "$@" ;;
        import) shift; pm_import "$@" ;;
        help|--help|-h|'') pm_help ;;
        *) err "Unknown command: $1"; pm_help ;;
    esac
}

### Bash completion
_pm_completion() {
    local cur cur="${[COMP_CWORD]}"
    local subcommands="add list remove open back forward rename update upgrad note info search status export import help"
    
    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
        return 0
    fi
    
    local projects=""
    [ -f "$PM_DB" ] && projects="$(awk -F= '{print $1}' "$PM_DB" 2>/dev/null | tr '\n' ' ')"
    
    case "${COMP_WORDS[1]}" in
        open) COMPREPLY=( $(compgen -W "$projects --last" -- "$cur") ) ;;
        remove|rename|info|note|search) COMPREPLY=( $(compgen -W "$projects" -- "$cur") ) ;;
        update)
            if [ $ -eq 2 ]; then COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
            elif [ $COMP_CWORD -eq 3 ]; then COMPREPLY=( $(compgen -W "--current" -- "$cur") ); fi ;;
        add) 
            if [ $COMP_CWORD -eq 3 ]; then COMPREPLY=( $(compgen -W "--current" -- "$cur") ); fi ;;
    esac
}
complete -F _pm_completion pm 2>/dev/null || true
