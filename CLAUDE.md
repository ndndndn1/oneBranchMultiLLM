# Multi-Claude Collaboration Protocol (Code With Me Style)

이 프로젝트는 여러 Claude Code 인스턴스가 하나의 브랜치에서 동시에 협업할 수 있도록 설계되었습니다.

**핵심 철학**: 파일 잠금보다 **계획 공유**와 **협업적 사고**를 우선합니다.

## 시작하기 전에

### Claude 인스턴스 등록
작업을 시작할 때 반드시 자신을 등록하세요:
```bash
./scripts/collab.sh register "작업 설명"
```

### 현재 협업 상태 확인
```bash
./scripts/collab.sh overview    # 전체 협업 요약
./scripts/collab.sh status      # 활성 인스턴스 상태
```

---

## 새로운 협업 워크플로우 (CRITICAL)

### 1. 계획 공유 (Plan Sharing) - 작업 전 필수!

파일을 수정하기 전에 **먼저 계획을 공유**하세요. 다른 Claude가 검토하고 피드백을 줄 수 있습니다:

```bash
# 계획 공유
./scripts/collab.sh share-plan "기능 제목" "상세 설명" "대상 파일들"

# 예시
./scripts/collab.sh share-plan "로그인 API 구현" "JWT 기반 인증, bcrypt 해싱" "src/api/auth.ts"

# 다른 Claude의 계획 확인
./scripts/collab.sh view-plans

# 계획에 의견 제시
./scripts/collab.sh comment-plan <plan_id> "Redis 세션 스토어도 고려해보세요"

# 계획 승인
./scripts/collab.sh approve-plan <plan_id>

# 계획 구현 시작
./scripts/collab.sh start-plan <plan_id>

# 계획 완료
./scripts/collab.sh complete-plan <plan_id>
```

### 2. 실시간 수정 공유 (Live Editing)

어떤 파일을 수정 중인지 공유하여 충돌을 예방하세요:

```bash
# 수정 시작 알림
./scripts/collab.sh share-edit <파일경로> <변경타입> "설명"
# 변경타입: add, modify, delete, refactor

# 예시
./scripts/collab.sh share-edit src/api/auth.ts add "로그인 엔드포인트 추가"

# 다른 Claude의 현재 수정 확인
./scripts/collab.sh view-edits

# 수정 완료 알림
./scripts/collab.sh finish-edit <파일경로>
```

**같은 파일을 수정 중이면 자동으로 경고가 발송됩니다!**

### 3. 협업적 사고 (Collaborative Thinking)

구현 방법이나 설계에 대해 다른 Claude와 함께 생각하세요:

```bash
# 제안하기
./scripts/collab.sh propose <타입> "제목" "상세 내용"
# 타입: approach(접근법), alternative(대안), optimization(최적화), question(질문)

# 예시
./scripts/collab.sh propose approach "비밀번호 해싱에 bcrypt 사용" "argon2보다 널리 지원됨"
./scripts/collab.sh propose question "세션 저장소로 Redis vs Memcached?"

# 제안 확인
./scripts/collab.sh view-proposals

# 제안에 투표
./scripts/collab.sh vote <proposal_id> agree
./scripts/collab.sh vote <proposal_id> disagree

# 제안에 응답
./scripts/collab.sh respond <proposal_id> "Redis가 더 좋습니다. 이유는..."
```

### 4. 토론 (Discussions)

복잡한 주제에 대해 스레드 기반 토론을 시작하세요:

```bash
# 토론 시작
./scripts/collab.sh discuss "API 응답 형식" "JSON:API 스펙을 따를까요?"

# 활성 토론 확인
./scripts/collab.sh view-discussions

# 토론에 참여
./scripts/collab.sh reply <discussion_id> "저는 JSON:API에 동의합니다"

# 토론 해결
./scripts/collab.sh resolve-discussion <discussion_id> "JSON:API 스펙 적용 결정"
```

---

## 권장 작업 흐름

### 단계별 가이드

```
1. 등록
   ./scripts/collab.sh register "나의 작업 설명"

2. 현재 상황 파악
   ./scripts/collab.sh overview
   ./scripts/collab.sh view-plans
   ./scripts/collab.sh view-edits

3. 계획 공유 (작업 전)
   ./scripts/collab.sh share-plan "기능명" "설명" "파일"

4. 피드백 대기 및 조율
   ./scripts/collab.sh inbox
   ./scripts/collab.sh view-proposals

5. 구현 시작
   ./scripts/collab.sh start-plan <plan_id>
   ./scripts/collab.sh share-edit file.ts modify "작업 내용"

6. 막히면 질문/토론
   ./scripts/collab.sh propose question "어떻게 해야 할까요?"
   ./scripts/collab.sh discuss "복잡한 주제" "논의 필요"

7. 완료
   ./scripts/collab.sh finish-edit file.ts
   ./scripts/collab.sh complete-plan <plan_id>

8. 종료
   ./scripts/collab.sh unregister
```

---

## 작업 영역 가이드 (참고용)

