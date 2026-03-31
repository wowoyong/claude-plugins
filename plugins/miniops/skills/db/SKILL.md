---
name: db
description: Mac Mini DB 운영 — PostgreSQL 백업/복원, Prisma 마이그레이션, SQLite 관리. "데이터베이스", "백업", "마이그레이션", "db" 등에 트리거.
disable-model-invocation: true
argument-hint: "<command> [db-name]  (예: backup ai-hub, migrate cm-api, list, size)"
---

# DB 운영

**Input**: $ARGUMENTS

## 프로젝트 자동 감지

인자가 없으면 현재 디렉토리에서 DB 유형 판별:

1. `prisma/schema.prisma` 존재 → Prisma 프로젝트 (datasource에서 DB 유형 파악)
2. `docker-compose.yml` 내 postgres 서비스 → Docker PostgreSQL
3. `*.db` 파일 존재 → SQLite
4. 아무것도 없으면 → `list` 명령 실행

## 명령어 라우팅

| 명령 | 동작 |
|------|------|
| `list` 또는 인자 없음 | 실행 중인 DB 인스턴스 목록 |
| `backup <db>` | pg_dump로 백업 생성 |
| `restore <file>` | 백업 파일에서 복원 (확인 필수) |
| `migrate` | Prisma migrate deploy 실행 |
| `size` | DB 크기 및 테이블별 용량 |

## 실행 절차

### list

```bash
# Docker PostgreSQL 인스턴스
docker ps --filter "ancestor=postgres" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# SQLite 파일 찾기
find /Users/jojaeyong/WebstormProjects -name "*.db" -o -name "*.sqlite" 2>/dev/null | head -20

# Prisma 프로젝트 찾기
find /Users/jojaeyong/WebstormProjects -name "schema.prisma" -path "*/prisma/*" 2>/dev/null | head -20
```

### backup <db>

**Docker PostgreSQL:**
```bash
# 타임스탬프 파일명으로 백업
BACKUP_FILE="backup_<db>_$(date +%Y%m%d_%H%M%S).sql"

# ai-hub (port 5434, user: postgres)
docker exec <container> pg_dump -U postgres <dbname> > ~/backups/$BACKUP_FILE

# 또는 docker compose 사용
docker compose exec db pg_dump -U <user> <dbname> > ~/backups/$BACKUP_FILE

echo "백업 완료: ~/backups/$BACKUP_FILE"
ls -lh ~/backups/$BACKUP_FILE
```

**SQLite:**
```bash
cp <path/to/db.sqlite> ~/backups/backup_<name>_$(date +%Y%m%d_%H%M%S).sqlite
```

백업 디렉토리가 없으면 생성:
```bash
mkdir -p ~/backups
```

### restore <file>

**반드시 사용자 확인 후 실행.** 현재 데이터가 덮어써집니다.

**Docker PostgreSQL:**
```bash
# 1. 현재 DB 백업 (안전장치)
docker exec <container> pg_dump -U postgres <dbname> > ~/backups/pre_restore_$(date +%Y%m%d_%H%M%S).sql

# 2. 복원
docker exec -i <container> psql -U postgres <dbname> < <backup-file>
```

**SQLite:**
```bash
cp <backup-file> <original-path>
```

### migrate

Prisma 프로젝트 디렉토리에서:
```bash
npx prisma migrate deploy
```

Docker Compose 환경:
```bash
docker compose exec app npx prisma migrate deploy
```

마이그레이션 전 반드시 백업 권고.

### size

**Docker PostgreSQL:**
```bash
docker exec <container> psql -U postgres -d <dbname> -c "
SELECT
  schemaname || '.' || tablename AS table,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
LIMIT 20;
"
```

**SQLite:**
```bash
ls -lh <path/to/db.sqlite>
sqlite3 <path/to/db.sqlite> ".tables"
```

## 현재 DB 인스턴스 참조

| DB | 유형 | 포트 | 프로젝트 | 컨테이너 |
|----|------|------|---------|----------|
| ai-hub | PostgreSQL 16 | 5434 | ai-hub | ai-hub-postgres-1 |
| freeSchedule | PostgreSQL 16 | 5433 | freeSchedule | freeschedule-db-1 |
| voca-app | SQLite x3 | - | voca-app | 파일 기반 |
| paperclip-v2 | SQLite | - | paperclip-v2 | 파일 기반 |

## 자주 하는 실수

- 복원 전 백업 안 함 → 항상 pre_restore 백업 먼저
- Docker exec에서 `-i` 플래그 누락 → stdin 리다이렉션 실패
- Prisma migrate deploy vs migrate dev 혼동 → 프로덕션은 `deploy`만
- SQLite 파일 복사 중 앱이 쓰기 중 → 앱 중지 후 복사
