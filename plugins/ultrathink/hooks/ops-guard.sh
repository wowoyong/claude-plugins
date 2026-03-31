#!/usr/bin/env bash
# ultrathink: PreToolUse Bash hook — 위험한 운영 명령 감지
# decision: ask (사용자에게 확인 요청)

set -euo pipefail

# $CLAUDE_TOOL_INPUT contains the Bash command as JSON
COMMAND=$(echo "${CLAUDE_TOOL_INPUT:-}" | jq -r '.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# 위험 패턴 목록
DANGEROUS_PATTERNS=(
  "pm2 delete all"
  "pm2 kill"
  "docker compose down -v"
  "docker system prune -a"
  "docker volume prune"
  "rm -rf /Users/jojaeyong"
  "rm -rf ~/WebstormProjects"
  "rm -rf /*"
  "dropdb"
  "DROP DATABASE"
  "DROP TABLE"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qi "$pattern"; then
    echo "WARN: 위험한 운영 명령 감지: '$pattern'"
    echo "이 명령은 데이터 손실이나 서비스 중단을 유발할 수 있습니다."
    exit 2  # exit 2 = ask for confirmation
  fi
done

exit 0
