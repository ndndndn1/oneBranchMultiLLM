# Multi-Claude Workflow Examples

이 문서는 여러 Claude Code 인스턴스가 협업하는 실제 시나리오를 보여줍니다.

## Scenario 1: Feature Development (2 Claude 협업)

### 상황
새로운 사용자 인증 기능을 구현해야 합니다.
- Claude-A: 프론트엔드 담당
- Claude-B: 백엔드 담당

### 워크플로우

**Claude-A (Terminal 1):**
```bash
# 1. 등록
export CLAUDE_ID="claude-frontend"
./scripts/collab.sh register "Implementing login UI"

# 2. 파일 잠금 및 작업
./scripts/collab.sh lock src/components/Login.tsx
./scripts/collab.sh lock src/components/Login.css

# 3. 코드 작성...
# (Claude Code가 파일 수정)

# 4. 커밋 및 푸시
./scripts/conflict_resolver.sh safe-commit "feat: add Login component"
./scripts/conflict_resolver.sh safe-push

# 5. 잠금 해제 및 알림
./scripts/collab.sh unlock src/components/Login.tsx
./scripts/collab.sh unlock src/components/Login.css
./scripts/collab.sh send claude-backend "Login UI ready, API: POST /api/auth/login"
```

**Claude-B (Terminal 2):**
```bash
# 1. 등록
export CLAUDE_ID="claude-backend"
./scripts/collab.sh register "Implementing auth API"

# 2. 메시지 확인
./scripts/collab.sh inbox

# 3. 파일 잠금 및 작업
./scripts/collab.sh lock src/api/auth.ts
./scripts/collab.sh lock src/middleware/auth.ts

# 4. API 구현...

# 5. 커밋 및 푸시
./scripts/conflict_resolver.sh safe-commit "feat: add auth API endpoints"
./scripts/conflict_resolver.sh safe-push

# 6. 완료 알림
./scripts/collab.sh unlock src/api/auth.ts
./scripts/collab.sh unlock src/middleware/auth.ts
./scripts/collab.sh send claude-frontend "API ready: POST /api/auth/login, /logout"
```

---

## Scenario 2: Bug Fix (3 Claude 협업)

### 상황
프로덕션 버그 수정이 필요합니다.
- Claude-A: 버그 분석
- Claude-B: 수정 구현
- Claude-C: 테스트 작성

### 워크플로우

**Claude-A (분석):**
```bash
export CLAUDE_ID="claude-analyst"
./scripts/collab.sh register "Analyzing payment bug"

# 분석 수행...
# 결과를 다른 Claude에게 공유
./scripts/collab.sh broadcast "Bug found in src/payment/checkout.ts:145 - race condition"
./scripts/collab.sh complete "Bug analysis"
./scripts/collab.sh unregister
```

**Claude-B (수정):**
```bash
export CLAUDE_ID="claude-fixer"
./scripts/collab.sh register "Fixing payment race condition"
./scripts/collab.sh inbox  # 분석 결과 확인

./scripts/collab.sh lock src/payment/checkout.ts

# 수정 작업...

./scripts/conflict_resolver.sh safe-commit "fix: race condition in checkout"
./scripts/conflict_resolver.sh safe-push

./scripts/collab.sh unlock src/payment/checkout.ts
./scripts/collab.sh send claude-tester "Fix ready, please verify"
```

**Claude-C (테스트):**
```bash
export CLAUDE_ID="claude-tester"
./scripts/collab.sh register "Testing payment fix"
./scripts/collab.sh inbox

# 테스트 슬롯 획득
./scripts/collab.sh request-test-slot

./scripts/collab.sh lock tests/payment.test.ts

# 테스트 작성 및 실행
npm test

./scripts/collab.sh release-test-slot
./scripts/collab.sh unlock tests/payment.test.ts

./scripts/collab.sh broadcast "All tests passed! Fix verified."
```

---

