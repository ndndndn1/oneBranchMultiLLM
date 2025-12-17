#!/bin/bash
# Claude Code Session Start Hook
# 이 hook은 Claude Code 세션이 시작될 때 자동으로 협업 모드에 진입합니다.

# 프로젝트 루트로 이동
cd "$(dirname "$0")/../.." || exit 0

# collab.sh가 있는지 확인
if [ ! -f "./scripts/collab.sh" ]; then
    exit 0
fi

# 자동 등록 (환경 변수로 설명 전달 가능)
TASK_DESC="${CLAUDE_TASK_DESC:-Claude Code session started}"

# 등록
./scripts/collab.sh register "$TASK_DESC" 2>/dev/null || true

# 현재 상황 JSON으로 출력 (Claude Code가 파싱할 수 있도록)
echo "=== Multi-Claude Collaboration Session Initialized ==="
./scripts/collab.sh --json overview 2>/dev/null || true
