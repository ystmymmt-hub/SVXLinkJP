#!/usr/bin/env bash

set -u

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$PROJECT_ROOT" || exit 1

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
RESET='\033[0m'

ERROR_COUNT=0
WARN_COUNT=0

print_title() {
    printf '\n%s===== %s =====%s\n' "$CYAN" "$1" "$RESET"
}

ok() {
    printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$1"
}

warn() {
    printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

ng() {
    printf '%s[ NG ]%s %s\n' "$RED" "$RESET" "$1"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

is_placeholder_value() {
    case "$1" in
        ""|YOUR_*|CHANGE_ME|CHANGEME|EXAMPLE|example|xxxxxxxx|XXXXXXXX|********)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

print_title "SVXLinkJP Release Check"

printf 'Project: %s\n' "$PROJECT_ROOT"
printf 'Date   : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

print_title "Git Repository"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "Git repository detected"
else
    ng "This directory is not a Git repository"
fi

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"

if [ -n "$CURRENT_BRANCH" ]; then
    ok "Current branch: $CURRENT_BRANCH"
else
    warn "Could not detect current branch"
fi

if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    ok "Working tree is clean"
else
    warn "Uncommitted or staged changes exist"
    git status --short
fi

print_title "Ignored Personal Files"

if git check-ignore -q config/config.ini 2>/dev/null; then
    ok "config/config.ini is ignored by Git"
else
    ng "config/config.ini is not ignored"
fi

if git check-ignore -q backup/test.ini 2>/dev/null; then
    ok "backup/ directory is ignored by Git"
else
    ng "backup/ directory is not ignored"
fi

if git ls-files --error-unmatch config/config.ini >/dev/null 2>&1; then
    ng "config/config.ini is still tracked by Git"
else
    ok "config/config.ini is not tracked by Git"
fi

TRACKED_BACKUPS="$(
    git ls-files 2>/dev/null |
    grep -E '(^|/)(backup/|.*\.(bak|backup)(\.|$)|.*\.backup\.)' || true
)"

if [ -n "$TRACKED_BACKUPS" ]; then
    ng "Backup files are tracked by Git"
    printf '%s\n' "$TRACKED_BACKUPS"
else
    ok "No backup files are tracked by Git"
fi

print_title "Sensitive Values in Tracked Files"

SENSITIVE_RESULTS="$(
    git grep -nEI \
        '(PASSWORD|PASSWD|SECRET|TOKEN|API_KEY)[[:space:]]*=[[:space:]]*[^[:space:]]+' \
        -- \
        ':!check_release.sh' \
        2>/dev/null || true
)"

REAL_SECRET_FOUND=0

if [ -n "$SENSITIVE_RESULTS" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue

        value="${line#*=}"
        value="${value%%[[:space:]]*}"
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        if is_placeholder_value "$value"; then
            printf '%s[INFO]%s Placeholder: %s\n' "$CYAN" "$RESET" "$line"
        elif [[ "$line" =~ PASSWORD=\"\" ]] ||
             [[ "$line" =~ PASSWORD=\'\' ]] ||
             [[ "$line" =~ PASSWORD=\$ ]] ||
             [[ "$line" =~ PASSWORD=\$\{ ]] ||
             [[ "$line" =~ PASSWORD=\$[A-Za-z_] ]]; then
            printf '%s[INFO]%s Program variable: %s\n' "$CYAN" "$RESET" "$line"
        else
            printf '%s[ NG ]%s Possible secret: %s\n' "$RED" "$RESET" "$line"
            REAL_SECRET_FOUND=1
        fi
    done <<< "$SENSITIVE_RESULTS"
fi

if [ "$REAL_SECRET_FOUND" -eq 0 ]; then
    ok "No obvious real passwords or tokens found in tracked files"
else
    ng "Possible real password or token found"
fi

print_title "Personal Callsign Check"

CALLSIGN_RESULTS="$(
    git grep -nEI \
        '(JQ1YOF|JE1BGA|JP1YMH|CALLSIGN[[:space:]]*=[[:space:]]*[A-Z0-9]+)' \
        -- \
        ':!README.md' \
        ':!CHANGELOG.md' \
        ':!check_release.sh' \
        2>/dev/null || true
)"

if [ -n "$CALLSIGN_RESULTS" ]; then
    warn "Callsign-like values were found. Review them manually:"
    printf '%s\n' "$CALLSIGN_RESULTS"
else
    ok "No personal callsign-like values found in tracked program files"
fi

print_title "Hard-Coded Path Check"

HARDCODED_PATHS="$(
    git grep -nE \
        '(/root/SVXLinkJP|/home/[^/]+/SVXLinkJP)' \
        -- \
        ':!README.md' \
        ':!CHANGELOG.md' \
        ':!check_release.sh' \
        2>/dev/null || true
)"

if [ -n "$HARDCODED_PATHS" ]; then
    ng "Hard-coded project paths found"
    printf '%s\n' "$HARDCODED_PATHS"
else
    ok "No hard-coded SVXLinkJP home paths found"
fi

print_title "Shell Syntax Check"

SHELL_ERROR=0

while IFS= read -r file; do
    [ -z "$file" ] && continue

    if bash -n "$file" 2>/dev/null; then
        printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$file"
    else
        printf '%s[ NG ]%s Syntax error: %s\n' "$RED" "$RESET" "$file"
        bash -n "$file"
        SHELL_ERROR=1
    fi
done < <(
    git ls-files '*.sh' 2>/dev/null
)

if [ "$SHELL_ERROR" -eq 0 ]; then
    ok "All tracked shell scripts passed bash -n"
else
    ng "Shell syntax errors found"
fi

print_title "Required Files"

REQUIRED_FILES=(
    "README.md"
    "install.sh"
    "menu.sh"
    "config/config.ini.example"
    ".gitignore"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        ok "$file exists"
    else
        ng "$file is missing"
    fi
done

print_title "Current Release Information"

printf 'Branch : %s\n' "${CURRENT_BRANCH:-unknown}"
printf 'Commit : %s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf 'Latest : %s\n' "$(git log -1 --pretty='%h %s' 2>/dev/null || echo unknown)"

printf '\n'

if [ "$ERROR_COUNT" -eq 0 ]; then
    printf '%s========================================%s\n' "$GREEN" "$RESET"
    printf '%s RELEASE CHECK PASSED%s\n' "$GREEN" "$RESET"
    printf '%s Errors: %d  Warnings: %d%s\n' \
        "$GREEN" "$ERROR_COUNT" "$WARN_COUNT" "$RESET"
    printf '%s========================================%s\n' "$GREEN" "$RESET"
    exit 0
else
    printf '%s========================================%s\n' "$RED" "$RESET"
    printf '%s RELEASE CHECK FAILED%s\n' "$RED" "$RESET"
    printf '%s Errors: %d  Warnings: %d%s\n' \
        "$RED" "$ERROR_COUNT" "$WARN_COUNT" "$RESET"
    printf '%s Fix all NG items before pushing a release.%s\n' "$RED" "$RESET"
    printf '%s========================================%s\n' "$RED" "$RESET"
    exit 1
fi
