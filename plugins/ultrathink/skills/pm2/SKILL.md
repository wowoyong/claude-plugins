---
name: pm2
description: Mac Mini PM2 프로세스 관리 — 재시작, 로그 확인, 메모리 감시, 상태 조회. "pm2 관리", "프로세스 재시작", "pm2 로그" 등에 트리거.
disable-model-invocation: true
argument-hint: "<command> [app-name]  (예: restart cm-api, logs voca-app, status)"
---

# PM2 프로세스 관리

**Input**: $ARGUMENTS

## 프로젝트 자동 감지

인자가 없으면 현재 디렉토리에서 ecosystem.config 파일을 탐색:

1. `ecosystem.config.js` 또는 `ecosystem.config.cjs` 존재 확인
2. 있으면 파일 읽어서 앱 목록 파싱
3. 없으면 `pm2 jlist`로 전체 앱 목록 제시

## 명령어 라우팅

| 명령 | 동작 |
|------|------|
| `status` 또는 인자 없음 | 전체 프로세스 상태 조회 |
| `restart <app>` | 앱 재시작 (클러스터 모드면 `reload`, fork 모드면 `restart`) |
| `logs <app>` | 최근 로그 50줄 조회 |
| `memory` | 메모리 사용량 높은 앱 Top 10 |
| `cleanup` | 에러 로그 flush + 중지된 앱 정리 |

## 실행 절차

### status

```bash
pm2 jlist
```

결과를 파싱하여 테이블로 정리:
- name, status, uptime, restart count, memory, cpu
- errored/stopped 앱은 상단에 표시

### restart <app>

1. `pm2 jlist`에서 해당 앱의 `exec_mode` 확인
2. 클러스터 모드(`cluster`): `pm2 reload <app>` (무중단)
3. Fork 모드(`fork`): `pm2 restart <app>`
4. 재시작 후 5초 대기, `pm2 jlist`로 상태 확인
5. 상태가 `online`이 아니면 경고 출력

```bash
# 클러스터 모드 (cm-api, cm-web)
pm2 reload <app>

# Fork 모드 (나머지)
pm2 restart <app>

# 상태 확인
sleep 5 && pm2 jlist | jq '.[] | select(.name == "<app>") | {name, status: .pm2_env.status, memory: .monit.memory, uptime: .pm2_env.pm_uptime}'
```

### logs <app>

```bash
pm2 logs <app> --lines 50 --nostream
```

에러 로그만 보고 싶으면:
```bash
pm2 logs <app> --lines 50 --nostream --err
```

### memory

```bash
pm2 jlist | jq '[.[] | {name, memory_mb: (.monit.memory / 1048576 | floor), status: .pm2_env.status}] | sort_by(-.memory_mb) | .[:10]'
```

500MB 이상 사용 앱은 경고 표시.

### cleanup

```bash
# 에러 로그 flush
pm2 flush

# 중지된 앱 확인
pm2 jlist | jq '[.[] | select(.pm2_env.status == "stopped") | .name]'
```

중지된 앱 삭제 전 사용자에게 확인 요청.

## 주요 프로세스 참조

| name | mode | port | 프로젝트 |
|------|------|------|---------|
| cm-api | cluster(2) | 4001 | creator-marketplace/backend |
| cm-web | cluster | 4002 | creator-marketplace/frontend |
| mac-monitor | fork | 3002 | mac-monitor |
| paperclip-v2 | fork | 3050 | paperclip-v2 |
| dev-study-bot | fork | - | dev-study-bot (tsx) |
| voca-app | fork | - | voca-app |

## 자주 하는 실수

- `restart` vs `reload` 혼동 → 클러스터 모드(cm-api, cm-web)는 반드시 `reload`
- 빌드 전 `pm2 reload` → 반드시 `npm run build` 완료 후 reload
- 좀비 Node 프로세스가 포트 점유 → `lsof -i :<port>`로 확인 후 `kill -9`
- `pm2 save` 없이 재부팅 → 자동 시작 안 됨
