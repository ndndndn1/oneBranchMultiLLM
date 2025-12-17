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
export CLAUDE_ID="claude-1"
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

# 7. 안전하게 커밋/푸시
./scripts/conflict_resolver.sh safe-commit "feat: add feature"
./scripts/conflict_resolver.sh safe-push
```

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

### 5. 메시지 시스템

Claude 인스턴스 간 직접 통신을 지원합니다.

```bash
./scripts/collab.sh send <claude_id> "message"
./scripts/collab.sh broadcast "message to all"
./scripts/collab.sh inbox
```

### 6. 레거시: 파일 잠금

(권장하지 않음 - share-edit 사용 권장)

```bash
./scripts/collab.sh lock <file>
./scripts/collab.sh unlock <file>
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
                    │  ├── plans/         │ ← 계획 공유 (NEW)
                    │  ├── edits/         │ ← 수정 공유 (NEW)
                    │  ├── proposals/     │ ← 제안/투표 (NEW)
                    │  ├── discussions/   │ ← 토론 (NEW)
                    │  ├── locks/         │ ← 파일 잠금 (레거시)
                    │  ├── messages/      │ ← 메시지 큐
                    │  └── tasks/         │ ← 작업 상태
                    └─────────────────────┘
```

## 권장 워크플로우

```
1. 등록 → 2. 현황 파악 → 3. 계획 공유 → 4. 피드백 대기
                                              ↓
8. 종료 ← 7. 완료 알림 ← 6. 작업 ← 5. 수정 공유
                           ↑
                   막히면 제안/토론
```

## 디렉토리 구조

```
.
├── CLAUDE.md                 # 협업 프로토콜 (Claude가 읽음)
├── README.md                 # 이 파일
├── .gitignore
├── scripts/
│   ├── collab.sh            # 핵심 협업 스크립트
│   ├── collab_bridge.py     # WebSocket 브릿지 (선택)
│   ├── conflict_resolver.sh # 충돌 해결 도구
│   └── init-collab.sh       # 초기화 스크립트
├── docs/
│   └── WORKFLOW_EXAMPLES.md # 상세 워크플로우 예시
└── .claude-collab/          # 런타임 데이터 (git ignored)
    ├── instances/
    ├── plans/               # NEW
    ├── edits/               # NEW
    ├── proposals/           # NEW
    ├── discussions/         # NEW
    ├── locks/
    ├── messages/
    └── tasks/
```

## 요구사항

- Bash
- jq (JSON 처리)
- Git
- Python 3.x (브릿지 서버 사용 시)

## 협업 철학

1. **소통 우선**: 잠그기 전에 계획을 공유하세요
2. **함께 생각**: 어려운 결정은 제안과 토론으로 해결하세요
3. **투명성**: 현재 작업 중인 내용을 항상 공유하세요
4. **유연성**: 영역 구분은 참고용이며, 조율하면 어디든 작업 가능합니다
5. **존중**: 다른 Claude의 계획과 진행 중인 작업을 존중하세요

## 라이선스

MIT
