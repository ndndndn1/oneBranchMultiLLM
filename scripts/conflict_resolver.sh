#!/bin/bash
# Git 충돌 자동 해결 및 조율 스크립트

set -e

COLLAB_DIR=".claude-collab"
CONFLICTS_DIR="$COLLAB_DIR/conflicts"
CLAUDE_ID="${CLAUDE_ID:-unknown}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 충돌 감지
detect_conflicts() {
    log_info "Checking for git conflicts..."

    # Merge 충돌 확인
    if git diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
        echo "MERGE_CONFLICT"
        return 0
    fi

    # 동시 수정 가능성 확인 (같은 파일에 대한 잠금 충돌)
    local current_locks=$(ls -1 "$COLLAB_DIR/locks/"*.lock 2>/dev/null | wc -l)
    if [ "$current_locks" -gt 0 ]; then
        echo "POTENTIAL_CONFLICT"
        return 0
    fi

    echo "NO_CONFLICT"
    return 0
}

# 충돌 파일 목록
list_conflicts() {
    log_info "Conflicting files:"
    git diff --name-only --diff-filter=U 2>/dev/null | while read file; do
        echo "  - $file"

        # 해당 파일의 잠금 소유자 확인
        local encoded=$(echo "$file" | sed 's/\//_SLASH_/g')
        local lock_file="$COLLAB_DIR/locks/$encoded.lock"
        if [ -f "$lock_file" ]; then
            local owner=$(jq -r '.owner' "$lock_file")
            echo "    (locked by: $owner)"
        fi
    done
}

# 충돌 기록
record_conflict() {
    local file="$1"
    local conflict_type="$2"

    mkdir -p "$CONFLICTS_DIR"

    local conflict_file="$CONFLICTS_DIR/$(date +%s)_${CLAUDE_ID}.json"
    cat > "$conflict_file" << EOF
{
    "file": "$file",
    "type": "$conflict_type",
    "reporter": "$CLAUDE_ID",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "status": "unresolved",
    "resolution": null
}
EOF

    log_info "Conflict recorded: $conflict_file"
}

# 자동 해결 시도 (간단한 케이스)
auto_resolve() {
    local file="$1"
    local strategy="${2:-ours}"  # ours, theirs, union

    log_info "Attempting auto-resolve for $file with strategy: $strategy"

    case "$strategy" in
        ours)
            git checkout --ours "$file"
            git add "$file"
            log_success "Resolved with 'ours' strategy"
            ;;
        theirs)
            git checkout --theirs "$file"
            git add "$file"
            log_success "Resolved with 'theirs' strategy"
            ;;
        union)
            # 두 변경사항 모두 유지 시도
            if git merge-file -p "$file" 2>/dev/null; then
                git add "$file"
                log_success "Resolved with union merge"
            else
                log_error "Union merge failed"
                return 1
            fi
            ;;
        *)
            log_error "Unknown strategy: $strategy"
            return 1
            ;;
    esac
}

# 충돌 해결 조율
coordinate_resolution() {
    log_info "=== Conflict Resolution Coordination ==="

    # 충돌 파일별로 처리
    git diff --name-only --diff-filter=U 2>/dev/null | while read file; do
        log_info "Processing: $file"

        # 파일 잠금 소유자 확인
        local encoded=$(echo "$file" | sed 's/\//_SLASH_/g')
        local lock_file="$COLLAB_DIR/locks/$encoded.lock"

        if [ -f "$lock_file" ]; then
            local owner=$(jq -r '.owner' "$lock_file")

            if [ "$owner" = "$CLAUDE_ID" ]; then
                log_info "You own the lock. Resolving with 'ours'..."
                auto_resolve "$file" "ours"
            else
                log_warn "Locked by $owner. Waiting for resolution..."
                # 다른 소유자에게 알림
                ./scripts/collab.sh send "$owner" "[CONFLICT] Please resolve conflict in $file" 2>/dev/null || true
                record_conflict "$file" "awaiting_owner"
            fi
        else
            # 잠금 없는 파일 - 먼저 온 변경사항 유지
            log_warn "No lock on file. Using 'theirs' (remote changes)..."
            auto_resolve "$file" "theirs"
        fi
    done
}

