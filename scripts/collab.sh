#!/bin/bash
# Multi-Claude Collaboration Script
# 여러 Claude Code 인스턴스 간 협업을 위한 도구

set -e

COLLAB_DIR=".claude-collab"
INSTANCES_DIR="$COLLAB_DIR/instances"
LOCKS_DIR="$COLLAB_DIR/locks"
MESSAGES_DIR="$COLLAB_DIR/messages"
TASKS_DIR="$COLLAB_DIR/tasks"
CONFLICTS_DIR="$COLLAB_DIR/conflicts"
ERRORS_DIR="$COLLAB_DIR/errors"

# 현재 Claude 인스턴스 ID (환경변수 또는 자동 생성)
CLAUDE_ID="${CLAUDE_ID:-claude-$(hostname | md5sum | cut -c1-4)}"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 유틸리티 함수들
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

timestamp() { date +%s; }
datetime() { date '+%Y-%m-%d %H:%M:%S'; }

# 파일 경로를 안전한 파일명으로 인코딩
encode_path() {
    echo "$1" | sed 's/\//_SLASH_/g' | sed 's/ /_SPACE_/g'
}

decode_path() {
    echo "$1" | sed 's/_SLASH_/\//g' | sed 's/_SPACE_/ /g'
}

# 디렉토리 초기화
init_dirs() {
    mkdir -p "$INSTANCES_DIR" "$LOCKS_DIR" "$MESSAGES_DIR" "$TASKS_DIR"/{pending,in_progress,completed} "$CONFLICTS_DIR" "$ERRORS_DIR"
}

# ============================================
# 인스턴스 관리
# ============================================

cmd_register() {
    local description="${1:-No description}"
    init_dirs

    local instance_file="$INSTANCES_DIR/$CLAUDE_ID.json"
    cat > "$instance_file" << EOF
{
    "id": "$CLAUDE_ID",
    "description": "$description",
    "registered_at": "$(datetime)",
    "last_heartbeat": "$(timestamp)",
    "status": "active",
    "current_task": null,
    "locked_files": []
}
EOF
    log_success "Registered as $CLAUDE_ID"
    log_info "Description: $description"

    # 메시지 디렉토리 생성
    mkdir -p "$MESSAGES_DIR/$CLAUDE_ID"
}

