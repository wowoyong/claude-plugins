---
name: docker
description: Mac Mini Docker 컨테이너 운영 — 시작/중지, 볼륨 관리, 이미지 정리, 로그. "도커 관리", "컨테이너", "docker" 등에 트리거.
disable-model-invocation: true
argument-hint: "<command> [service]  (예: restart postgres, logs redis, prune, status)"
---

# Docker 컨테이너 운영

**Input**: $ARGUMENTS

## 프로젝트 자동 감지

인자가 없으면 현재 디렉토리에서 `docker-compose.yml` 탐색:

1. 존재하면 해당 파일의 서비스 목록 파싱
2. 없으면 `docker ps -a`로 전체 컨테이너 목록 제시

## 명령어 라우팅

| 명령 | 동작 |
|------|------|
| `status` 또는 인자 없음 | 전체 컨테이너 상태 조회 |
| `restart <service>` | docker compose 서비스 재시작 |
| `logs <service>` | 컨테이너 로그 50줄 |
| `prune` | 미사용 이미지/볼륨 정리 (확인 후) |
| `rebuild <service>` | 이미지 리빌드 + 컨테이너 재생성 |

## 실행 절차

### status

```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
```

docker-compose.yml이 있으면 추가로:
```bash
docker compose ps
```

### restart <service>

docker-compose.yml이 있는 디렉토리에서:
```bash
docker compose restart <service>
```

없으면 컨테이너 이름으로:
```bash
docker restart <container-name>
```

재시작 후 상태 확인:
```bash
docker ps --filter "name=<service>" --format "{{.Names}}: {{.Status}}"
```

### logs <service>

docker-compose.yml이 있으면:
```bash
docker compose logs <service> --tail=50 --no-log-prefix
```

없으면:
```bash
docker logs <container-name> --tail=50
```

### prune

사용자에게 확인 받은 후 실행:

```bash
# 중지된 컨테이너 정리
docker container prune -f

# 사용 안 하는 이미지 정리
docker image prune -f

# dangling 볼륨 정리 (데이터 볼륨 아닌 것만)
docker volume prune -f
```

전체 정리 (`docker system prune -a`)는 ops-guard 훅이 차단 — 사용자 명시 확인 필요.

### rebuild <service>

```bash
docker compose build --no-cache <service>
docker compose up -d <service>
```

빌드 후 상태 확인:
```bash
docker compose ps <service>
```

## 현재 Docker 서비스 참조

| 서비스 | 이미지 | 포트 | 프로젝트 |
|--------|--------|------|---------|
| postgres (ai-hub) | postgres:16 | 5434 | ai-hub |
| redis (ai-hub) | redis:7 | 6380 | ai-hub |
| postgres (freeSchedule) | postgres:16-alpine | 5433 | freeSchedule |

## credsStore 오류 해결

```bash
# "error getting credentials - err: exec: docker-credential-desktop"
# ~/.docker/config.json에서 credsStore 항목 제거:
# { "auths": {} }
```

## 자주 하는 실수

- `docker compose down -v`로 DB 데이터 삭제 → 볼륨 백업 후 진행
- 맥미니 로컬 PostgreSQL(5432)과 컨테이너 포트 충돌 → 외부 포트 5433/5434 사용
- `--build` 없이 `docker compose up -d` → 코드 변경 미반영
- healthcheck 없이 app 시작 → DB 준비 전 연결 시도 오류
