---
name: deploy
description: Mac Mini 프로젝트 배포 — git pull, build, PM2/Docker 재시작, 헬스체크. "배포", "deploy", "배포해줘" 등에 트리거.
disable-model-invocation: true
argument-hint: "[project-name]  (예: cm-api, paperclip-v2, ai-hub)"
---

# 배포 워크플로우

**Input**: $ARGUMENTS

## 프로젝트 자동 감지

인자가 없으면 현재 디렉토리에서 프로젝트 유형 판별:

1. `ecosystem.config.js/cjs` 존재 → PM2 배포
2. `docker-compose.yml` 존재 → Docker Compose 배포
3. `package.json`만 존재 → 빌드 타입 확인 후 안내
4. 아무것도 없으면 → 프로젝트 이름 입력 요청

## 배포 절차

### Step 1: 배포 전 상태 스냅샷

```bash
# 현재 커밋 해시 기록 (롤백용)
PREV_COMMIT=$(git rev-parse HEAD)
echo "현재 커밋: $PREV_COMMIT"

# PM2 프로젝트: 현재 상태 기록
pm2 jlist | jq '.[] | select(.name == "<app>") | {name, status: .pm2_env.status, uptime: .pm2_env.pm_uptime}'

# Docker 프로젝트: 컨테이너 상태 기록
docker compose ps
```

### Step 2: 코드 업데이트

```bash
git pull origin main
```

충돌 발생 시 중단하고 사용자에게 보고.

### Step 3: 의존성 설치 + 빌드

**PM2 프로젝트 (Node.js):**
```bash
npm install
npm run build  # NestJS: dist/, Next.js: .next/
```

**Docker Compose 프로젝트:**
```bash
docker compose build --no-cache <service>
```

빌드 실패 시 중단하고 에러 로그 출력.

### Step 4: 서비스 재시작

**PM2 (클러스터 모드):**
```bash
pm2 reload <app>
```

**PM2 (fork 모드):**
```bash
pm2 restart <app>
```

**Docker Compose:**
```bash
docker compose up -d <service>
```

### Step 5: 헬스체크

```bash
# 5초 대기
sleep 5

# PM2 상태 확인
pm2 jlist | jq '.[] | select(.name == "<app>") | {status: .pm2_env.status}'

# HTTP 엔드포인트가 있으면 curl
curl -sf http://localhost:<port>/api/health || echo "HEALTH CHECK FAILED"

# Docker 상태 확인
docker compose ps --format json | jq '.[].Health // "N/A"'
```

상태가 `online`/`healthy`가 아니면 즉시 경고.

### Step 6: 결과 보고

성공/실패 여부와 함께:
- 이전 커밋 → 현재 커밋
- 배포 소요 시간
- 현재 서비스 상태

## 롤백 절차

배포 실패 시 안내할 롤백 명령:

```bash
git checkout <PREV_COMMIT>
npm install && npm run build
pm2 reload <app>
```

## 프로젝트별 배포 참조

| 프로젝트 | 타입 | 포트 | 빌드 명령 | 재시작 |
|---------|------|------|----------|--------|
| cm-api | PM2 cluster | 4001 | `npm run build` | `pm2 reload cm-api` |
| cm-web | PM2 cluster | 4002 | `npm run build` | `pm2 reload cm-web` |
| paperclip-v2 | PM2 fork | 3050 | `npm run build` | `pm2 restart paperclip-v2` |
| ai-hub | Docker | 5434,6380 | `docker compose build` | `docker compose up -d` |
| dev-study-bot | PM2 fork (tsx) | - | 없음 | `pm2 restart dev-study-bot` |

## 파일 전송 Gotcha

### 브라켓 경로 (Next.js 동적 라우트)
```bash
# scp 실패함 → cat 파이프 사용
cat local-file.tsx | ssh mac-mini 'cat > ~/project/app/[id]/page.tsx'
```

### SSH heredoc
```bash
# 반드시 'EOF' (따옴표)로 변수 확장 방지
ssh mac-mini << 'EOF'
  cd ~/WebstormProjects/<project> && npm run build && pm2 reload <app>
EOF
```

## 자주 하는 실수

- 빌드 전 reload → 반드시 빌드 완료 후
- Docker `--build` 누락 → 코드 변경 미반영
- `.env` 파일 미존재 → 배포 전 확인 필수
- `restart` vs `reload` 혼동 → 클러스터 모드는 reload
