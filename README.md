# Multi-Claude Collaboration System

여러 Claude Code 인스턴스가 하나의 브랜치에서 동시에 협업할 수 있는 시스템입니다.

## 왜 필요한가?

- 복잡한 기능을 여러 Claude가 병렬로 구현하여 **2배 이상 빠르게** 완료
- 프론트엔드/백엔드/테스트를 동시에 개발
- 대규모 리팩토링을 안전하게 분산 처리

## Quick Start

```bash
# 1. 초기화
./scripts/init-collab.sh

# 2. Claude 인스턴스 등록
export CLAUDE_ID="claude-1"  # 고유 ID 설정
./scripts/collab.sh register "My task description"

# 3. 상태 확인
./scripts/collab.sh status

# 4. 파일 잠금 후 작업
./scripts/collab.sh lock src/myfile.ts
# ... 작업 ...
./scripts/collab.sh unlock src/myfile.ts

# 5. 안전하게 커밋/푸시
./scripts/conflict_resolver.sh safe-commit "feat: add feature"
./scripts/conflict_resolver.sh safe-push
```

## 핵심 기능

### 파일 잠금 시스템
충돌을 방지하기 위해 수정 전 파일을 잠급니다.

```bash
./scripts/collab.sh lock <file>
./scripts/collab.sh unlock <file>
```

### 메시지 시스템
Claude 인스턴스 간 통신을 지원합니다.

```bash
./scripts/collab.sh send <claude_id> "message"
./scripts/collab.sh broadcast "message to all"
./scripts/collab.sh inbox
```

### 충돌 해결
Git 충돌을 자동으로 감지하고 해결합니다.

```bash
./scripts/conflict_resolver.sh detect
./scripts/conflict_resolver.sh safe-pull
./scripts/conflict_resolver.sh safe-push
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
    │(Frontend) │        │(Backend)  │        │(Tests)    │
    └───────────┘        └───────────┘        └───────────┘
          │                    │                    │
          └────────────────────┼────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │  .claude-collab/    │
                    │  ├── instances/     │ ← 활성 인스턴스
                    │  ├── locks/         │ ← 파일 잠금
                    │  ├── messages/      │ ← 메시지 큐
                    │  └── tasks/         │ ← 작업 상태
                    └─────────────────────┘
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
    ├── locks/
    ├── messages/
    └── tasks/
```

## 요구사항

- Bash
- jq (JSON 처리)
- Git
- Python 3.x (브릿지 서버 사용 시)

## JetBrains Code With Me 연동

Code With Me와 함께 사용하면 더욱 효과적입니다:

1. Code With Me 세션 시작
2. 각 Claude Code가 다른 터미널에서 실행
3. 파일 잠금 시스템으로 충돌 방지
4. 실시간 코드 공유

## 라이선스

MIT
