#!/bin/bash
# Multi-Claude Collaboration 초기화 스크립트
# 프로젝트에서 협업을 시작하기 전에 실행하세요

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║      Multi-Claude Collaboration System (Code With Me)         ║
║                   Initialization Script                       ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 디렉토리 구조 생성
echo -e "${YELLOW}Creating directory structure...${NC}"

mkdir -p .claude-collab/{instances,locks,messages,tasks/{pending,in_progress,completed},conflicts,errors,plans,edits,proposals,discussions}

echo "  ✓ .claude-collab/instances/"
echo "  ✓ .claude-collab/plans/        (NEW: 계획 공유)"
echo "  ✓ .claude-collab/edits/        (NEW: 수정 공유)"
echo "  ✓ .claude-collab/proposals/    (NEW: 제안/투표)"
echo "  ✓ .claude-collab/discussions/  (NEW: 토론)"
echo "  ✓ .claude-collab/locks/        (레거시)"
echo "  ✓ .claude-collab/messages/"
echo "  ✓ .claude-collab/tasks/"
echo "  ✓ .claude-collab/conflicts/"
echo "  ✓ .claude-collab/errors/"

# 스크립트 실행 권한
echo -e "\n${YELLOW}Setting up scripts...${NC}"
chmod +x scripts/*.sh scripts/*.py 2>/dev/null || true
echo "  ✓ Scripts are executable"

# jq 확인
echo -e "\n${YELLOW}Checking dependencies...${NC}"
if command -v jq &> /dev/null; then
    echo "  ✓ jq is installed"
else
    echo "  ⚠ jq is not installed (required for collab.sh)"
    echo "    Install with: apt-get install jq (Linux) or brew install jq (macOS)"
fi

# Git hooks 설정 (선택)
echo -e "\n${YELLOW}Setting up Git hooks (optional)...${NC}"

# Pre-push hook - 잠금 확인
cat > .git/hooks/pre-push << 'HOOK'
#!/bin/bash
# Check for lock conflicts before push

COLLAB_DIR=".claude-collab"
CLAUDE_ID="${CLAUDE_ID:-unknown}"

# 다른 Claude가 잠근 파일을 수정했는지 확인
changed_files=$(git diff --name-only HEAD~1 2>/dev/null || git diff --name-only HEAD)

for file in $changed_files; do
    encoded=$(echo "$file" | sed 's/\//_SLASH_/g')
    lock_file="$COLLAB_DIR/locks/$encoded.lock"

    if [ -f "$lock_file" ]; then
        owner=$(jq -r '.owner' "$lock_file" 2>/dev/null)
        if [ "$owner" != "$CLAUDE_ID" ] && [ "$owner" != "unknown" ]; then
            echo "⚠ Warning: $file is locked by $owner"
            echo "  Consider coordinating before pushing."
        fi
    fi
done

exit 0
HOOK
chmod +x .git/hooks/pre-push
echo "  ✓ Pre-push hook installed"

# Post-merge hook - 자동 sync
cat > .git/hooks/post-merge << 'HOOK'
#!/bin/bash
# Notify other Claude instances after merge

if [ -x scripts/collab.sh ]; then
    ./scripts/collab.sh broadcast "[GIT] Changes merged, please sync" 2>/dev/null || true
fi
HOOK
chmod +x .git/hooks/post-merge
echo "  ✓ Post-merge hook installed"

echo -e "\n${GREEN}Initialization complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Register your Claude instance:"
echo "     ./scripts/collab.sh register \"Your task description\""
echo ""
echo "  2. Check collaboration status:"
echo "     ./scripts/collab.sh overview"
echo ""
echo "  3. Share your plan before working:"
echo "     ./scripts/collab.sh share-plan \"Feature title\" \"Description\" \"target files\""
echo ""
echo "  4. Share what you're editing:"
echo "     ./scripts/collab.sh share-edit file.ts modify \"Adding feature\""
echo ""
echo "  5. Read CLAUDE.md for full protocol documentation"
echo ""
echo -e "${BLUE}Happy collaborating! 함께 생각하고, 계획을 공유하세요!${NC}"
