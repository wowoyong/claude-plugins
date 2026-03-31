---
name: health
description: Mac Mini 인프라 전체 상태 점검 — PM2, Docker, 디스크, 포트, 네트워크. "헬스체크", "상태 확인", "health", "인프라 점검" 등에 트리거.
argument-hint: "[section]  (예: pm2, docker, disk, ports, all)"
---

# 인프라 헬스체크

**Input**: $ARGUMENTS

이 스킬은 읽기 전용입니다. 수정/재시작 작업은 해당 스킬(pm2, docker, deploy)을 사용하세요.

## 섹션 라우팅

| 섹션 | 동작 |
|------|------|
| `all` 또는 인자 없음 | 전체 점검 |
| `pm2` | PM2 프로세스만 |
| `docker` | Docker 컨테이너만 |
| `disk` | 디스크 사용량만 |
| `ports` | 포트 충돌 검사만 |

## 전체 점검 절차

### 1. PM2 프로세스 상태

```bash
pm2 jlist | jq '{
  total: length,
  online: [.[] | select(.pm2_env.status == "online")] | length,
  stopped: [.[] | select(.pm2_env.status == "stopped")] | length,
  errored: [.[] | select(.pm2_env.status == "errored")] | length,
  high_memory: [.[] | select(.monit.memory > 524288000) | .name],
  high_restarts: [.[] | select(.pm2_env.restart_time > 50) | {name, restarts: .pm2_env.restart_time}]
}'
```

- online이 아닌 앱 목록 강조
- 메모리 500MB 초과 앱 경고
- 재시작 50회 초과 앱 경고

### 2. Docker 컨테이너 상태

```bash
docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"
```

- running/healthy 아닌 컨테이너 강조
- 헬스체크 실패 컨테이너 경고

### 3. 디스크 사용량

```bash
df -h / /System/Volumes/Data 2>/dev/null | tail -n +2
```

- 사용량 80% 이상이면 경고
- 90% 이상이면 긴급 경고 + 정리 권고

### 4. 포트 충돌 검사

```bash
# 주요 포트 점유 현황
for port in 3000 3002 3050 4001 4002 5432 5433 5434 6380 8000 8082; do
  pid=$(lsof -ti :$port 2>/dev/null)
  if [ -n "$pid" ]; then
    proc=$(ps -p $pid -o comm= 2>/dev/null)
    echo "$port: $proc (PID $pid)"
  fi
done
```

같은 포트에 여러 프로세스가 있으면 충돌 경고.

### 5. 시스템 리소스

```bash
# CPU/메모리 상위 프로세스 (macOS BSD ps)
ps -axo pid,pcpu,pmem,comm | sort -k3 -rn | head -10

# 시스템 메모리
vm_stat | head -5
```

## 결과 출력 형식

```
## Mac Mini Health Report

### PM2: ✅ 24/24 online (0 errored, 0 stopped)
  ⚠️ blog-review: 42 restarts
  ⚠️ scraper-server: 52.6MB memory

### Docker: ✅ 3/3 running
  ai-hub-postgres-1: healthy (45h uptime)
  ai-hub-redis-1: healthy (45h uptime)

### Disk: ✅ 65% used (234GB free)

### Ports: ✅ No conflicts detected

### System: ℹ️ CPU 12%, Memory 68%
```

## 자주 하는 실수

- `lsof` 권한 문제 → sudo 없이도 자신의 프로세스는 확인 가능
- `vm_stat` 출력이 page 단위 → 4096 곱해서 바이트 변환 필요
