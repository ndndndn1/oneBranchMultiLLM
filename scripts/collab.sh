#!/bin/bash
# Multi-Claude Collaboration Script
# 여러 Claude Code 인스턴스 간 협업을 위한 도구
# Agent/MCP 친화적: --json 옵션으로 JSON 출력 지원

set -e

# JSON 모드 감지
JSON_MODE=false
if [ "$1" = "--json" ]; then
    JSON_MODE=true
    shift
fi

COLLAB_DIR=".claude-collab"
INSTANCES_DIR="$COLLAB_DIR/instances"
LOCKS_DIR="$COLLAB_DIR/locks"
MESSAGES_DIR="$COLLAB_DIR/messages"
TASKS_DIR="$COLLAB_DIR/tasks"
CONFLICTS_DIR="$COLLAB_DIR/conflicts"
ERRORS_DIR="$COLLAB_DIR/errors"

# 새로운 협업 디렉토리 (Code With Me 스타일)
PLANS_DIR="$COLLAB_DIR/plans"
EDITS_DIR="$COLLAB_DIR/edits"
DISCUSSIONS_DIR="$COLLAB_DIR/discussions"
PROPOSALS_DIR="$COLLAB_DIR/proposals"

# 현재 Claude 인스턴스 ID (환경변수 또는 자동 생성)
CLAUDE_ID="${CLAUDE_ID:-claude-$(hostname | md5sum | cut -c1-4)}"