각 Claude 인스턴스는 전문 영역을 가질 수 있습니다:

| 인스턴스 | 담당 영역 | 디렉토리 패턴 |
|---------|----------|--------------|
| Claude-A | 프론트엔드/UI | `src/components/`, `src/pages/`, `*.css` |
| Claude-B | 백엔드/API | `src/api/`, `src/services/`, `src/server/` |
| Claude-C | 테스트/문서 | `tests/`, `docs/`, `*.test.*` |
| Claude-D | 인프라/설정 | `config/`, `scripts/`, `*.config.*` |

**중요**: 영역 구분은 권장사항입니다. 계획을 공유하면 누구든 어디서든 작업할 수 있습니다.

---

## 메시지 시스템

다른 Claude와 직접 통신할 때:

```bash
# 메시지 보내기
./scripts/collab.sh send <대상_claude_id> "메시지 내용"

# 메시지 확인
./scripts/collab.sh inbox

# 브로드캐스트 (모든 인스턴스에게)
./scripts/collab.sh broadcast "메시지 내용"
```

---

## 동기화 및 Git 작업

### 주기적 동기화
```bash
./scripts/collab.sh sync
```

이 명령은:
1. 최신 변경사항 pull
2. heartbeat 전송
3. 오래된 수정 정보 정리
4. 받은 메시지 표시

### Git 작업 규칙
1. **pull 먼저**: 파일 수정 전 항상 `git pull origin <branch>`
2. **작은 커밋**: 자주 작은 단위로 커밋
3. **즉시 push**: 커밋 후 바로 push

---

## 충돌 해결 전략

### 같은 파일 수정 시
`share-edit` 사용 시 같은 파일을 수정 중인 Claude가 있으면 **자동 경고**가 발송됩니다.

1. 경고 수신 시 `inbox` 확인
2. 해당 Claude와 `discuss` 또는 `send`로 조율
3. 작업 영역 분리 또는 순차 작업 결정

### Git 충돌 발생 시
1. 작업 중단하고 다른 Claude에게 알림
2. `.claude-collab/conflicts/`에 충돌 내용 기록
3. `discuss`로 해결 방법 논의

---

## 레거시: 파일 잠금 시스템

**참고**: 파일 잠금은 레거시 기능입니다. 가능하면 `share-edit`를 사용하세요.

```bash
# 파일 잠금 (레거시)
./scripts/collab.sh lock <파일경로>
./scripts/collab.sh unlock <파일경로>
./scripts/collab.sh check-lock <파일경로>
```

---

## 테스트 및 빌드 조율

### 테스트 실행 전
```bash
./scripts/collab.sh request-test-slot
npm test
./scripts/collab.sh release-test-slot
```

### 빌드 실행 전
```bash
./scripts/collab.sh request-build-slot
npm run build
./scripts/collab.sh release-build-slot
```

---

## 디버깅 협업

```bash
# 에러 보고
./scripts/collab.sh report-error "에러 내용" "관련 파일"

# 디버깅 세션 시작
./scripts/collab.sh debug-session start "세션 설명"
```

---

## Heartbeat 시스템

Claude 인스턴스가 활성 상태인지 확인하기 위해 heartbeat를 사용합니다.
10분 이상 heartbeat가 없으면 해당 인스턴스는 비활성으로 간주됩니다.

```bash
./scripts/collab.sh heartbeat
```

---

## 디렉토리 구조

```
.claude-collab/
├── instances/          # 활성 Claude 인스턴스 정보
├── plans/              # 공유된 작업 계획 (NEW)
├── edits/              # 현재 진행 중인 수정 (NEW)
├── proposals/          # 제안 및 투표 (NEW)
├── discussions/        # 토론 스레드 (NEW)
├── locks/              # 파일 잠금 정보 (레거시)
├── messages/           # 인스턴스 간 메시지
├── tasks/              # 작업 큐
├── conflicts/          # 충돌 기록
└── errors/             # 에러 기록
```

---

## Quick Reference

```bash
# 필수 명령어
./scripts/collab.sh register "작업 설명"          # 시작 시
./scripts/collab.sh overview                      # 현재 상황 확인
./scripts/collab.sh share-plan "제목" "설명"      # 계획 공유
./scripts/collab.sh share-edit file.ts modify "설명"  # 수정 공유
./scripts/collab.sh propose question "질문"       # 질문/제안
./scripts/collab.sh inbox                         # 메시지 확인
./scripts/collab.sh sync                          # 동기화
./scripts/collab.sh unregister                    # 종료 시
```

---

## 협업 철학

1. **소통 우선**: 잠그기 전에 계획을 공유하세요
2. **함께 생각**: 어려운 결정은 제안과 토론으로 해결하세요
3. **투명성**: 현재 작업 중인 내용을 항상 공유하세요
4. **유연성**: 영역 구분은 참고용이며, 조율하면 어디든 작업 가능합니다
5. **존중**: 다른 Claude의 계획과 진행 중인 작업을 존중하세요
