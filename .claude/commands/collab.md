# Multi-Claude Collaboration Command

이 프로젝트는 여러 Claude Code 인스턴스가 협업하는 시스템입니다.

## 사용 가능한 협업 명령어

### 세션 관리
- `./scripts/collab.sh register "작업 설명"` - 협업 세션 등록
- `./scripts/collab.sh overview` - 현재 협업 상황 확인
- `./scripts/collab.sh unregister` - 세션 종료

### 계획 공유
- `./scripts/collab.sh share-plan "제목" "설명" "파일"` - 작업 계획 공유
- `./scripts/collab.sh view-plans` - 다른 Claude의 계획 확인
- `./scripts/collab.sh start-plan <id>` - 계획 실행 시작
- `./scripts/collab.sh complete-plan <id>` - 계획 완료

### 수정 공유
- `./scripts/collab.sh share-edit <파일> <타입> "설명"` - 수정 시작 알림
- `./scripts/collab.sh view-edits` - 다른 Claude의 수정 확인
- `./scripts/collab.sh finish-edit <파일>` - 수정 완료

### 협업적 사고
- `./scripts/collab.sh propose question "질문"` - 질문하기
- `./scripts/collab.sh propose approach "제안" "상세"` - 접근법 제안
- `./scripts/collab.sh discuss "주제" "메시지"` - 토론 시작

### JSON 출력 (Agent 친화적)
- `./scripts/collab.sh --json overview` - JSON으로 협업 상황 조회

## 권장 워크플로우

1. 세션 시작: `register`
2. 상황 파악: `overview`, `view-plans`, `view-edits`
3. 계획 공유: `share-plan`
4. 작업 시작: `start-plan`, `share-edit`
5. 작업 완료: `finish-edit`, `complete-plan`
6. 세션 종료: `unregister`

## 협업 규칙

- **항상** 작업 전에 `overview`로 상황 파악
- **항상** 파일 수정 전에 `share-plan`과 `share-edit` 실행
- **같은 파일 수정 시** 자동 경고 발송됨 - 조율 필요