cmd_unregister() {
    # 모든 잠금 해제
    for lock_file in "$LOCKS_DIR"/*.lock; do
        if [ -f "$lock_file" ]; then
            local owner=$(jq -r '.owner' "$lock_file" 2>/dev/null)
            if [ "$owner" = "$CLAUDE_ID" ]; then
                rm -f "$lock_file"
            fi
        fi
    done

    # 인스턴스 파일 삭제
    rm -f "$INSTANCES_DIR/$CLAUDE_ID.json"
    log_success "Unregistered $CLAUDE_ID"
}

cmd_heartbeat() {
    local instance_file="$INSTANCES_DIR/$CLAUDE_ID.json"
    if [ -f "$instance_file" ]; then
        local tmp=$(mktemp)
        jq --arg ts "$(timestamp)" '.last_heartbeat = ($ts | tonumber)' "$instance_file" > "$tmp"
        mv "$tmp" "$instance_file"
        log_info "Heartbeat sent"
    else
        log_error "Not registered. Run 'register' first."
        exit 1
    fi
}

cmd_status() {
    log_info "=== Active Claude Instances ==="
    echo ""

    local current_time=$(timestamp)
    local timeout=600  # 10분

    for instance_file in "$INSTANCES_DIR"/*.json; do
        if [ -f "$instance_file" ]; then
            local id=$(jq -r '.id' "$instance_file")
            local desc=$(jq -r '.description' "$instance_file")
            local last_hb=$(jq -r '.last_heartbeat' "$instance_file")
            local status=$(jq -r '.status' "$instance_file")
            local registered=$(jq -r '.registered_at' "$instance_file")

            local age=$((current_time - last_hb))
            local status_icon="🟢"

            if [ $age -gt $timeout ]; then
                status_icon="🔴"
                status="inactive"
            elif [ $age -gt 300 ]; then
                status_icon="🟡"
                status="idle"
            fi

            if [ "$id" = "$CLAUDE_ID" ]; then
                echo -e "${GREEN}► $id (YOU)${NC}"
            else
                echo "  $id"
            fi
            echo "    Status: $status_icon $status"
            echo "    Task: $desc"
            echo "    Registered: $registered"
            echo "    Last seen: ${age}s ago"
            echo ""
        fi
    done

    # 잠금 현황
    log_info "=== Active Locks ==="
    local lock_count=0
    for lock_file in "$LOCKS_DIR"/*.lock; do
        if [ -f "$lock_file" ]; then
            local owner=$(jq -r '.owner' "$lock_file")
            local path=$(jq -r '.path' "$lock_file")
            local since=$(jq -r '.locked_at' "$lock_file")
            echo "  📁 $path"
            echo "     Locked by: $owner"
            echo "     Since: $since"
            lock_count=$((lock_count + 1))
        fi
    done

    if [ $lock_count -eq 0 ]; then
        echo "  No active locks"
    fi
}

# ============================================
# 파일 잠금 시스템
# ============================================

cmd_lock() {
    local file_path="$1"
    if [ -z "$file_path" ]; then
        log_error "Usage: collab.sh lock <file_path>"
        exit 1
    fi

    local encoded=$(encode_path "$file_path")
    local lock_file="$LOCKS_DIR/$encoded.lock"

    # 기존 잠금 확인
    if [ -f "$lock_file" ]; then
        local owner=$(jq -r '.owner' "$lock_file")
        local locked_at=$(jq -r '.locked_at' "$lock_file")

        if [ "$owner" = "$CLAUDE_ID" ]; then
            log_warn "You already have the lock on $file_path"
            return 0
        else
            log_error "File is locked by $owner since $locked_at"
            log_info "Wait or ask $owner to release the lock"
            exit 1
        fi
    fi

    # 잠금 획득
    cat > "$lock_file" << EOF
{
    "path": "$file_path",
    "owner": "$CLAUDE_ID",
    "locked_at": "$(datetime)",
    "timestamp": $(timestamp)
}
EOF

    log_success "Locked: $file_path"

    # 다른 인스턴스에게 알림
    cmd_broadcast "[LOCK] $CLAUDE_ID locked $file_path" "system"
}

cmd_unlock() {
    local file_path="$1"
    if [ -z "$file_path" ]; then
        log_error "Usage: collab.sh unlock <file_path>"
        exit 1
    fi

    local encoded=$(encode_path "$file_path")
    local lock_file="$LOCKS_DIR/$encoded.lock"

    if [ ! -f "$lock_file" ]; then
        log_warn "No lock exists for $file_path"
        return 0
    fi

    local owner=$(jq -r '.owner' "$lock_file")
    if [ "$owner" != "$CLAUDE_ID" ]; then
        log_error "Cannot unlock: owned by $owner"
        exit 1
    fi

    rm -f "$lock_file"
    log_success "Unlocked: $file_path"

    # 다른 인스턴스에게 알림
    cmd_broadcast "[UNLOCK] $CLAUDE_ID unlocked $file_path" "system"
}

cmd_check_lock() {
    local file_path="$1"
    local encoded=$(encode_path "$file_path")
    local lock_file="$LOCKS_DIR/$encoded.lock"

    if [ -f "$lock_file" ]; then
        local owner=$(jq -r '.owner' "$lock_file")
        if [ "$owner" = "$CLAUDE_ID" ]; then
            echo "locked_by_you"
        else
            echo "locked_by_$owner"
        fi
    else
        echo "unlocked"
    fi
}

# ============================================
# 메시지 시스템
# ============================================

cmd_send() {
    local target="$1"
    local message="$2"
    local msg_type="${3:-normal}"

    if [ -z "$target" ] || [ -z "$message" ]; then
        log_error "Usage: collab.sh send <target_claude_id> <message>"
        exit 1
    fi

    local target_dir="$MESSAGES_DIR/$target"
    mkdir -p "$target_dir"

    local msg_file="$target_dir/$(timestamp)_${CLAUDE_ID}.msg"
    cat > "$msg_file" << EOF
{
    "from": "$CLAUDE_ID",
    "to": "$target",
    "type": "$msg_type",
    "message": "$message",
    "timestamp": "$(datetime)",
    "read": false
}
EOF

    log_success "Message sent to $target"
}

cmd_broadcast() {
    local message="$1"
    local msg_type="${2:-normal}"

    for instance_file in "$INSTANCES_DIR"/*.json; do
        if [ -f "$instance_file" ]; then
            local target=$(jq -r '.id' "$instance_file")
            if [ "$target" != "$CLAUDE_ID" ]; then
                cmd_send "$target" "$message" "$msg_type" 2>/dev/null
            fi
        fi
    done

    if [ "$msg_type" != "system" ]; then
        log_success "Broadcast sent to all instances"
    fi
}

cmd_inbox() {
    local my_messages="$MESSAGES_DIR/$CLAUDE_ID"
    mkdir -p "$my_messages"

    log_info "=== Inbox for $CLAUDE_ID ==="
    echo ""

    local msg_count=0
    for msg_file in "$my_messages"/*.msg; do
        if [ -f "$msg_file" ]; then
            local from=$(jq -r '.from' "$msg_file")
            local message=$(jq -r '.message' "$msg_file")
            local ts=$(jq -r '.timestamp' "$msg_file")
            local msg_type=$(jq -r '.type' "$msg_file")
            local read_status=$(jq -r '.read' "$msg_file")

            local icon="📨"
            [ "$read_status" = "true" ] && icon="📭"
            [ "$msg_type" = "system" ] && icon="🔔"
            [ "$msg_type" = "urgent" ] && icon="🚨"

            echo "$icon [$ts] From: $from"
            echo "   $message"
            echo ""

            # 읽음 표시
            local tmp=$(mktemp)
            jq '.read = true' "$msg_file" > "$tmp"
            mv "$tmp" "$msg_file"

            msg_count=$((msg_count + 1))
        fi
    done

    if [ $msg_count -eq 0 ]; then
        echo "  No messages"
    fi
}

cmd_clear_inbox() {
    rm -f "$MESSAGES_DIR/$CLAUDE_ID"/*.msg 2>/dev/null
    log_success "Inbox cleared"
}

# ============================================
# 작업 상태
# ============================================

cmd_update_status() {
    local status="$1"
    local instance_file="$INSTANCES_DIR/$CLAUDE_ID.json"

    if [ -f "$instance_file" ]; then
        local tmp=$(mktemp)
        jq --arg status "$status" --arg ts "$(timestamp)" \
            '.current_task = $status | .last_heartbeat = ($ts | tonumber)' \
            "$instance_file" > "$tmp"
        mv "$tmp" "$instance_file"
        log_success "Status updated"
    else
        log_error "Not registered"
        exit 1
    fi
}

cmd_complete() {
    local description="$1"
    cmd_broadcast "[COMPLETE] $CLAUDE_ID finished: $description" "system"
    log_success "Completion notification sent"
}

# ============================================
# 동기화 및 충돌 처리
# ============================================

cmd_sync() {
    log_info "=== Syncing with remote ==="

    # Git pull
    log_info "Pulling latest changes..."
    if git pull --rebase 2>/dev/null; then
        log_success "Git sync complete"
    else
        log_warn "Git pull failed or nothing to pull"
    fi

    # Heartbeat
    cmd_heartbeat

    # 비활성 인스턴스의 잠금 정리
    log_info "Cleaning stale locks..."
    local current_time=$(timestamp)
    local timeout=600

    for lock_file in "$LOCKS_DIR"/*.lock; do
        if [ -f "$lock_file" ]; then
            local owner=$(jq -r '.owner' "$lock_file")
            local instance_file="$INSTANCES_DIR/$owner.json"

            if [ -f "$instance_file" ]; then
                local last_hb=$(jq -r '.last_heartbeat' "$instance_file")
                local age=$((current_time - last_hb))

                if [ $age -gt $timeout ]; then
                    local path=$(jq -r '.path' "$lock_file")
                    log_warn "Releasing stale lock: $path (owner: $owner inactive)"
                    rm -f "$lock_file"
                fi
            else
                # 인스턴스가 없으면 잠금 해제
                log_warn "Releasing orphan lock (owner not registered)"
                rm -f "$lock_file"
            fi
        fi
    done

    # 받은 메시지 확인
    echo ""
    cmd_inbox
}

# ============================================
# 에러 보고
# ============================================

cmd_report_error() {
    local error_msg="$1"
    local related_file="$2"

    local error_file="$ERRORS_DIR/$(timestamp)_${CLAUDE_ID}.json"
    cat > "$error_file" << EOF
{
    "reporter": "$CLAUDE_ID",
    "error": "$error_msg",
    "related_file": "$related_file",
    "timestamp": "$(datetime)"
}
EOF

    # 관련 파일 담당자에게 알림
    if [ -n "$related_file" ]; then
        local encoded=$(encode_path "$related_file")
        local lock_file="$LOCKS_DIR/$encoded.lock"

        if [ -f "$lock_file" ]; then
            local owner=$(jq -r '.owner' "$lock_file")
            cmd_send "$owner" "[ERROR] $error_msg (file: $related_file)" "urgent"
        fi
    fi

    cmd_broadcast "[ERROR] $CLAUDE_ID reported: $error_msg" "system"
    log_success "Error reported"
}

# ============================================
# 테스트/빌드 슬롯
# ============================================

cmd_request_test_slot() {
    local slot_file="$COLLAB_DIR/test_slot.lock"

    if [ -f "$slot_file" ]; then
        local owner=$(jq -r '.owner' "$slot_file")
        local ts=$(jq -r '.timestamp' "$slot_file")
        local age=$(($(timestamp) - ts))

        if [ $age -gt 300 ]; then
            # 5분 이상 된 슬롯은 해제
            rm -f "$slot_file"
        else
            log_warn "Test slot occupied by $owner (${age}s ago)"
            log_info "Waiting..."
            sleep 5
            cmd_request_test_slot
            return
        fi
    fi

    cat > "$slot_file" << EOF
{"owner": "$CLAUDE_ID", "timestamp": $(timestamp)}
EOF
    log_success "Test slot acquired"
}

cmd_release_test_slot() {
    rm -f "$COLLAB_DIR/test_slot.lock"
    log_success "Test slot released"
}

cmd_request_build_slot() {
    local slot_file="$COLLAB_DIR/build_slot.lock"

    if [ -f "$slot_file" ]; then
        local owner=$(jq -r '.owner' "$slot_file")
        log_warn "Build slot occupied by $owner"
        log_info "Waiting..."
        sleep 10
        cmd_request_build_slot
        return
    fi

    cat > "$slot_file" << EOF
{"owner": "$CLAUDE_ID", "timestamp": $(timestamp)}
EOF
    log_success "Build slot acquired"
}

cmd_release_build_slot() {
    rm -f "$COLLAB_DIR/build_slot.lock"
    log_success "Build slot released"
}

# ============================================
# 디버그 세션
# ============================================

cmd_debug_session() {
    local action="$1"
    local description="$2"
    local session_file="$COLLAB_DIR/debug_session.json"

    case "$action" in
        start)
            cat > "$session_file" << EOF
{
    "initiator": "$CLAUDE_ID",
    "description": "$description",
    "started_at": "$(datetime)",
    "participants": ["$CLAUDE_ID"]
}
EOF
            cmd_broadcast "[DEBUG SESSION] $CLAUDE_ID started: $description" "urgent"
            log_success "Debug session started"
            ;;
        join)
            if [ -f "$session_file" ]; then
                local tmp=$(mktemp)
                jq --arg id "$CLAUDE_ID" '.participants += [$id]' "$session_file" > "$tmp"
                mv "$tmp" "$session_file"
                cmd_broadcast "[DEBUG SESSION] $CLAUDE_ID joined the session" "system"
                log_success "Joined debug session"
            else
                log_error "No active debug session"
            fi
            ;;
        end)
            if [ -f "$session_file" ]; then
                rm -f "$session_file"
                cmd_broadcast "[DEBUG SESSION] Session ended by $CLAUDE_ID" "system"
                log_success "Debug session ended"
            fi
            ;;
        *)
            log_error "Usage: collab.sh debug-session [start|join|end] [description]"
            ;;
    esac
}

# ============================================
# 도움말
# ============================================

cmd_help() {
    cat << 'EOF'
Multi-Claude Collaboration Tool

Usage: collab.sh <command> [arguments]

Instance Management:
  register <desc>       Register this Claude instance
  unregister           Unregister and release all locks
  heartbeat            Send heartbeat signal
  status               Show all active instances and locks

File Locking:
  lock <file>          Acquire lock on a file
  unlock <file>        Release lock on a file
  check-lock <file>    Check lock status of a file

Messaging:
  send <id> <msg>      Send message to another Claude
  broadcast <msg>      Send message to all Claudes
  inbox                Check your messages
  clear-inbox          Clear all messages

Status Updates:
  update-status <msg>  Update your current task status
  complete <desc>      Announce task completion

Synchronization:
  sync                 Sync with remote and check messages

Error Handling:
  report-error <msg> [file]  Report an error

Resource Slots:
  request-test-slot    Request exclusive test slot
  release-test-slot    Release test slot
  request-build-slot   Request exclusive build slot
  release-build-slot   Release build slot

Debug Sessions:
  debug-session start <desc>  Start a debug session
  debug-session join          Join active debug session
  debug-session end           End debug session

Environment Variables:
  CLAUDE_ID            Override auto-generated instance ID

Examples:
  ./scripts/collab.sh register "Implementing login feature"
  ./scripts/collab.sh lock src/auth/login.ts
  ./scripts/collab.sh send claude-abc "Need help with API"
  ./scripts/collab.sh sync
EOF
}

# ============================================
# 메인
# ============================================

# 디렉토리 초기화
init_dirs

case "${1:-help}" in
    register)       cmd_register "$2" ;;
    unregister)     cmd_unregister ;;
    heartbeat)      cmd_heartbeat ;;
    status)         cmd_status ;;
    lock)           cmd_lock "$2" ;;
    unlock)         cmd_unlock "$2" ;;
    check-lock)     cmd_check_lock "$2" ;;
    send)           cmd_send "$2" "$3" ;;
    broadcast)      cmd_broadcast "$2" ;;
    inbox)          cmd_inbox ;;
    clear-inbox)    cmd_clear_inbox ;;
    update-status)  cmd_update_status "$2" ;;
    complete)       cmd_complete "$2" ;;
    sync)           cmd_sync ;;
    report-error)   cmd_report_error "$2" "$3" ;;
    request-test-slot)    cmd_request_test_slot ;;
    release-test-slot)    cmd_release_test_slot ;;
    request-build-slot)   cmd_request_build_slot ;;
    release-build-slot)   cmd_release_build_slot ;;
    debug-session)  cmd_debug_session "$2" "$3" ;;
    help|--help|-h) cmd_help ;;
    *)              log_error "Unknown command: $1"; cmd_help; exit 1 ;;
esac
