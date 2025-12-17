# Multi-Claude Collaboration System (Code With Me Style)

여러 Claude Code 인스턴스가 하나의 브랜치에서 동시에 협업할 수 있는 시스템입니다.

**핵심 철학**: 파일 잠금보다 **계획 공유**와 **협업적 사고**를 우선합니다.

## 왜 필요한가?

- 복잡한 기능을 여러 Claude가 병렬로 구현하여 **2배 이상 빠르게** 완료
- 프론트엔드/백엔드/테스트를 동시에 개발
- 계획 공유와 실시간 수정 공유로 충돌 예방
- 제안과 토론을 통한 협업적 의사결정

## Quick Start

```bash
# 1. 초기화
./scripts/init-collab.sh

# 2. Claude 인스턴스 등록
./scripts/collab.sh register "My task description"

# 3. 협업 현황 확인
./scripts/collab.sh overview

# 4. 계획 공유 (작업 전 필수!)
./scripts/collab.sh share-plan "Add login feature" "JWT auth" "src/api/auth.ts"

# 5. 작업 시작
./scripts/collab.sh start-plan <plan_id>
./scripts/collab.sh share-edit src/api/auth.ts add "Adding login endpoint"

# 6. 작업 완료
./scripts/collab.sh finish-edit src/api/auth.ts
./scripts/collab.sh complete-plan <plan_id>
```

## 🤖 자동 협업 (Agent-Friendly)

### MCP 서버 사용 (권장)

Claude Code가 자연스럽게 협업 도구를 사용할 수 있도록 MCP 서버를 제공합니다:

```json
{
  "mcpServers": {
    "collab": {
      "command": "python3",
      "args": ["mcp/collab-server.py"],
      "cwd": "/path/to/oneBranchMultiLLM"
    }
  }
}
```

MCP 도구:
- `collab_register` - 세션 등록
- `collab_overview` - 협업 현황 조회
- `collab_share_plan` - 계획 공유
- `collab_share_edit` - 수정 공유
- `collab_propose` - 제안/질문
- `collab_discuss` - 토론 시작

### JSON 출력 모드

Agent가 파싱하기 쉽도록 JSON 출력을 지원합니다:

```bash
./scripts/collab.sh --json overview
./scripts/collab.sh --json view-plans
./scripts/collab.sh --json view-edits
```

### Session Hooks

세션 시작/종료 시 자동으로 협업 상태를 관리합니다:
- `.claude/hooks/session-start.sh` - 세션 시작 시 자동 등록
- `.claude/hooks/session-end.sh` - 세션 종료 시 자동 해제

## 핵심 기능

### 1. 계획 공유 (Plan Sharing)

작업 전에 계획을 공유하여 다른 Claude가 검토하고 피드백을 줄 수 있습니다.

```bash
./scripts/collab.sh share-plan "기능명" "설명" "대상 파일"
./scripts/collab.sh view-plans
./scripts/collab.sh comment-plan <id> "의견"
./scripts/collab.sh approve-plan <id>
./scripts/collab.sh start-plan <id>
./scripts/collab.sh complete-plan <id>
```

### 2. 실시간 수정 공유 (Live Editing)

현재 수정 중인 파일을 공유하여 충돌을 예방합니다.

```bash
./scripts/collab.sh share-edit <file> <type> "설명"
./scripts/collab.sh view-edits
./scripts/collab.sh finish-edit <file>
```

**같은 파일을 수정 중인 Claude가 있으면 자동 경고!**

### 3. 협업적 사고 (Collaborative Thinking)

제안과 투표로 함께 결정합니다.

```bash
./scripts/collab.sh propose <type> "제목" "상세"
./scripts/collab.sh view-proposals
./scripts/collab.sh vote <id> agree|disagree
./scripts/collab.sh respond <id> "의견"
```

### 4. 토론 (Discussions)

복잡한 주제를 스레드로 논의합니다.

```bash
./scripts/collab.sh discuss "주제" "첫 메시지"
./scripts/collab.sh view-discussions
./scripts/collab.sh reply <id> "답변"
./scripts/collab.sh resolve-discussion <id> "결론"
```

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Git Repository                            │
│                    (Single Branch)                           │
└─────────────────────────────────────────────────────────────┘
          ▲                    ▲                    ▲
          │                    │                    │
    ┌─────┴─────┐        ┌─────┴─────┐        ┌─────┴─────┐
    │ Claude-A  │◄──────►│ Claude-B  │◄──────►│ Claude-C  │
    │(Frontend) │  협업   │(Backend)  │  협업   │(Tests)    │
    └───────────┘        └───────────┘        └───────────┘
          │                    │                    │
          └────────────────────┼────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │  .claude-collab/    │
                    │  ├── instances/     │ ← 활성 인스턴스
                    │  ├── plans/         │ ← 계획 공유
                    │  ├── edits/         │ ← 수정 공유
                    │  ├── proposals/     │ ← 제안/투표
                    │  ├── discussions/   │ ← 토론
                    │  └── messages/      │ ← 메시지 큐
                    └─────────────────────┘
```

## 디렉토리 구조

```
.
├── CLAUDE.md                 # 협업 프로토콜 (Claude가 읽음)
├── README.md                 # 이 파일
├── .gitignore
├── scripts/
│   ├── collab.sh            # 핵심 협업 스크립트 (--json 지원)
│   ├── collab_bridge.py     # WebSocket 브릿지 (선택)
│   ├── conflict_resolver.sh # 충돌 해결 도구
│   └── init-collab.sh       # 초기화 스크립트
├── mcp/
│   ├── collab-server.py     # MCP 서버 (Agent용)
│   └── mcp-config.example.json
├── .claude/
│   ├── hooks/
│   │   ├── session-start.sh # 세션 시작 hook
│   │   └── session-end.sh   # 세션 종료 hook
│   └── commands/
│       └── collab.md        # 협업 명령어 가이드
├── docs/
│   └── WORKFLOW_EXAMPLES.md
└── .claude-collab/          # 런타임 데이터 (git ignored)
```

## 요구사항

- Bash
- jq (JSON 처리)
- Git
- Python 3.x (MCP 서버 사용 시)
- mcp SDK (MCP 서버 사용 시): `pip install mcp`

## 협업 철학

1. **소통 우선**: 잠그기 전에 계획을 공유하세요
2. **함께 생각**: 어려운 결정은 제안과 토론으로 해결하세요
3. **투명성**: 현재 작업 중인 내용을 항상 공유하세요
4. **유연성**: 영역 구분은 참고용이며, 조율하면 어디든 작업 가능합니다
5. **존중**: 다른 Claude의 계획과 진행 중인 작업을 존중하세요

## 라이선스

MIT
