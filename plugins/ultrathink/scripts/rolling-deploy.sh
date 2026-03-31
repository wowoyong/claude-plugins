#!/usr/bin/env bash
# ultrathink: 다수 PM2 앱 순차 재시작 + 헬스체크
# Usage: rolling-deploy.sh [app1 app2 ...] 또는 ecosystem.config에서 자동 추출
#
# 각 앱을 순차적으로 reload/restart 하면서 헬스체크.
# 하나라도 실패하면 즉시 중단.

set -euo pipefail

WAIT_SECONDS=5

# 인자가 없으면 ecosystem.config에서 앱 목록 추출
if [ $# -eq 0 ]; then
  CONFIG=""
  for f in ecosystem.config.js ecosystem.config.cjs; do
    if [ -f "$f" ]; then
      CONFIG="$f"
      break
    fi
  done

  if [ -z "$CONFIG" ]; then
    echo "ERROR: 앱 이름을 인자로 전달하거나, ecosystem.config.js/cjs가 있는 디렉토리에서 실행하세요."
    exit 1
  fi

  # Node.js로 앱 이름 추출
  APPS=$(node -e "
    const cfg = require('./$CONFIG');
    const apps = cfg.apps || cfg;
    apps.forEach(a => console.log(a.name));
  " 2>/dev/null)

  if [ -z "$APPS" ]; then
    echo "ERROR: $CONFIG에서 앱 목록을 추출할 수 없습니다."
    exit 1
  fi
else
  APPS="$*"
fi

TOTAL=$(echo "$APPS" | wc -w | tr -d ' ')
CURRENT=0
FAILED=()

echo "=== Rolling Deploy: $TOTAL apps ==="
echo ""

for APP in $APPS; do
  CURRENT=$((CURRENT + 1))
  echo "[$CURRENT/$TOTAL] Deploying: $APP"

  # exec_mode 확인
  MODE=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name == \"$APP\") | .pm2_env.exec_mode" 2>/dev/null || echo "fork")

  if [ "$MODE" = "cluster_mode" ]; then
    pm2 reload "$APP" 2>/dev/null
  else
    pm2 restart "$APP" 2>/dev/null
  fi

  echo "  Waiting ${WAIT_SECONDS}s for health check..."
  sleep "$WAIT_SECONDS"

  # 상태 확인
  STATUS=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name == \"$APP\") | .pm2_env.status" 2>/dev/null || echo "unknown")

  if [ "$STATUS" = "online" ]; then
    echo "  ✓ $APP: online"
  else
    echo "  ✗ $APP: $STATUS — ABORTING"
    FAILED+=("$APP")
    echo ""
    echo "=== Rolling Deploy FAILED at $APP ==="
    echo "Successfully deployed: $((CURRENT - 1))/$TOTAL"
    echo "Failed app: ${FAILED[*]}"
    echo "Remaining apps were NOT restarted."
    exit 1
  fi

  echo ""
done

echo "=== Rolling Deploy COMPLETE: $TOTAL/$TOTAL apps ==="
