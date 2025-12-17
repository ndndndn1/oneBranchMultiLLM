# Multi-Claude Collaboration Protocol (Code With Me Style)

이 프로젝트는 여러 Claude Code 인스턴스가 하나의 브랜치에서 동시에 협업할 수 있도록 설계되었습니다.

**핵심 철학**: 파일 잠금보다 **계획 공유**와 **협업적 사고**를 우선합니다.

---

## 🤖 자동 협업 프로토콜 (CRITICAL - Claude Code 필수 준수)

### Claude Code는 이 프로젝트에서 작업 시 다음을 자동으로 수행해야 합니다:

#### 1. 세션 시작 시 (MANDATORY)
```bash
# 반드시 등록하고 현재 상황을 파악합니다
./scripts/collab.sh register "나의 작업 설명"
./scripts/collab.sh overview
./scripts/collab.sh view-plans
./scripts/collab.sh view-edits
./scripts/collab.sh inbox
```

#### 2. 파일 수정 전 (MANDATORY)
```bash
# 반드시 계획을 공유하고 수정 사항을 알립니다
./scripts/collab.sh share-plan "작업 제목" "상세 설명" "대상 파일"
./scripts/collab.sh start-plan <plan_id>
./scripts/collab.sh share-edit <파일> <타입> "설명"
```

#### 3. 의사결정이 필요할 때 (RECOMMENDED)
```bash
# 다른 Claude의 의견을 구합니다
./scripts/collab.sh propose question "질문 내용"
./scripts/collab.sh discuss "토론 주제" "초기 메시지"
```

#### 4. 작업 완료 시 (MANDATORY)
```bash
./scripts/collab.sh finish-edit <파일>
./scripts/collab.sh complete-plan <plan_id>
```

#### 5. 세션 종료 시 (MANDATORY)
```bash
./scripts/collab.sh unregister
```

---

## 🔧 MCP 서버 사용 (권장)

MCP 서버가 설치된 경우, 협업 도구를 자연스럽게 사용할 수 있습니다:

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

MCP 도구 목록:
- `collab_register` - 세션 등록
- `collab_overview` - 협업 현황 조회
- `collab_share_plan` - 계획 공유
- `collab_share_edit` - 수정 공유
- `collab_propose` - 제안/질문
- `collab_discuss` - 토론 시작
- `collab_inbox` - 메시지 확인
- `collab_report_conflict` - 충돌 보고
- `collab_view_conflicts` - 충돌 목록 조회
- `collab_propose_resolution` - 해결 방안 제안
- `collab_vote_resolution` - 해결 방안 투표
- `collab_resolve_conflict` - 충돌 해결 완료

---

## 📋 협업 행동 규칙 (Claude Code가 자동으로 따라야 함)

### 규칙 1: 항상 먼저 상황 파악
작업을 시작하기 전에 **반드시** 다음을 확인합니다:
- 다른 Claude가 어떤 계획을 가지고 있는지 (`view-plans`)
- 다른 Claude가 어떤 파일을 수정 중인지 (`view-edits`)
- 나에게 온 메시지가 있는지 (`inbox`)

### 규칙 2: 계획 먼저, 실행은 나중
파일을 수정하기 **전에** 반드시:
1. `share-plan`으로 무엇을 할지 공유
2. 다른 Claude의 피드백을 확인
3. `start-plan`으로 구현 시작 알림
4. `share-edit`로 수정 중인 파일 공유

### 규칙 3: 충돌 시 협력
같은 파일을 수정하려고 할 때:
1. 자동 경고를 확인
2. 해당 Claude에게 `send`로 조율
3. 필요시 `discuss`로 토론 시작
4. 작업 영역 분리 또는 순차 작업 결정

### 규칙 4: 투명한 의사결정
중요한 결정이 필요할 때:
1. `propose`로 제안 또는 질문
2. 다른 Claude의 `vote` 확인
3. `discuss`로 심층 토론
4. 합의 후 진행

### 규칙 5: 주기적 동기화
10분마다 또는 중요한 작업 전에:
```bash
./scripts/collab.sh sync
```

---

## 📊 JSON 출력 모드 (Agent-Friendly)

스크립트 출력을 JSON으로 받으려면:
```bash
./scripts/collab.sh --json overview
./scripts/collab.sh --json view-plans
./scripts/collab.sh --json view-edits
```

---

## 🎯 작업 영역 가이드 (참고용)

각 Claude 인스턴스는 전문 영역을 가질 수 있습니다:

| 인스턴스 | 담당 영역 | 디렉토리 패턴 |
|---------|----------|--------------|
| Claude-A | 프론트엔드/UI | `src/components/`, `src/pages/`, `*.css` |
| Claude-B | 백엔드/API | `src/api/`, `src/services/`, `src/server/` |
| Claude-C | 테스트/문서 | `tests/`, `docs/`, `*.test.*` |
| Claude-D | 인프라/설정 | `config/`, `scripts/`, `*.config.*` |

**중요**: 영역 구분은 권장사항입니다. 계획을 공유하면 누구든 어디서든 작업할 수 있습니다.

---

## 💬 협업 명령어 Quick Reference