## Scenario 3: 대규모 리팩토링 (4 Claude 협업)

### 상황
모놀리식 코드를 마이크로서비스로 분리합니다.

### 영역 분배

| Claude ID | 담당 영역 |
|-----------|----------|
| claude-user-svc | 사용자 서비스 |
| claude-order-svc | 주문 서비스 |
| claude-payment-svc | 결제 서비스 |
| claude-gateway | API 게이트웨이 |

### 워크플로우

```bash
# 각 Claude가 자신의 영역 등록
./scripts/collab.sh register "Extracting user service"

# 디렉토리 단위로 잠금
./scripts/collab.sh lock services/user/
./scripts/collab.sh lock src/user/

# 작업 수행...

# 주기적 동기화
./scripts/collab.sh sync

# 의존성 변경 시 알림
./scripts/collab.sh broadcast "User service API changed: getUserById -> findUserById"
```

---

## Scenario 4: 긴급 디버깅 세션

### 상황
여러 Claude가 함께 복잡한 버그를 디버깅합니다.

```bash
# Claude-A가 디버그 세션 시작
./scripts/collab.sh debug-session start "Memory leak investigation"

# Claude-B가 참여
./scripts/collab.sh debug-session join

# 실시간 정보 공유
./scripts/collab.sh broadcast "Found suspicious allocation in cache.ts:89"
./scripts/collab.sh broadcast "Confirmed: cache not clearing on timeout"

# 세션 종료
./scripts/collab.sh debug-session end
```

---

## Best Practices

### 1. 항상 잠금 먼저
```bash
# Good
./scripts/collab.sh lock src/file.ts
# ... edit ...
./scripts/collab.sh unlock src/file.ts

# Bad - 충돌 위험!
# ... edit without lock ...
```

### 2. 작은 단위로 커밋
```bash
# Good - 작은 변경, 자주 푸시
git commit -m "feat: add user validation"
git push

# Bad - 큰 변경, 나중에 푸시
# ... many changes over hours ...
git commit -m "add many features"  # 충돌 가능성 높음
```

### 3. 주기적 동기화
```bash
# 10분마다 실행 권장
./scripts/collab.sh sync
```

### 4. 명확한 커뮤니케이션
```bash
# 작업 시작 시
./scripts/collab.sh broadcast "Starting work on auth module"

# 중요 변경 시
./scripts/collab.sh broadcast "Changed API: login() now returns token"

# 완료 시
./scripts/collab.sh complete "Auth module refactoring"
```

### 5. 충돌 발생 시 즉시 중단
```bash
# 충돌 감지되면
./scripts/collab.sh broadcast "[CONFLICT] Please pause work on user module"

# 해결 후
./scripts/collab.sh broadcast "[RESOLVED] User module conflict resolved, safe to continue"
```

---

## JetBrains Code With Me 연동

Code With Me를 사용할 때:

1. **호스트 Claude**: 세션 생성 및 다른 Claude 초대
2. **게스트 Claude**: 초대 링크로 참여

### 장점
- 실시간 코드 공유
- 동일 파일 동시 편집 가능
- 변경사항 즉시 동기화

### 설정
```bash
# Code With Me 세션 시작 후
./scripts/collab.sh broadcast "Code With Me session started: [link]"

# 참여 후 등록
./scripts/collab.sh register "Joining Code With Me session"
```

---

## 문제 해결

### 잠금이 해제되지 않음
```bash
# 비활성 인스턴스 잠금 정리
./scripts/collab.sh sync
```

### 메시지가 전달되지 않음
```bash
# 직접 inbox 확인
ls -la .claude-collab/messages/
```

### Git 충돌 발생
```bash
# 자동 해결 시도
./scripts/conflict_resolver.sh coordinate

# 수동 해결 필요 시
./scripts/conflict_resolver.sh list
# 파일별로 해결
./scripts/conflict_resolver.sh resolve path/to/file ours
```
