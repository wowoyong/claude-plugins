#!/usr/bin/env bash
# ultrathink: SessionStart hook — Mac Mini 인프라 상태 요약 출력

set -euo pipefail

echo "=== Mac Mini Infrastructure Status ==="

# PM2 상태 요약
if command -v pm2 &>/dev/null; then
  PM2_JSON=$(pm2 jlist 2>/dev/null || echo "[]")
  TOTAL=$(echo "$PM2_JSON" | jq 'length' 2>/dev/null || echo "0")
  ONLINE=$(echo "$PM2_JSON" | jq '[.[] | select(.pm2_env.status == "online")] | length' 2>/dev/null || echo "0")
  STOPPED=$(echo "$PM2_JSON" | jq '[.[] | select(.pm2_env.status == "stopped")] | length' 2>/dev/null || echo "0")
  ERRORED=$(echo "$PM2_JSON" | jq '[.[] | select(.pm2_env.status == "errored")] | length' 2>/dev/null || echo "0")
  echo "PM2: ${ONLINE}/${TOTAL} online (${STOPPED} stopped, ${ERRORED} errored)"
else
  echo "PM2: not installed"
fi

# Docker 상태 요약
if command -v docker &>/dev/null; then
  RUNNING=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  TOTAL_C=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
  echo "Docker: ${RUNNING}/${TOTAL_C} running"
else
  echo "Docker: not installed"
fi

# 디스크 사용량
DISK_USAGE=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}')
echo "Disk: ${DISK_USAGE} used"

# 마지막 배포 시각 (git log 기반)
LAST_DEPLOY=$(git -C /Users/jojaeyong/WebstormProjects log --all --oneline --format="%cr" -1 2>/dev/null)
if [ -n "$LAST_DEPLOY" ]; then
  echo "Last Deploy: ${LAST_DEPLOY}"
fi

# 프로필 밸런싱 (프로필이 2개 이상일 때만)
PROFILES_DIR="$HOME/.claude/profiles"
PROFILE_COUNT=$(find "$PROFILES_DIR" -maxdepth 1 -mindepth 1 -type d ! -name '_previous' ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$PROFILE_COUNT" -ge 2 ]; then
  BALANCE_RESULT=$(python3 -c "
import json, os, time, datetime

profiles_dir = os.path.expanduser('~/.claude/profiles')
cred_file = os.path.expanduser('~/.claude/.credentials.json')
usage_file = os.path.join(profiles_dir, '.usage.json')
today = datetime.date.today().isoformat()

# usage DB 로드
try: usage_db = json.load(open(usage_file))
except: usage_db = {}

# 현재 프로필 식별
current = json.load(open(cred_file))
current_rt = current.get('claudeAiOauth', {}).get('refreshToken', '')
current_name = 'unknown'
for name in os.listdir(profiles_dir):
    cp = os.path.join(profiles_dir, name, '.credentials.json')
    if name in ('_previous',) or name.startswith('.') or not os.path.isfile(cp): continue
    p = json.load(open(cp))
    if p.get('claudeAiOauth', {}).get('refreshToken', '') == current_rt:
        current_name = name
        break

# 현재 세션 사용량 기록 (stats-cache에서)
try:
    stats = json.load(open(os.path.expanduser('~/.claude/stats-cache.json')))
    today_tokens = 0
    for day in stats.get('dailyModelTokens', []):
        if day.get('date') == today:
            today_tokens = sum(day.get('tokensByModel', {}).values())
            break
    if current_name != 'unknown':
        if current_name not in usage_db:
            usage_db[current_name] = {'daily': {}, 'total': 0}
        usage_db[current_name]['daily'][today] = today_tokens
        usage_db[current_name]['total'] = sum(usage_db[current_name]['daily'].values())
        json.dump(usage_db, open(usage_file, 'w'), indent=2)
except: today_tokens = 0

# 다음 세션을 위해 최적 프로필 선택
candidates = []
for name in os.listdir(profiles_dir):
    cp = os.path.join(profiles_dir, name, '.credentials.json')
    if name in ('_previous',) or name.startswith('.') or not os.path.isfile(cp): continue
    p = json.load(open(cp))
    exp = p.get('claudeAiOauth', {}).get('expiresAt', 0)
    expired = exp < time.time() * 1000
    day_usage = usage_db.get(name, {}).get('daily', {}).get(today, 0)
    candidates.append({'name': name, 'today': day_usage, 'expired': expired})

valid = [c for c in candidates if not c['expired']] or candidates
valid.sort(key=lambda c: c['today'])
best = valid[0]['name'] if valid else current_name

# 토큰 상태
exp = current.get('claudeAiOauth', {}).get('expiresAt', 0)
remaining_h = (exp - time.time() * 1000) / 1000 / 3600
tok = '✅' if remaining_h > 6 else ('⚠️' if remaining_h > 0 else '❌')

# 다음 세션용 credentials 교체 (현재 세션과 다를 때만)
switched = ''
if best != current_name and best != 'unknown':
    backup_dir = os.path.join(profiles_dir, '_previous')
    os.makedirs(backup_dir, exist_ok=True)
    import shutil
    shutil.copy2(cred_file, os.path.join(backup_dir, '.credentials.json'))
    best_cred = os.path.join(profiles_dir, best, '.credentials.json')
    shutil.copy2(best_cred, cred_file)
    os.chmod(cred_file, 0o600)
    switched = f' → Next: {best}'

# 사용량 요약
usage_parts = []
for c in sorted(candidates, key=lambda x: x['name']):
    marker = '◀' if c['name'] == current_name else ' '
    usage_parts.append(f\"{c['name']}:{c['today']//1000}k{marker}\")
usage_summary = ' | '.join(usage_parts)

print(f'Profile: {current_name} {tok} ({remaining_h:.0f}h) [{usage_summary}]{switched}')
" 2>/dev/null)
  echo "$BALANCE_RESULT"
fi

echo "======================================"