```bash
# 세션 관리
./scripts/collab.sh register "작업 설명"    # 시작 시 필수
./scripts/collab.sh overview                 # 현재 협업 상황
./scripts/collab.sh unregister               # 종료 시 필수

# 계획 공유
./scripts/collab.sh share-plan "제목" "설명" "파일"
./scripts/collab.sh view-plans
./scripts/collab.sh start-plan <id>
./scripts/collab.sh complete-plan <id>

# 수정 공유
./scripts/collab.sh share-edit file.ts modify "설명"
./scripts/collab.sh view-edits
./scripts/collab.sh finish-edit file.ts

# 협업적 사고
./scripts/collab.sh propose question "질문"
./scripts/collab.sh propose approach "제안" "상세"
./scripts/collab.sh vote <id> agree|disagree
./scripts/collab.sh discuss "주제" "메시지"
./scripts/collab.sh reply <id> "답변"

# 충돌 해결
./scripts/collab.sh report-conflict <file> "설명"
./scripts/collab.sh view-conflicts
./scripts/collab.sh propose-resolution <id> <strategy> "설명"
./scripts/collab.sh vote-resolution <id> <res_id> agree
./scripts/collab.sh resolve-conflict <id>

# 메시지
./scripts/collab.sh inbox
./scripts/collab.sh send <claude_id> "메시지"
./scripts/collab.sh broadcast "전체 메시지"

# 동기화
./scripts/collab.sh sync
```

---

## 🔄 권장 워크플로우 (Claude Code 자동 적용)

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. 세션 시작                                                     │
│    register → overview → view-plans → view-edits → inbox        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. 계획 공유                                                     │
│    share-plan → (피드백 대기) → start-plan                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. 구현                                                          │
│    share-edit → (코드 작성) → finish-edit                        │
│                                                                  │
│    막히면: propose question 또는 discuss                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. 완료                                                          │
│    complete-plan → git commit → git push                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. 세션 종료                                                     │
│    unregister                                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚨 협의적 충돌 해결 (Collaborative Conflict Resolution)

### 같은 파일 수정 시
`share-edit` 사용 시 같은 파일을 수정 중인 Claude가 있으면 **자동 경고**가 발송됩니다.

### 충돌 해결 워크플로우 (MANDATORY)

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. 충돌 감지                                                     │
│    share-edit 시 경고 → report-conflict                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. 충돌 협의                                                     │
│    conflict-message로 토론 → propose-resolution로 해결책 제안    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. 투표 및 합의                                                  │
│    vote-resolution agree/disagree → 합의 도출                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. 충돌 해결                                                     │
│    resolve-conflict → 합의된 전략에 따라 작업 진행                │
└─────────────────────────────────────────────────────────────────┘
```

### 충돌 해결 명령어

```bash
# 충돌 보고 (자동으로 상대방 감지)
./scripts/collab.sh report-conflict <file> "설명"

# 현재 충돌 목록 조회
./scripts/collab.sh view-conflicts

# 충돌 상세 정보 조회
./scripts/collab.sh conflict-detail <conflict_id>

# 충돌 토론에 메시지 추가
./scripts/collab.sh conflict-message <conflict_id> "메시지"

# 해결 방안 제안
./scripts/collab.sh propose-resolution <conflict_id> <strategy> "설명"

# 해결 방안 투표
./scripts/collab.sh vote-resolution <conflict_id> <resolution_id> agree

# 충돌 해결 완료
./scripts/collab.sh resolve-conflict <conflict_id>
```

### 해결 전략 (Resolution Strategies)

| 전략 | 설명 | 사용 상황 |
|------|------|----------|
| `split-regions` | 파일 내 작업 영역 분리 | 다른 함수/섹션을 담당할 때 |
| `sequential` | 순차 작업 | 한 Claude가 먼저 완료 후 다른 Claude 작업 |
| `merge` | 공동 작업 후 병합 | 변경 범위가 명확히 구분될 때 |
| `delegate` | 작업 위임 | 한 Claude에게 전체 작업 위임 |
| `other` | 기타 전략 | 커스텀 해결 방안 |

### MCP 충돌 해결 도구

```
collab_report_conflict    - 충돌 보고
collab_view_conflicts     - 충돌 목록 조회
collab_conflict_detail    - 충돌 상세 정보
collab_conflict_message   - 충돌 토론 메시지 추가
collab_propose_resolution - 해결 방안 제안
collab_vote_resolution    - 해결 방안 투표
collab_resolve_conflict   - 충돌 해결 완료
```

### Git 충돌 발생 시
1. 작업 중단하고 `broadcast`로 알림
2. `report-conflict`로 충돌 보고
3. `propose-resolution`으로 해결 방안 제안
4. 합의 후 충돌 해결

---

## 📁 디렉토리 구조

```
.claude-collab/
├── instances/          # 활성 Claude 인스턴스 정보
├── plans/              # 공유된 작업 계획
├── edits/              # 현재 진행 중인 수정
├── proposals/          # 제안 및 투표
├── discussions/        # 토론 스레드
├── locks/              # 파일 잠금 정보 (레거시)
├── messages/           # 인스턴스 간 메시지
├── tasks/              # 작업 큐
├── conflicts/          # 충돌 기록
└── errors/             # 에러 기록

mcp/
└── collab-server.py    # MCP 서버 (권장)
```

---

## 🧠 협업 철학

1. **소통 우선**: 잠그기 전에 계획을 공유하세요
2. **함께 생각**: 어려운 결정은 제안과 토론으로 해결하세요
3. **투명성**: 현재 작업 중인 내용을 항상 공유하세요
4. **유연성**: 영역 구분은 참고용이며, 조율하면 어디든 작업 가능합니다
5. **존중**: 다른 Claude의 계획과 진행 중인 작업을 존중하세요

---

## ⚡ SessionStart Hook (자동 협업 진입)

`.claude/hooks/session-start.sh`를 통해 세션 시작 시 자동으로 협업 모드에 진입합니다:

```bash
#!/bin/bash
cd "$(dirname "$0")/../.."
./scripts/collab.sh register "Session started"
./scripts/collab.sh overview
```

이 hook은 Claude Code 세션이 시작될 때 자동으로 실행되어 협업 상태를 설정합니다.