# Safe pull with conflict handling
safe_pull() {
    log_info "Performing safe pull..."

    # 먼저 fetch
    git fetch origin 2>/dev/null || {
        log_error "Failed to fetch from origin"
        return 1
    }

    # 로컬 변경사항 stash
    local has_changes=false
    if ! git diff --quiet 2>/dev/null; then
        has_changes=true
        log_info "Stashing local changes..."
        git stash push -m "collab-auto-stash-$(date +%s)"
    fi

    # Rebase 시도
    if git pull --rebase origin "$(git branch --show-current)" 2>/dev/null; then
        log_success "Pull successful"
    else
        log_warn "Rebase conflict detected"

        # 충돌 해결 조율
        coordinate_resolution

        # Continue rebase if possible
        git rebase --continue 2>/dev/null || {
            log_error "Cannot auto-continue rebase. Manual intervention needed."
            git rebase --abort 2>/dev/null
            return 1
        }
    fi

    # Stash 복원
    if [ "$has_changes" = true ]; then
        log_info "Restoring stashed changes..."
        git stash pop 2>/dev/null || {
            log_warn "Stash pop failed. Check git stash list."
        }
    fi

    log_success "Safe pull completed"
}

# 충돌 방지 커밋
safe_commit() {
    local message="$1"

    if [ -z "$message" ]; then
        log_error "Commit message required"
        return 1
    fi

    # 최신 상태로 업데이트
    log_info "Syncing before commit..."
    git fetch origin 2>/dev/null

    # 원격에 새 커밋이 있는지 확인
    local behind=$(git rev-list --count HEAD..origin/$(git branch --show-current) 2>/dev/null || echo "0")

    if [ "$behind" -gt 0 ]; then
        log_warn "Remote has $behind new commits. Pulling first..."
        safe_pull
    fi

    # 커밋
    git add -A
    git commit -m "$message"

    log_success "Committed: $message"
}

# 충돌 방지 푸시
safe_push() {
    local branch="${1:-$(git branch --show-current)}"
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        log_info "Push attempt $((retry + 1))/$max_retries..."

        if git push -u origin "$branch" 2>/dev/null; then
            log_success "Push successful"
            return 0
        fi

        log_warn "Push failed. Pulling and retrying..."
        safe_pull

        retry=$((retry + 1))
        sleep 2
    done

    log_error "Push failed after $max_retries attempts"
    return 1
}

# 도움말
show_help() {
    cat << 'EOF'
Conflict Resolver - Git conflict handling for multi-Claude collaboration

Usage: conflict_resolver.sh <command> [arguments]

Commands:
  detect              Check for conflicts
  list                List conflicting files
  resolve <file> <strategy>  Resolve a specific file (ours/theirs/union)
  coordinate          Coordinate resolution for all conflicts
  safe-pull           Pull with automatic conflict handling
  safe-commit <msg>   Commit with pre-pull sync
  safe-push [branch]  Push with retry on conflict

Strategies:
  ours    - Keep local changes
  theirs  - Keep remote changes
  union   - Try to merge both

Examples:
  ./scripts/conflict_resolver.sh detect
  ./scripts/conflict_resolver.sh resolve src/app.ts ours
  ./scripts/conflict_resolver.sh safe-commit "feat: add login"
  ./scripts/conflict_resolver.sh safe-push main
EOF
}

# 메인
case "${1:-help}" in
    detect)     detect_conflicts ;;
    list)       list_conflicts ;;
    resolve)    auto_resolve "$2" "$3" ;;
    coordinate) coordinate_resolution ;;
    safe-pull)  safe_pull ;;
    safe-commit) safe_commit "$2" ;;
    safe-push)  safe_push "$2" ;;
    help|--help|-h) show_help ;;
    *) log_error "Unknown command: $1"; show_help; exit 1 ;;
esac