# 색상 정의 (JSON 모드에서는 비활성화)
if [ "$JSON_MODE" = true ]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# 유틸리티 함수들
log_info() {
    if [ "$JSON_MODE" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}
log_success() {
    if [ "$JSON_MODE" = false ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}
log_warn() {
    if [ "$JSON_MODE" = false ]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}
log_error() {
    if [ "$JSON_MODE" = false ]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

# JSON 출력 헬퍼
json_output() {
    if [ "$JSON_MODE" = true ]; then
        echo "$1"
    fi
}

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
    # 협업 기반 디렉토리
    mkdir -p "$PLANS_DIR" "$EDITS_DIR" "$DISCUSSIONS_DIR" "$PROPOSALS_DIR"
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
# 계획 공유 시스템 (Code With Me 스타일)
# ============================================

cmd_share_plan() {
    local title="$1"
    local description="$2"
    local target_files="$3"

    if [ -z "$title" ]; then
        log_error "Usage: collab.sh share-plan <title> [description] [target_files]"
        exit 1
    fi

    local plan_id="$(timestamp)_${CLAUDE_ID}"
    local plan_file="$PLANS_DIR/${plan_id}.json"

    cat > "$plan_file" << EOF
{
    "id": "$plan_id",
    "author": "$CLAUDE_ID",
    "title": "$title",
    "description": "$description",
    "target_files": "$target_files",
    "status": "proposed",
    "created_at": "$(datetime)",
    "comments": [],
    "approvals": [],
    "implementation_started": false
}
EOF

    cmd_broadcast "[PLAN] $CLAUDE_ID shared a plan: $title" "system"
    log_success "Plan shared: $title (ID: $plan_id)"
    log_info "Other Claudes can now review and comment on this plan"
}

cmd_view_plans() {
    log_info "=== Shared Plans ==="
    echo ""

    for plan_file in "$PLANS_DIR"/*.json; do
        if [ -f "$plan_file" ]; then
            local id=$(jq -r '.id' "$plan_file")
            local author=$(jq -r '.author' "$plan_file")
            local title=$(jq -r '.title' "$plan_file")
            local description=$(jq -r '.description' "$plan_file")
            local target_files=$(jq -r '.target_files' "$plan_file")
            local status=$(jq -r '.status' "$plan_file")
            local created=$(jq -r '.created_at' "$plan_file")
            local approval_count=$(jq '.approvals | length' "$plan_file")
            local comment_count=$(jq '.comments | length' "$plan_file")

            local status_icon="📋"
            [ "$status" = "approved" ] && status_icon="✅"
            [ "$status" = "in_progress" ] && status_icon="🔨"
            [ "$status" = "completed" ] && status_icon="🎉"
            [ "$status" = "rejected" ] && status_icon="❌"

            echo "$status_icon [$status] $title"
            echo "   Author: $author | Created: $created"
            [ -n "$description" ] && [ "$description" != "null" ] && echo "   Description: $description"
            [ -n "$target_files" ] && [ "$target_files" != "null" ] && echo "   Target files: $target_files"
            echo "   Comments: $comment_count | Approvals: $approval_count"
            echo "   Plan ID: $id"
            echo ""
        fi
    done
}

cmd_comment_plan() {
    local plan_id="$1"
    local comment="$2"

    if [ -z "$plan_id" ] || [ -z "$comment" ]; then
        log_error "Usage: collab.sh comment-plan <plan_id> <comment>"
        exit 1
    fi

    local plan_file="$PLANS_DIR/${plan_id}.json"
    if [ ! -f "$plan_file" ]; then
        log_error "Plan not found: $plan_id"
        exit 1
    fi

    local tmp=$(mktemp)
    local new_comment="{\"author\": \"$CLAUDE_ID\", \"text\": \"$comment\", \"timestamp\": \"$(datetime)\"}"
    jq --argjson comment "$new_comment" '.comments += [$comment]' "$plan_file" > "$tmp"
    mv "$tmp" "$plan_file"

    local author=$(jq -r '.author' "$plan_file")
    cmd_send "$author" "[COMMENT] $CLAUDE_ID commented on your plan: $comment" "normal"
    log_success "Comment added to plan"
}

cmd_approve_plan() {
    local plan_id="$1"

    if [ -z "$plan_id" ]; then
        log_error "Usage: collab.sh approve-plan <plan_id>"
        exit 1
    fi

    local plan_file="$PLANS_DIR/${plan_id}.json"
    if [ ! -f "$plan_file" ]; then
        log_error "Plan not found: $plan_id"
        exit 1
    fi

    local tmp=$(mktemp)
    jq --arg approver "$CLAUDE_ID" '.approvals += [$approver] | .approvals = (.approvals | unique)' "$plan_file" > "$tmp"
    mv "$tmp" "$plan_file"

    local author=$(jq -r '.author' "$plan_file")
    local title=$(jq -r '.title' "$plan_file")
    cmd_send "$author" "[APPROVED] $CLAUDE_ID approved your plan: $title" "normal"
    log_success "Plan approved"
}

cmd_start_plan() {
    local plan_id="$1"

    if [ -z "$plan_id" ]; then
        log_error "Usage: collab.sh start-plan <plan_id>"
        exit 1
    fi

    local plan_file="$PLANS_DIR/${plan_id}.json"
    if [ ! -f "$plan_file" ]; then
        log_error "Plan not found: $plan_id"
        exit 1
    fi

    local tmp=$(mktemp)
    jq '.status = "in_progress" | .implementation_started = true | .started_at = "'"$(datetime)"'"' "$plan_file" > "$tmp"
    mv "$tmp" "$plan_file"

    local title=$(jq -r '.title' "$plan_file")
    cmd_broadcast "[IMPLEMENTATION] $CLAUDE_ID started implementing: $title" "system"
    log_success "Plan implementation started"
}

cmd_complete_plan() {
    local plan_id="$1"

    if [ -z "$plan_id" ]; then
        log_error "Usage: collab.sh complete-plan <plan_id>"
        exit 1
    fi

    local plan_file="$PLANS_DIR/${plan_id}.json"
    if [ ! -f "$plan_file" ]; then
        log_error "Plan not found: $plan_id"
        exit 1
    fi

    local tmp=$(mktemp)
    jq '.status = "completed" | .completed_at = "'"$(datetime)"'"' "$plan_file" > "$tmp"
    mv "$tmp" "$plan_file"

    local title=$(jq -r '.title' "$plan_file")
    cmd_broadcast "[COMPLETED] $CLAUDE_ID completed plan: $title" "system"
    log_success "Plan marked as completed"
}

# ============================================
# 실시간 수정 공유 (Live Editing)
# ============================================

cmd_share_edit() {
    local file_path="$1"
    local change_type="$2"  # add, modify, delete, refactor
    local description="$3"

    if [ -z "$file_path" ] || [ -z "$description" ]; then
        log_error "Usage: collab.sh share-edit <file_path> <change_type> <description>"
        log_info "Change types: add, modify, delete, refactor"
        exit 1
    fi

    local encoded=$(encode_path "$file_path")
    local edit_file="$EDITS_DIR/${encoded}_${CLAUDE_ID}.json"

    cat > "$edit_file" << EOF
{
    "file": "$file_path",
    "editor": "$CLAUDE_ID",
    "change_type": "${change_type:-modify}",
    "description": "$description",
    "started_at": "$(datetime)",
    "timestamp": $(timestamp),
    "status": "in_progress"
}
EOF

    log_success "Edit shared: $file_path"
    log_info "Other Claudes can see you're editing this file"

    # 같은 파일을 수정 중인 다른 Claude가 있는지 확인
    local has_conflict=false
    local conflict_editors=""
    for other_edit in "$EDITS_DIR"/${encoded}_*.json; do
        if [ -f "$other_edit" ] && [ "$other_edit" != "$edit_file" ]; then
            local other_editor=$(jq -r '.editor' "$other_edit")
            local other_status=$(jq -r '.status' "$other_edit")
            if [ "$other_status" = "in_progress" ]; then
                has_conflict=true
                conflict_editors="$conflict_editors $other_editor"
                log_warn "⚠️  $other_editor is also editing $file_path!"
                cmd_send "$other_editor" "[CONCURRENT EDIT] $CLAUDE_ID is also editing $file_path - let's coordinate!" "urgent"
            fi
        fi
    done

    if [ "$has_conflict" = true ]; then
        log_warn "🔴 POTENTIAL CONFLICT DETECTED!"
        log_info "To start conflict resolution discussion, run:"
        log_info "  ./scripts/collab.sh report-conflict \"$file_path\" \"설명\""
        log_info ""
        log_info "Or coordinate directly with:$conflict_editors"
    fi
}

cmd_view_edits() {
    log_info "=== Active Edits ==="
    echo ""

    local current_time=$(timestamp)

    for edit_file in "$EDITS_DIR"/*.json; do
        if [ -f "$edit_file" ]; then
            local file=$(jq -r '.file' "$edit_file")
            local editor=$(jq -r '.editor' "$edit_file")
            local change_type=$(jq -r '.change_type' "$edit_file")
            local description=$(jq -r '.description' "$edit_file")
            local started=$(jq -r '.started_at' "$edit_file")
            local ts=$(jq -r '.timestamp' "$edit_file")
            local status=$(jq -r '.status' "$edit_file")
            local age=$((current_time - ts))

            # 30분 이상 된 편집은 비활성으로 표시
            if [ $age -gt 1800 ]; then
                status="stale"
            fi

            local type_icon="📝"
            [ "$change_type" = "add" ] && type_icon="➕"
            [ "$change_type" = "delete" ] && type_icon="➖"
            [ "$change_type" = "refactor" ] && type_icon="🔄"

            local status_icon="🔨"
            [ "$status" = "completed" ] && status_icon="✅"
            [ "$status" = "stale" ] && status_icon="⏸️"

            if [ "$editor" = "$CLAUDE_ID" ]; then
                echo -e "${GREEN}$status_icon $type_icon $file (YOU)${NC}"
            else
                echo "$status_icon $type_icon $file"
            fi
            echo "   Editor: $editor | Type: $change_type"
            echo "   Description: $description"
            echo "   Started: $started (${age}s ago)"
            echo ""
        fi
    done
}

cmd_finish_edit() {
    local file_path="$1"

    if [ -z "$file_path" ]; then
        log_error "Usage: collab.sh finish-edit <file_path>"
        exit 1
    fi

    local encoded=$(encode_path "$file_path")
    local edit_file="$EDITS_DIR/${encoded}_${CLAUDE_ID}.json"

    if [ -f "$edit_file" ]; then
        local tmp=$(mktemp)
        jq '.status = "completed" | .finished_at = "'"$(datetime)"'"' "$edit_file" > "$tmp"
        mv "$tmp" "$edit_file"
        log_success "Edit finished: $file_path"
    else
        log_warn "No active edit found for $file_path"
    fi
}

# ============================================
# 협업적 사고 (Collaborative Thinking)
# ============================================

cmd_propose() {
    local proposal_type="$1"  # approach, alternative, optimization, question
    local title="$2"
    local details="$3"

    if [ -z "$proposal_type" ] || [ -z "$title" ]; then
        log_error "Usage: collab.sh propose <type> <title> [details]"
        log_info "Types: approach, alternative, optimization, question"
        exit 1
    fi

    local proposal_id="$(timestamp)_${CLAUDE_ID}"
    local proposal_file="$PROPOSALS_DIR/${proposal_id}.json"

    cat > "$proposal_file" << EOF
{
    "id": "$proposal_id",
    "type": "$proposal_type",
    "author": "$CLAUDE_ID",
    "title": "$title",
    "details": "$details",
    "created_at": "$(datetime)",
    "votes": {"agree": [], "disagree": []},
    "responses": [],
    "status": "open"
}
EOF

    local type_icon="💡"
    [ "$proposal_type" = "alternative" ] && type_icon="🔀"
    [ "$proposal_type" = "optimization" ] && type_icon="⚡"
    [ "$proposal_type" = "question" ] && type_icon="❓"

    cmd_broadcast "[PROPOSAL] $type_icon $CLAUDE_ID proposes: $title" "normal"
    log_success "Proposal submitted: $title (ID: $proposal_id)"
    log_info "Other Claudes can vote agree/disagree or respond"
}

cmd_view_proposals() {
    log_info "=== Active Proposals ==="
    echo ""

    for proposal_file in "$PROPOSALS_DIR"/*.json; do
        if [ -f "$proposal_file" ]; then
            local id=$(jq -r '.id' "$proposal_file")
            local ptype=$(jq -r '.type' "$proposal_file")
            local author=$(jq -r '.author' "$proposal_file")
            local title=$(jq -r '.title' "$proposal_file")
            local details=$(jq -r '.details' "$proposal_file")
            local created=$(jq -r '.created_at' "$proposal_file")
            local status=$(jq -r '.status' "$proposal_file")
            local agrees=$(jq '.votes.agree | length' "$proposal_file")
            local disagrees=$(jq '.votes.disagree | length' "$proposal_file")
            local response_count=$(jq '.responses | length' "$proposal_file")

            local type_icon="💡"
            [ "$ptype" = "alternative" ] && type_icon="🔀"
            [ "$ptype" = "optimization" ] && type_icon="⚡"
            [ "$ptype" = "question" ] && type_icon="❓"

            echo "$type_icon [$ptype] $title"
            echo "   Author: $author | Status: $status"
            [ -n "$details" ] && [ "$details" != "null" ] && echo "   Details: $details"
            echo "   Votes: 👍 $agrees | 👎 $disagrees | Responses: $response_count"
            echo "   Proposal ID: $id"
            echo ""
        fi
    done
}

cmd_vote() {
    local proposal_id="$1"
    local vote="$2"  # agree or disagree

    if [ -z "$proposal_id" ] || [ -z "$vote" ]; then
        log_error "Usage: collab.sh vote <proposal_id> <agree|disagree>"
        exit 1
    fi

    local proposal_file="$PROPOSALS_DIR/${proposal_id}.json"
    if [ ! -f "$proposal_file" ]; then
        log_error "Proposal not found: $proposal_id"
        exit 1
    fi

    local tmp=$(mktemp)
    if [ "$vote" = "agree" ]; then
        jq --arg voter "$CLAUDE_ID" '.votes.agree += [$voter] | .votes.agree = (.votes.agree | unique)' "$proposal_file" > "$tmp"
    else
        jq --arg voter "$CLAUDE_ID" '.votes.disagree += [$voter] | .votes.disagree = (.votes.disagree | unique)' "$proposal_file" > "$tmp"
    fi
    mv "$tmp" "$proposal_file"

    local author=$(jq -r '.author' "$proposal_file")
    local title=$(jq -r '.title' "$proposal_file")
    cmd_send "$author" "[VOTE] $CLAUDE_ID voted $vote on: $title" "normal"
    log_success "Vote recorded: $vote"
}

cmd_respond() {
    local proposal_id="$1"
    local response="$2"

    if [ -z "$proposal_id" ] || [ -z "$response" ]; then
        log_error "Usage: collab.sh respond <proposal_id> <response>"
        exit 1
    fi

    local proposal_file="$PROPOSALS_DIR/${proposal_id}.json"
    if [ ! -f "$proposal_file" ]; then
        log_error "Proposal not found: $proposal_id"
        exit 1
    fi

    local tmp=$(mktemp)
    local new_response="{\"author\": \"$CLAUDE_ID\", \"text\": \"$response\", \"timestamp\": \"$(datetime)\"}"
    jq --argjson response "$new_response" '.responses += [$response]' "$proposal_file" > "$tmp"
    mv "$tmp" "$proposal_file"

    local author=$(jq -r '.author' "$proposal_file")
    cmd_send "$author" "[RESPONSE] $CLAUDE_ID responded to your proposal: $response" "normal"
    log_success "Response added"
}

# ============================================
# 토론 시스템 (Discussion Threads)
# ============================================

cmd_discuss() {
    local topic="$1"
    local initial_message="$2"

    if [ -z "$topic" ]; then
        log_error "Usage: collab.sh discuss <topic> [initial_message]"
        exit 1
    fi

    local discussion_id="$(timestamp)_${CLAUDE_ID}"
    local discussion_file="$DISCUSSIONS_DIR/${discussion_id}.json"

    cat > "$discussion_file" << EOF
{
    "id": "$discussion_id",
    "topic": "$topic",
    "initiator": "$CLAUDE_ID",
    "created_at": "$(datetime)",
    "messages": [
        {
            "author": "$CLAUDE_ID",
            "text": "${initial_message:-Let's discuss: $topic}",
            "timestamp": "$(datetime)"
        }
    ],
    "participants": ["$CLAUDE_ID"],
    "status": "active"
}
EOF

    cmd_broadcast "[DISCUSSION] 💬 $CLAUDE_ID started a discussion: $topic" "normal"
    log_success "Discussion started: $topic (ID: $discussion_id)"
}

cmd_view_discussions() {
    log_info "=== Active Discussions ==="
    echo ""

    for discussion_file in "$DISCUSSIONS_DIR"/*.json; do
        if [ -f "$discussion_file" ]; then
            local id=$(jq -r '.id' "$discussion_file")
            local topic=$(jq -r '.topic' "$discussion_file")
            local initiator=$(jq -r '.initiator' "$discussion_file")
            local created=$(jq -r '.created_at' "$discussion_file")
            local status=$(jq -r '.status' "$discussion_file")
            local msg_count=$(jq '.messages | length' "$discussion_file")
            local participants=$(jq -r '.participants | join(", ")' "$discussion_file")

            local status_icon="💬"
            [ "$status" = "resolved" ] && status_icon="✅"
            [ "$status" = "closed" ] && status_icon="🔒"

            echo "$status_icon $topic"
            echo "   Started by: $initiator | Messages: $msg_count"
            echo "   Participants: $participants"
            echo "   Discussion ID: $id"
            echo ""
        fi
    done
}

cmd_reply() {
    local discussion_id="$1"
    local message="$2"

    if [ -z "$discussion_id" ] || [ -z "$message" ]; then
        log_error "Usage: collab.sh reply <discussion_id> <message>"
        exit 1
    fi

    local discussion_file="$DISCUSSIONS_DIR/${discussion_id}.json"
    if [ ! -f "$discussion_file" ]; then
        log_error "Discussion not found: $discussion_id"
        exit 1
    fi

    local tmp=$(mktemp)
    local new_message="{\"author\": \"$CLAUDE_ID\", \"text\": \"$message\", \"timestamp\": \"$(datetime)\"}"
    jq --argjson msg "$new_message" --arg participant "$CLAUDE_ID" \
        '.messages += [$msg] | .participants += [$participant] | .participants = (.participants | unique)' \
        "$discussion_file" > "$tmp"
    mv "$tmp" "$discussion_file"

    # 다른 참여자들에게 알림
    local participants=$(jq -r '.participants[]' "$discussion_file")
    local topic=$(jq -r '.topic' "$discussion_file")
    for participant in $participants; do
        if [ "$participant" != "$CLAUDE_ID" ]; then
            cmd_send "$participant" "[REPLY] $CLAUDE_ID in '$topic': $message" "normal"
        fi
    done

    log_success "Reply added to discussion"
}

cmd_resolve_discussion() {
    local discussion_id="$1"
    local resolution="$2"

    if [ -z "$discussion_id" ]; then
        log_error "Usage: collab.sh resolve-discussion <discussion_id> [resolution]"
        exit 1
    fi

    local discussion_file="$DISCUSSIONS_DIR/${discussion_id}.json"
    if [ ! -f "$discussion_file" ]; then
        log_error "Discussion not found: $discussion_id"
        exit 1
    fi

    local tmp=$(mktemp)
    jq --arg resolution "${resolution:-Resolved}" \
        '.status = "resolved" | .resolution = $resolution | .resolved_at = "'"$(datetime)"'" | .resolved_by = "'"$CLAUDE_ID"'"' \
        "$discussion_file" > "$tmp"
    mv "$tmp" "$discussion_file"

    local topic=$(jq -r '.topic' "$discussion_file")
    cmd_broadcast "[RESOLVED] Discussion '$topic' resolved by $CLAUDE_ID: ${resolution:-Resolved}" "system"
    log_success "Discussion resolved"
}

# ============================================
# 협의적 충돌 해결 (Collaborative Conflict Resolution)
# ============================================

cmd_report_conflict() {
    local file_path="$1"
    local description="$2"
    local other_editor="$3"  # 충돌 상대방 (optional, auto-detect if empty)

    if [ -z "$file_path" ]; then
        log_error "Usage: collab.sh report-conflict <file_path> [description] [other_editor]"
        exit 1
    fi

    local encoded=$(encode_path "$file_path")

    # 충돌 상대방 자동 감지
    if [ -z "$other_editor" ]; then
        for other_edit in "$EDITS_DIR"/${encoded}_*.json; do
            if [ -f "$other_edit" ]; then
                local editor=$(jq -r '.editor' "$other_edit")
                local status=$(jq -r '.status' "$other_edit")
                if [ "$editor" != "$CLAUDE_ID" ] && [ "$status" = "in_progress" ]; then
                    other_editor="$editor"
                    break
                fi
            fi
        done
    fi

    if [ -z "$other_editor" ]; then
        log_warn "No other editor detected for $file_path"
        log_info "If you know who you're conflicting with, use: collab.sh report-conflict <file> <desc> <other_claude_id>"
    fi

    # 충돌 ID 생성
    local conflict_id="$(timestamp)_${encoded}"
    local conflict_file="$CONFLICTS_DIR/${conflict_id}.json"

    cat > "$conflict_file" << EOF
{
    "id": "$conflict_id",
    "file": "$file_path",
    "reporter": "$CLAUDE_ID",
    "other_party": "$other_editor",
    "description": "${description:-Concurrent edit conflict}",
    "reported_at": "$(datetime)",
    "status": "open",
    "resolutions": [],
    "participants": ["$CLAUDE_ID"${other_editor:+, \"$other_editor\"}],
    "discussion_messages": [
        {
            "author": "$CLAUDE_ID",
            "text": "충돌 보고: ${description:-$file_path 파일에서 동시 수정 충돌이 발생했습니다. 함께 해결 방안을 논의해주세요.}",
            "timestamp": "$(datetime)"
        }
    ],
    "selected_resolution": null
}
EOF

    log_success "Conflict reported: $file_path (ID: $conflict_id)"
    log_info "Other Claudes can now propose resolutions"

    # 관련자들에게 알림
    if [ -n "$other_editor" ]; then
        cmd_send "$other_editor" "[CONFLICT] 🔴 $CLAUDE_ID reported a conflict on $file_path - Please discuss resolution!" "urgent"
    fi
    cmd_broadcast "[CONFLICT] 🔴 Conflict reported on $file_path by $CLAUDE_ID - Discussion needed!" "urgent"

    echo "$conflict_id"
}

cmd_view_conflicts() {
    log_info "=== Active Conflicts ==="
    echo ""

    local found=0
    for conflict_file in "$CONFLICTS_DIR"/*.json; do
        if [ -f "$conflict_file" ]; then
            local id=$(jq -r '.id' "$conflict_file")
            local file=$(jq -r '.file' "$conflict_file")
            local reporter=$(jq -r '.reporter' "$conflict_file")
            local other_party=$(jq -r '.other_party' "$conflict_file")
            local description=$(jq -r '.description' "$conflict_file")
            local status=$(jq -r '.status' "$conflict_file")
            local reported_at=$(jq -r '.reported_at' "$conflict_file")
            local resolution_count=$(jq '.resolutions | length' "$conflict_file")
            local selected=$(jq -r '.selected_resolution' "$conflict_file")

            local status_icon="🔴"
            [ "$status" = "discussing" ] && status_icon="💬"
            [ "$status" = "voting" ] && status_icon="🗳️"
            [ "$status" = "resolved" ] && status_icon="✅"

            echo "$status_icon [$status] $file"
            echo "   Reporter: $reporter"
            [ "$other_party" != "null" ] && [ -n "$other_party" ] && echo "   Other party: $other_party"
            echo "   Description: $description"
            echo "   Reported: $reported_at"
            echo "   Proposed resolutions: $resolution_count"
            [ "$selected" != "null" ] && echo "   Selected resolution: $selected"
            echo "   Conflict ID: $id"
            echo ""
            found=$((found + 1))
        fi
    done

    if [ $found -eq 0 ]; then
        echo "  No active conflicts"
    fi
}

cmd_propose_resolution() {
    local conflict_id="$1"
    local strategy="$2"  # split-regions, sequential, merge, delegate, other
    local description="$3"

    if [ -z "$conflict_id" ] || [ -z "$strategy" ]; then
        log_error "Usage: collab.sh propose-resolution <conflict_id> <strategy> [description]"
        log_info "Strategies:"
        log_info "  split-regions  - 파일 내 작업 영역 분리 (예: 다른 함수/섹션 담당)"
        log_info "  sequential     - 순차 작업 (한 Claude가 먼저 완료 후 다른 Claude 작업)"
        log_info "  merge          - 공동 작업 후 수동 병합"
        log_info "  delegate       - 한 Claude에게 전체 작업 위임"
        log_info "  other          - 기타 (description에 상세 기술)"
        exit 1
    fi

    local conflict_file="$CONFLICTS_DIR/${conflict_id}.json"
    if [ ! -f "$conflict_file" ]; then
        log_error "Conflict not found: $conflict_id"
        exit 1
    fi

    local resolution_id="${CLAUDE_ID}_$(timestamp)"
    local tmp=$(mktemp)

    local new_resolution=$(cat << EOF
{
    "id": "$resolution_id",
    "proposer": "$CLAUDE_ID",
    "strategy": "$strategy",
    "description": "${description:-No additional description}",
    "proposed_at": "$(datetime)",
    "votes": {"agree": [], "disagree": []}
}
EOF
)

    jq --argjson resolution "$new_resolution" \
        '.resolutions += [$resolution] | .status = "voting"' \
        "$conflict_file" > "$tmp"
    mv "$tmp" "$conflict_file"

    log_success "Resolution proposed: $strategy (ID: $resolution_id)"

    # 참여자들에게 알림
    local participants=$(jq -r '.participants[]' "$conflict_file")
    local file=$(jq -r '.file' "$conflict_file")
    for participant in $participants; do
        if [ "$participant" != "$CLAUDE_ID" ]; then
            cmd_send "$participant" "[RESOLUTION] 🗳️ $CLAUDE_ID proposed '$strategy' for $file conflict - Please vote!" "normal"
        fi
    done

    cmd_broadcast "[RESOLUTION] 🗳️ $CLAUDE_ID proposed '$strategy' resolution for conflict on $file" "system"
}

cmd_vote_resolution() {
    local conflict_id="$1"
    local resolution_id="$2"
    local vote="$3"  # agree or disagree

    if [ -z "$conflict_id" ] || [ -z "$resolution_id" ] || [ -z "$vote" ]; then
        log_error "Usage: collab.sh vote-resolution <conflict_id> <resolution_id> <agree|disagree>"
        exit 1
    fi

    local conflict_file="$CONFLICTS_DIR/${conflict_id}.json"
    if [ ! -f "$conflict_file" ]; then
        log_error "Conflict not found: $conflict_id"
        exit 1
    fi

    local tmp=$(mktemp)
    if [ "$vote" = "agree" ]; then
        jq --arg rid "$resolution_id" --arg voter "$CLAUDE_ID" \
            '(.resolutions[] | select(.id == $rid) | .votes.agree) += [$voter] | (.resolutions[] | select(.id == $rid) | .votes.agree) |= unique' \
            "$conflict_file" > "$tmp"
    else
        jq --arg rid "$resolution_id" --arg voter "$CLAUDE_ID" \
            '(.resolutions[] | select(.id == $rid) | .votes.disagree) += [$voter] | (.resolutions[] | select(.id == $rid) | .votes.disagree) |= unique' \
            "$conflict_file" > "$tmp"
    fi
    mv "$tmp" "$conflict_file"

    log_success "Vote recorded: $vote for resolution $resolution_id"

    # 제안자에게 알림
    local proposer=$(jq -r --arg rid "$resolution_id" '.resolutions[] | select(.id == $rid) | .proposer' "$conflict_file")
    if [ -n "$proposer" ] && [ "$proposer" != "$CLAUDE_ID" ]; then
        cmd_send "$proposer" "[VOTE] $CLAUDE_ID voted '$vote' on your resolution proposal" "normal"
    fi
}

cmd_add_conflict_message() {
    local conflict_id="$1"
    local message="$2"

    if [ -z "$conflict_id" ] || [ -z "$message" ]; then
        log_error "Usage: collab.sh conflict-message <conflict_id> <message>"
        exit 1
    fi

    local conflict_file="$CONFLICTS_DIR/${conflict_id}.json"
    if [ ! -f "$conflict_file" ]; then
        log_error "Conflict not found: $conflict_id"
        exit 1
    fi

    local tmp=$(mktemp)
    local new_message="{\"author\": \"$CLAUDE_ID\", \"text\": \"$message\", \"timestamp\": \"$(datetime)\"}"
    jq --argjson msg "$new_message" --arg participant "$CLAUDE_ID" \
        '.discussion_messages += [$msg] | .participants += [$participant] | .participants = (.participants | unique) | .status = "discussing"' \
        "$conflict_file" > "$tmp"
    mv "$tmp" "$conflict_file"

    log_success "Message added to conflict discussion"

    # 다른 참여자들에게 알림
    local participants=$(jq -r '.participants[]' "$conflict_file")
    local file=$(jq -r '.file' "$conflict_file")
    for participant in $participants; do
        if [ "$participant" != "$CLAUDE_ID" ]; then
            cmd_send "$participant" "[CONFLICT DISCUSSION] $CLAUDE_ID on $file: $message" "normal"
        fi
    done
}

cmd_resolve_conflict() {
    local conflict_id="$1"
    local resolution_id="$2"
    local final_notes="$3"

    if [ -z "$conflict_id" ]; then
        log_error "Usage: collab.sh resolve-conflict <conflict_id> [resolution_id] [final_notes]"
        exit 1
    fi

    local conflict_file="$CONFLICTS_DIR/${conflict_id}.json"
    if [ ! -f "$conflict_file" ]; then
        log_error "Conflict not found: $conflict_id"
        exit 1
    fi

    local tmp=$(mktemp)

    # resolution_id가 제공되지 않으면 가장 많은 agree 투표를 받은 것 선택
    if [ -z "$resolution_id" ]; then
        resolution_id=$(jq -r '.resolutions | sort_by(.votes.agree | length) | reverse | .[0].id // empty' "$conflict_file")
    fi

    jq --arg rid "$resolution_id" --arg notes "${final_notes:-Conflict resolved}" \
        '.status = "resolved" | .selected_resolution = $rid | .resolved_at = "'"$(datetime)"'" | .resolved_by = "'"$CLAUDE_ID"'" | .final_notes = $notes' \
        "$conflict_file" > "$tmp"
    mv "$tmp" "$conflict_file"

    local file=$(jq -r '.file' "$conflict_file")
    local strategy=""
    if [ -n "$resolution_id" ]; then
        strategy=$(jq -r --arg rid "$resolution_id" '.resolutions[] | select(.id == $rid) | .strategy' "$conflict_file")
    fi

    log_success "Conflict resolved: $file"
    [ -n "$strategy" ] && log_info "Applied strategy: $strategy"

    cmd_broadcast "[CONFLICT RESOLVED] ✅ $file conflict resolved by $CLAUDE_ID${strategy:+ using '$strategy' strategy}" "system"
}

cmd_view_conflict_detail() {
    local conflict_id="$1"

    if [ -z "$conflict_id" ]; then
        log_error "Usage: collab.sh conflict-detail <conflict_id>"
        exit 1
    fi

    local conflict_file="$CONFLICTS_DIR/${conflict_id}.json"
    if [ ! -f "$conflict_file" ]; then
        log_error "Conflict not found: $conflict_id"
        exit 1
    fi

    log_info "=== Conflict Detail ==="
    echo ""

    local file=$(jq -r '.file' "$conflict_file")
    local status=$(jq -r '.status' "$conflict_file")
    local reporter=$(jq -r '.reporter' "$conflict_file")
    local description=$(jq -r '.description' "$conflict_file")

    echo "📁 File: $file"
    echo "📊 Status: $status"
    echo "👤 Reporter: $reporter"
    echo "📝 Description: $description"
    echo ""

    log_info "=== Discussion Messages ==="
    jq -r '.discussion_messages[] | "[\(.timestamp)] \(.author): \(.text)"' "$conflict_file"
    echo ""

    log_info "=== Proposed Resolutions ==="
    local resolutions=$(jq -r '.resolutions[] | "[\(.strategy)] by \(.proposer) - 👍 \(.votes.agree | length) / 👎 \(.votes.disagree | length)\n   ID: \(.id)\n   \(.description)"' "$conflict_file")
    if [ -n "$resolutions" ]; then
        echo "$resolutions"
    else
        echo "  No resolutions proposed yet"
    fi
}

# ============================================
# 협업 요약 (Collaboration Summary)
# ============================================

cmd_overview() {
    local current_time=$(timestamp)

    # 활성 인스턴스 수집
    local active_count=0
    local instances_json="[]"
    for instance_file in "$INSTANCES_DIR"/*.json; do
        if [ -f "$instance_file" ]; then
            local last_hb=$(jq -r '.last_heartbeat' "$instance_file")
            local age=$((current_time - last_hb))
            if [ $age -lt 600 ]; then
                active_count=$((active_count + 1))
                local inst_data=$(jq --arg is_me "$([ "$(jq -r '.id' "$instance_file")" = "$CLAUDE_ID" ] && echo true || echo false)" \
                    '. + {is_me: ($is_me == "true")}' "$instance_file")
                instances_json=$(echo "$instances_json" | jq --argjson inst "$inst_data" '. += [$inst]')
            fi
        fi
    done

    # 진행 중인 계획 수집
    local plans_in_progress=0
    local plans_json="[]"
    for plan_file in "$PLANS_DIR"/*.json; do
        if [ -f "$plan_file" ]; then
            local status=$(jq -r '.status' "$plan_file")
            if [ "$status" = "in_progress" ] || [ "$status" = "proposed" ]; then
                [ "$status" = "in_progress" ] && plans_in_progress=$((plans_in_progress + 1))
                plans_json=$(echo "$plans_json" | jq --slurpfile plan "$plan_file" '. += $plan')
            fi
        fi
    done

    # 활성 편집 수집
    local active_edits=0
    local edits_json="[]"
    for edit_file in "$EDITS_DIR"/*.json; do
        if [ -f "$edit_file" ]; then
            local status=$(jq -r '.status' "$edit_file")
            local ts=$(jq -r '.timestamp' "$edit_file")
            local age=$((current_time - ts))
            if [ "$status" = "in_progress" ] && [ $age -lt 1800 ]; then
                active_edits=$((active_edits + 1))
                edits_json=$(echo "$edits_json" | jq --slurpfile edit "$edit_file" '. += $edit')
            fi
        fi
    done

    # 열린 제안 수집
    local open_proposals=0
    local proposals_json="[]"
    for proposal_file in "$PROPOSALS_DIR"/*.json; do
        if [ -f "$proposal_file" ]; then
            local status=$(jq -r '.status' "$proposal_file")
            if [ "$status" = "open" ]; then
                open_proposals=$((open_proposals + 1))
                proposals_json=$(echo "$proposals_json" | jq --slurpfile prop "$proposal_file" '. += $prop')
            fi
        fi
    done

    # 활성 토론 수집
    local active_discussions=0
    local discussions_json="[]"
    for discussion_file in "$DISCUSSIONS_DIR"/*.json; do
        if [ -f "$discussion_file" ]; then
            local status=$(jq -r '.status' "$discussion_file")
            if [ "$status" = "active" ]; then
                active_discussions=$((active_discussions + 1))
                discussions_json=$(echo "$discussions_json" | jq --slurpfile disc "$discussion_file" '. += $disc')
            fi
        fi
    done

    # 읽지 않은 메시지 수집
    local unread_count=0
    local messages_json="[]"
    for msg_file in "$MESSAGES_DIR/$CLAUDE_ID"/*.msg; do
        if [ -f "$msg_file" ]; then
            local read_status=$(jq -r '.read' "$msg_file")
            if [ "$read_status" = "false" ]; then
                unread_count=$((unread_count + 1))
                messages_json=$(echo "$messages_json" | jq --slurpfile msg "$msg_file" '. += $msg')
            fi
        fi
    done

    # JSON 모드 출력
    if [ "$JSON_MODE" = true ]; then
        jq -n \
            --arg my_id "$CLAUDE_ID" \
            --argjson active_instances "$instances_json" \
            --argjson active_plans "$plans_json" \
            --argjson active_edits "$edits_json" \
            --argjson open_proposals "$proposals_json" \
            --argjson active_discussions "$discussions_json" \
            --argjson unread_messages "$messages_json" \
            --argjson counts "{\"instances\": $active_count, \"plans\": $plans_in_progress, \"edits\": $active_edits, \"proposals\": $open_proposals, \"discussions\": $active_discussions, \"unread\": $unread_count}" \
            '{
                my_id: $my_id,
                counts: $counts,
                active_instances: $active_instances,
                active_plans: $active_plans,
                active_edits: $active_edits,
                open_proposals: $open_proposals,
                active_discussions: $active_discussions,
                unread_messages: $unread_messages
            }'
        return
    fi

    # 일반 텍스트 출력
    log_info "=== Collaboration Overview ==="
    echo ""
    echo "👥 Active Claudes: $active_count"
    echo "📋 Plans in progress: $plans_in_progress"
    echo "📝 Active edits: $active_edits"
    echo "💡 Open proposals: $open_proposals"
    echo "💬 Active discussions: $active_discussions"
    echo ""

    if [ $unread_count -gt 0 ]; then
        echo "📬 You have $unread_count unread message(s)!"
    fi
}

# ============================================
# 도움말
# ============================================

cmd_help() {
    cat << 'EOF'
Multi-Claude Collaboration Tool (Code With Me Style)

Usage: collab.sh <command> [arguments]

Instance Management:
  register <desc>       Register this Claude instance
  unregister           Unregister and release all locks
  heartbeat            Send heartbeat signal
  status               Show all active instances and locks
  overview             Show collaboration summary

=== PLAN SHARING (계획 공유) ===
  share-plan <title> [desc] [files]   Share your implementation plan
  view-plans                          View all shared plans
  comment-plan <id> <comment>         Comment on a plan
  approve-plan <id>                   Approve a plan
  start-plan <id>                     Start implementing a plan
  complete-plan <id>                  Mark plan as completed

=== LIVE EDITING (실시간 수정 공유) ===
  share-edit <file> <type> <desc>     Share what you're editing
  view-edits                          View all active edits
  finish-edit <file>                  Mark edit as finished
  (types: add, modify, delete, refactor)

=== COLLABORATIVE THINKING (협업적 사고) ===
  propose <type> <title> [details]    Submit a proposal
  view-proposals                      View all proposals
  vote <id> <agree|disagree>          Vote on a proposal
  respond <id> <response>             Respond to a proposal
  (types: approach, alternative, optimization, question)

=== DISCUSSIONS (토론) ===
  discuss <topic> [message]           Start a discussion
  view-discussions                    View active discussions
  reply <id> <message>                Reply to a discussion
  resolve-discussion <id> [resolution] Resolve a discussion

=== CONFLICT RESOLUTION (협의적 충돌 해결) ===
  report-conflict <file> [desc] [other_id]  Report a file conflict
  view-conflicts                            View all conflicts
  conflict-detail <id>                      View conflict details
  conflict-message <id> <message>           Add message to conflict discussion
  propose-resolution <id> <strategy> [desc] Propose a resolution strategy
  vote-resolution <id> <res_id> agree|disagree  Vote on resolution
  resolve-conflict <id> [res_id] [notes]    Mark conflict as resolved

  Resolution Strategies:
    split-regions  - Divide file into separate work regions
    sequential     - Work sequentially (one completes, then other)
    merge          - Work together, manually merge later
    delegate       - Delegate entire work to one Claude
    other          - Custom strategy (describe in description)

=== LEGACY FILE LOCKING (레거시 파일 잠금) ===
  lock <file>          Acquire lock on a file
  unlock <file>        Release lock on a file
  check-lock <file>    Check lock status of a file
  (Note: Prefer share-edit for collaborative workflow)

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

=== RECOMMENDED WORKFLOW ===
1. Register: ./scripts/collab.sh register "My task"
2. Share plan: ./scripts/collab.sh share-plan "Feature X" "Description" "file.ts"
3. Wait for feedback: ./scripts/collab.sh view-plans
4. Start work: ./scripts/collab.sh start-plan <plan_id>
5. Share edits: ./scripts/collab.sh share-edit src/file.ts modify "Adding new function"
6. If stuck, discuss: ./scripts/collab.sh propose question "How should we handle X?"
7. Finish: ./scripts/collab.sh finish-edit src/file.ts && ./scripts/collab.sh complete-plan <id>

Examples:
  ./scripts/collab.sh register "Implementing login feature"
  ./scripts/collab.sh share-plan "Add auth API" "JWT-based authentication" "src/api/auth.ts"
  ./scripts/collab.sh share-edit src/api/auth.ts add "Adding login endpoint"
  ./scripts/collab.sh propose approach "Use bcrypt for password hashing"
  ./scripts/collab.sh discuss "API response format" "Should we use JSON:API spec?"
EOF
}

# ============================================
# 메인
# ============================================

# 디렉토리 초기화
init_dirs

case "${1:-help}" in
    # Instance management
    register)       cmd_register "$2" ;;
    unregister)     cmd_unregister ;;
    heartbeat)      cmd_heartbeat ;;
    status)         cmd_status ;;
    overview)       cmd_overview ;;

    # Plan sharing (협업 기반)
    share-plan)     cmd_share_plan "$2" "$3" "$4" ;;
    view-plans)     cmd_view_plans ;;
    comment-plan)   cmd_comment_plan "$2" "$3" ;;
    approve-plan)   cmd_approve_plan "$2" ;;
    start-plan)     cmd_start_plan "$2" ;;
    complete-plan)  cmd_complete_plan "$2" ;;

    # Live editing (실시간 수정 공유)
    share-edit)     cmd_share_edit "$2" "$3" "$4" ;;
    view-edits)     cmd_view_edits ;;
    finish-edit)    cmd_finish_edit "$2" ;;

    # Collaborative thinking (협업적 사고)
    propose)        cmd_propose "$2" "$3" "$4" ;;
    view-proposals) cmd_view_proposals ;;
    vote)           cmd_vote "$2" "$3" ;;
    respond)        cmd_respond "$2" "$3" ;;

    # Discussions (토론)
    discuss)        cmd_discuss "$2" "$3" ;;
    view-discussions) cmd_view_discussions ;;
    reply)          cmd_reply "$2" "$3" ;;
    resolve-discussion) cmd_resolve_discussion "$2" "$3" ;;

    # Conflict resolution (충돌 해결)
    report-conflict)    cmd_report_conflict "$2" "$3" "$4" ;;
    view-conflicts)     cmd_view_conflicts ;;
    conflict-detail)    cmd_view_conflict_detail "$2" ;;
    conflict-message)   cmd_add_conflict_message "$2" "$3" ;;
    propose-resolution) cmd_propose_resolution "$2" "$3" "$4" ;;
    vote-resolution)    cmd_vote_resolution "$2" "$3" "$4" ;;
    resolve-conflict)   cmd_resolve_conflict "$2" "$3" "$4" ;;

    # Legacy file locking (레거시)
    lock)           cmd_lock "$2" ;;
    unlock)         cmd_unlock "$2" ;;
    check-lock)     cmd_check_lock "$2" ;;

    # Messaging
    send)           cmd_send "$2" "$3" ;;
    broadcast)      cmd_broadcast "$2" ;;
    inbox)          cmd_inbox ;;
    clear-inbox)    cmd_clear_inbox ;;

    # Status
    update-status)  cmd_update_status "$2" ;;
    complete)       cmd_complete "$2" ;;
    sync)           cmd_sync ;;
    report-error)   cmd_report_error "$2" "$3" ;;

    # Resource slots
    request-test-slot)    cmd_request_test_slot ;;
    release-test-slot)    cmd_release_test_slot ;;
    request-build-slot)   cmd_request_build_slot ;;
    release-build-slot)   cmd_release_build_slot ;;

    # Debug sessions
    debug-session)  cmd_debug_session "$2" "$3" ;;

    help|--help|-h) cmd_help ;;
    *)              log_error "Unknown command: $1"; cmd_help; exit 1 ;;
esac
