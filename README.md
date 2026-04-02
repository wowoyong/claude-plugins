# wowoyong Claude Code Plugins

> Mac Mini 인프라 운영 + AI 코딩 생산성 도구 모음

## 설치

```bash
# 마켓플레이스에서 설치
claude plugin marketplace add wowoyong/claude-plugins

# 개별 플러그인 설치
claude plugin install miniops
claude plugin install agent-mux
claude plugin install architecture-enforcer
claude plugin install harness-docs
claude plugin install harness-planner
```

## 플러그인 목록

### miniops — Mac Mini 인프라 운영 `v1.0.0`

PM2, Docker, 배포, DB, 헬스체크, 멀티 계정 관리를 위한 통합 운영 도구.

| 스킬 | 명령어 | 설명 |
|------|--------|------|
| pm2 | `/pm2` | PM2 프로세스 관리 (시작/중지/재시작/로그) |
| docker | `/docker` | Docker 컨테이너/이미지 관리 |
| deploy | `/deploy` | 롤링 배포 실행 |
| db | `/db` | PostgreSQL 백업/복구/마이그레이션 |
| health | `/health` | 인프라 전체 상태 점검 (PM2/Docker/디스크/포트) |
| profile | `/profile` | 멀티 계정 프로필 관리 + 사용량 밸런싱 + 토큰 자동 갱신 |
| verify | `/verify` | 커밋 전 프로젝트 전체 검증 (lint/type/test/security) + 자동 수정 |

### agent-mux — 작업 라우팅 `v0.7.0`

Claude Code와 Codex CLI 간 작업을 자동으로 라우팅. 구독 효율 최적화.

| 스킬 | 설명 |
|------|------|
| mux | 태스크 분석 → Claude/Codex 자동 배분 |

### architecture-enforcer — 아키텍처 검증 `v2.0.0`

모듈 경계, 레이어 의존성, 네이밍 규칙, 구조 무결성 자동 검증.

| 스킬 | 설명 |
|------|------|
| architecture | 아키텍처 규칙 위반 탐지 + 수정 가이드 |

### harness-docs — 문서 관리 `v1.0.0`

에이전트를 위한 레포 내 문서 시스템. AGENTS.md 자동 생성/관리.

| 스킬 | 설명 |
|------|------|
| harness-docs | 인덱스, 품질 진단, 자동 추출 |

### harness-planner — 계획 관리 `v1.0.0`

실행 계획, 기술 부채, 추적성을 버전 관리되는 아티팩트로 관리.

| 스킬 | 설명 |
|------|------|
| harness-planner | 작업 분해 + 부채 추적 + 추적성 검증 |

## 관련 프로젝트

- [claude-multi-account](https://github.com/wowoyong/claude-multi-account) — 멀티 계정 프로필 관리 (standalone)

## License

MIT
