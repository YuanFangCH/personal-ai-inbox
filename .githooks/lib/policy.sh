#!/bin/sh

set -eu

policy_fail() {
    printf '\n[git-policy] ERROR: %s\n' "$*" >&2
    exit 1
}

policy_root() {
    git rev-parse --show-toplevel 2>/dev/null ||
        policy_fail "Not inside a Git repository."
}

policy_require_no_unstaged_changes() {
    if ! git diff --quiet --ignore-submodules --; then
        policy_fail "Tracked changes are not staged. Stage the complete task before committing."
    fi
}

policy_require_no_untracked_files() {
    untracked=$(git ls-files --others --exclude-standard)
    if [ -n "$untracked" ]; then
        printf '\n[git-policy] Untracked files:\n%s\n' "$untracked" >&2
        policy_fail "Untracked files must be staged, ignored, or removed before committing."
    fi
}

policy_require_no_sensitive_paths() {
    staged=$(git diff --cached --name-only --diff-filter=ACMR)
    [ -n "$staged" ] || return 0

    findings=$(printf '%s\n' "$staged" | grep -Ei \
        -e '(^|/)\.env($|\.)' \
        -e '\.(pem|key|p12|pfx|jks|keystore)$' \
        -e '(^|/)key\.properties$' \
        -e '(^|/)(vault|build|\.dart_tool|secrets?|credentials?)/' \
        || true)

    if [ -n "$findings" ]; then
        printf '\n[git-policy] Sensitive paths:\n%s\n' "$findings" >&2
        policy_fail "Sensitive local data or signing material must not be committed."
    fi
}

policy_require_no_high_confidence_secrets() {
    staged=$(git diff --cached --name-only --diff-filter=ACMR)
    [ -n "$staged" ] || return 0

    findings=""
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if git show ":$path" 2>/dev/null | grep -E -q \
            -e 'sk-[A-Za-z0-9_-]{16,}' \
            -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
            -e 'AIza[0-9A-Za-z_-]{30,}' \
            -e 'xox[baprs]-[A-Za-z0-9-]{20,}' \
            -e 'AKIA[0-9A-Z]{16}' \
            -e 'ASIA[0-9A-Z]{16}' \
            -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
            -e 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}' \
            -e 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/-]{20,}' \
            -e '序列号[：:][[:space:]]*[A-Z0-9]{10,}' \
            -e '-AndroidDevice[[:space:]]+[A-Z0-9]{10,}' \
            -e '-d[[:space:]]+R[0-9A-Z]{10,}'; then
            findings="$findings$path
"
        fi
    done <<EOF
$staged
EOF

    if [ -n "$findings" ]; then
        printf '\n[git-policy] Files containing secret-like content:\n%s\n' "$findings" >&2
        policy_fail "High-confidence secret patterns must not be committed."
    fi
}

policy_require_handoff_staged() {
    staged=$(git diff --cached --name-only)
    [ -n "$staged" ] || policy_fail "No staged changes were found."

    if git diff --cached --name-only --diff-filter=D -- RM_HANDOFF.md | grep -q .; then
        policy_fail "RM_HANDOFF.md cannot be deleted."
    fi

    [ -f RM_HANDOFF.md ] || policy_fail "RM_HANDOFF.md is missing."

    has_handoff=0
    has_other=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ "$path" = "RM_HANDOFF.md" ]; then
            has_handoff=1
        else
            has_other=1
        fi
    done <<EOF
$staged
EOF

    if [ "$has_other" -eq 1 ] && [ "$has_handoff" -ne 1 ]; then
        policy_fail "Formal changes require RM_HANDOFF.md to be updated and staged in the same commit."
    fi
}

policy_validate_handoff_section() {
    section=$1
    awk -v wanted="$section" '
        $0 == wanted {
            inside = 1
            next
        }
        inside && /^## / {
            exit
        }
        inside && $0 !~ /^[[:space:]]*$/ {
            content = 1
        }
        END {
            exit content ? 0 : 1
        }
    ' RM_HANDOFF.md ||
        policy_fail "RM_HANDOFF.md section is missing or empty: $section"
}

policy_validate_handoff() {
    [ -f RM_HANDOFF.md ] || policy_fail "RM_HANDOFF.md is missing."

    policy_validate_handoff_section "## 1. 文档状态"
    policy_validate_handoff_section "## 2. 一句话交接"
    policy_validate_handoff_section "## 3. 当前目标与范围"
    policy_validate_handoff_section "## 4. 权威文件"
    policy_validate_handoff_section "## 5. 已锁定决定"
    policy_validate_handoff_section "## 6. 当前进度与验证"
    policy_validate_handoff_section "## 7. 风险、阻塞与下一步"
    policy_validate_handoff_section "## 8. 变更记录"
}
