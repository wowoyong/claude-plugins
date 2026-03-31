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

echo "======================================"
