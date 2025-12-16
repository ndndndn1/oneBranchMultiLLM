# Multi-Claude Collaboration Protocol

이 프로젝트는 여러 Claude Code 인스턴스가 하나의 브랜치에서 동시에 협업할 수 있도록 설계되었습니다.

## 시작하기 전에

### Claude 인스턴스 등록
작업을 시작할 때 반드시 자신을 등록하세요:
```bash
./scripts/collab.sh register "작업 설명"
```

### 현재 활성 인스턴스 확인
```bash
./scripts/collab.sh status
```

---

## 협업 규칙 (CRITICAL - 반드시 준수)

### 1. 파일 잠금 시스템
파일을 수정하기 전에 **반드시** 잠금을 획득하세요:

```bash
# 파일 잠금 획득
./scripts/collab.sh lock <파일경로>

# 작업 완료 후 잠금 해제
./scripts/collab.sh unlock <파일경로>
```

**잠금 없이 파일을 수정하면 충돌이 발생합니다!**

### 2. 작업 영역 분리
각 Claude 인스턴스는 서로 다른 영역을 담당합니다:

| 인스턴스 | 담당 영역 | 디렉토리 패턴 |
|---------|----------|--------------|
| Claude-A | 프론트엔드/UI | `src/components/`, `src/pages/`, `*.css` |
| Claude-B | 백엔드/API | `src/api/`, `src/services/`, `src/server/` |
| Claude-C | 테스트/문서 | `tests/`, `docs/`, `*.test.*` |
| Claude-D | 인프라/설정 | `config/`, `scripts/`, `*.config.*` |

### 3. 메시지 채널
다른 Claude와 통신할 때 메시지 시스템을 사용하세요:

```bash
# 메시지 보내기
./scripts/collab.sh send <대상_claude_id> "메시지 내용"

# 메시지 확인
./scripts/collab.sh inbox

# 브로드캐스트 (모든 인스턴스에게)
./scripts/collab.sh broadcast "메시지 내용"
```

### 4. 작업 상태 업데이트
작업 상태를 주기적으로 업데이트하세요:

```bash
# 현재 작업 상태 업데이트
./scripts/collab.sh update-status "현재 하고 있는 작업"

# 작업 완료 알림
./scripts/collab.sh complete "완료된 작업 설명"
```

---

## 충돌 방지 전략

### Git 작업 규칙
1. **pull 먼저**: 파일 수정 전 항상 `git pull origin <branch>`
2. **작은 커밋**: 자주 작은 단위로 커밋
3. **즉시 push**: 커밋 후 바로 push

### 충돌 발생 시
1. 작업 중단하고 다른 Claude에게 알림
2. `.claude-collab/conflicts/`에 충돌 내용 기록
3. 충돌 해결 담당자 지정 (보통 먼저 작업 시작한 Claude)

---

## 디렉토리 구조

```
.claude-collab/
├── instances/          # 활성 Claude 인스턴스 정보
│   └── <claude_id>.json
├── locks/              # 파일 잠금 정보
│   └── <encoded_path>.lock
├── messages/           # 인스턴스 간 메시지
│   └── <target_id>/
│       └── <timestamp>_<from_id>.msg
├── tasks/              # 작업 큐
│   ├── pending/
│   ├── in_progress/
│   └── completed/
└── conflicts/          # 충돌 기록
```

---

## 작업 흐름 예시

### 새 기능 구현 (2개 Claude 협업)

**Claude-A (프론트엔드):**
```bash
./scripts/collab.sh register "로그인 UI 구현"
./scripts/collab.sh lock src/components/Login.tsx
# ... 작업 ...
git add . && git commit -m "feat: add Login component"
git push origin <branch>
./scripts/collab.sh unlock src/components/Login.tsx
./scripts/collab.sh send claude-b "로그인 UI 완료, API 연동 준비됨"
```

**Claude-B (백엔드):**
```bash
./scripts/collab.sh register "로그인 API 구현"
./scripts/collab.sh lock src/api/auth.ts
# ... 작업 ...
git add . && git commit -m "feat: add auth API"
git push origin <branch>
./scripts/collab.sh unlock src/api/auth.ts
./scripts/collab.sh send claude-a "API 완료, endpoint: /api/auth/login"
```

---

## 자동화된 충돌 감지

매 작업 전에 실행:
```bash
./scripts/collab.sh sync
```

이 명령은:
1. 최신 변경사항 pull
2. 잠금 충돌 확인
3. 다른 인스턴스 상태 확인
4. 받은 메시지 표시

---

## Heartbeat 시스템

Claude 인스턴스가 활성 상태인지 확인하기 위해 5분마다 heartbeat를 보냅니다.
10분 이상 heartbeat가 없으면 해당 인스턴스는 비활성으로 간주되고 잠금이 자동 해제됩니다.

```bash
# 수동 heartbeat (보통 자동)
./scripts/collab.sh heartbeat
```

---

## 우선순위 및 충돌 해결

### 우선순위 규칙
1. 먼저 잠금을 획득한 인스턴스가 우선
2. 충돌 시 낮은 번호의 Claude가 우선 (claude-a > claude-b)
3. 긴급 작업은 `--priority high` 플래그 사용

### 데드락 방지
- 2개 이상의 파일을 동시에 잠글 때는 파일 경로의 알파벳 순서로 잠금
- 30초 이상 잠금 대기 시 타임아웃

---

## 테스트 및 빌드 조율

### 테스트 실행 전
```bash
./scripts/collab.sh request-test-slot
# 테스트 슬롯 획득 시에만 테스트 실행
npm test
./scripts/collab.sh release-test-slot
```

### 빌드 실행 전
```bash
./scripts/collab.sh request-build-slot
npm run build
./scripts/collab.sh release-build-slot
```

이렇게 하면 여러 Claude가 동시에 테스트/빌드를 실행하여 리소스 충돌을 방지합니다.

---

## 디버깅 협업

컴파일 에러 발생 시:
1. 에러를 `.claude-collab/errors/` 에 기록
2. 관련 파일 담당 Claude에게 알림
3. 필요시 공동 디버깅 세션 시작

```bash
# 에러 보고
./scripts/collab.sh report-error "에러 내용" "관련 파일"

# 디버깅 세션 시작 (다른 Claude 초대)
./scripts/collab.sh debug-session start "세션 설명"
```

---

## 주의사항

1. **절대로** 다른 Claude의 잠금 파일을 임의로 삭제하지 마세요
2. **항상** 작업 시작/종료 시 상태를 업데이트하세요
3. **정기적으로** inbox를 확인하세요
4. **충돌 발생 시** 즉시 작업을 중단하고 조율하세요

---

## Quick Reference

```bash
# 필수 명령어
./scripts/collab.sh register "작업 설명"     # 시작 시
./scripts/collab.sh lock <file>             # 파일 수정 전
./scripts/collab.sh unlock <file>           # 파일 수정 후
./scripts/collab.sh sync                    # 주기적으로
./scripts/collab.sh inbox                   # 메시지 확인
./scripts/collab.sh unregister              # 종료 시
```
