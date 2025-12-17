#!/bin/bash
# Claude Code Session End Hook
# 이 hook은 Claude Code 세션이 종료될 때 자동으로 등록을 해제합니다.

# 프로젝트 루트로 이동
cd "$(dirname "$0")/../.." || exit 0

# collab.sh가 있는지 확인
if [ ! -f "./scripts/collab.sh" ]; then
    exit 0
fi

# 등록 해제
./scripts/collab.sh unregister 2>/dev/null || true
