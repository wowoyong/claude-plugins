#!/bin/bash
# token-keeper.sh — 모든 프로필의 OAuth 토큰을 자동 갱신
# 크론으로 주기적 실행: 매 4시간마다
#
# OAuth refresh flow:
#   refreshToken → POST /oauth/token → 새 accessToken + refreshToken
#
# Usage: ./token-keeper.sh [--check-only] [--profile <name>]

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PROFILES_DIR="$CLAUDE_DIR/profiles"
LOG_FILE="$PROFILES_DIR/.token-keeper.log"
CHECK_ONLY=false
TARGET_PROFILE=""

for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=true ;;
    --profile) shift; TARGET_PROFILE="$1" 2>/dev/null || true ;;
  esac
done

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- 토큰 만료 확인 ---

check_token_expiry() {
  local cred_file="$1"
  python3 -c "
import json, time, datetime

cred = json.load(open('$cred_file'))
oauth = cred.get('claudeAiOauth', {})
expires_ms = oauth.get('expiresAt', 0)
now_ms = time.time() * 1000
remaining_hours = (expires_ms - now_ms) / 1000 / 3600

status = 'ok'
if remaining_hours <= 0:
    status = 'expired'
elif remaining_hours <= 6:
    status = 'expiring_soon'

exp_dt = datetime.datetime.fromtimestamp(expires_ms / 1000)
print(f'{status}|{remaining_hours:.1f}|{exp_dt.isoformat()}')
" 2>/dev/null
}

# --- OAuth 토큰 갱신 ---
# Claude Code는 console.anthropic.com OAuth를 사용
# refresh_token으로 새 access_token을 받는 표준 OAuth2 flow

refresh_token() {
  local cred_file="$1"
  local profile_name="$2"

  python3 << 'PYEOF'
import json, urllib.request, urllib.parse, time, sys, os

cred_file = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('CRED_FILE', '')

try:
    cred = json.load(open(cred_file))
    oauth = cred.get('claudeAiOauth', {})
    refresh_tok = oauth.get('refreshToken', '')

    if not refresh_tok:
        print('ERROR: no refresh token')
        sys.exit(1)

    # Anthropic OAuth token endpoint
    # Claude Code uses console.anthropic.com for OAuth
    token_url = 'https://console.anthropic.com/v1/oauth/token'

    data = urllib.parse.urlencode({
        'grant_type': 'refresh_token',
        'refresh_token': refresh_tok,
    }).encode()

    req = urllib.request.Request(
        token_url,
        data=data,
        headers={
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'claude-code-token-keeper/1.0',
        },
        method='POST'
    )

    resp = urllib.request.urlopen(req, timeout=30)
    result = json.loads(resp.read())

    # 새 토큰 업데이트
    if 'access_token' in result:
        oauth['accessToken'] = result['access_token']
    if 'refresh_token' in result:
        oauth['refreshToken'] = result['refresh_token']
    if 'expires_in' in result:
        oauth['expiresAt'] = int(time.time() * 1000) + (result['expires_in'] * 1000)
    elif 'expires_at' in result:
        oauth['expiresAt'] = result['expires_at']

    cred['claudeAiOauth'] = oauth
    json.dump(cred, open(cred_file, 'w'), indent=2)
    os.chmod(cred_file, 0o600)

    print('REFRESHED')

except urllib.error.HTTPError as e:
    body = e.read().decode() if e.fp else ''
    print(f'HTTP_ERROR:{e.code}:{body[:200]}')
    sys.exit(1)
except Exception as e:
    print(f'ERROR:{e}')
    sys.exit(1)
PYEOF
}

# --- 프로필별 처리 ---

process_profile() {
  local name="$1"
  local cred_file="$PROFILES_DIR/$name/.credentials.json"

  if [ ! -f "$cred_file" ]; then
    return
  fi

  local result
  result=$(check_token_expiry "$cred_file")
  local status=$(echo "$result" | cut -d'|' -f1)
  local hours=$(echo "$result" | cut -d'|' -f2)
  local expiry=$(echo "$result" | cut -d'|' -f3)

  case "$status" in
    ok)
      log "[$name] OK — ${hours}h remaining (expires $expiry)"
      ;;
    expiring_soon)
      log "[$name] EXPIRING SOON — ${hours}h remaining"
      if [ "$CHECK_ONLY" = false ]; then
        log "[$name] Refreshing token..."
        local refresh_result
        refresh_result=$(CRED_FILE="$cred_file" python3 << 'PYEOF' 2>&1 || true
import json, urllib.request, urllib.parse, time, sys, os

cred_file = os.environ.get('CRED_FILE', '')
cred = json.load(open(cred_file))
oauth = cred.get('claudeAiOauth', {})
refresh_tok = oauth.get('refreshToken', '')

if not refresh_tok:
    print('ERROR: no refresh token')
    sys.exit(1)

token_url = 'https://console.anthropic.com/v1/oauth/token'
data = urllib.parse.urlencode({
    'grant_type': 'refresh_token',
    'refresh_token': refresh_tok,
}).encode()

req = urllib.request.Request(token_url, data=data, headers={
    'Content-Type': 'application/x-www-form-urlencoded',
    'User-Agent': 'claude-code-token-keeper/1.0',
}, method='POST')

try:
    resp = urllib.request.urlopen(req, timeout=30)
    result = json.loads(resp.read())
    if 'access_token' in result:
        oauth['accessToken'] = result['access_token']
    if 'refresh_token' in result:
        oauth['refreshToken'] = result['refresh_token']
    if 'expires_in' in result:
        oauth['expiresAt'] = int(time.time() * 1000) + (result['expires_in'] * 1000)
    cred['claudeAiOauth'] = oauth
    json.dump(cred, open(cred_file, 'w'), indent=2)
    os.chmod(cred_file, 0o600)
    print('REFRESHED')
except urllib.error.HTTPError as e:
    print(f'HTTP_ERROR:{e.code}')
except Exception as e:
    print(f'ERROR:{e}')
PYEOF
)
        log "[$name] Result: $refresh_result"

        # 갱신 성공 시, 이 프로필이 현재 활성이면 active credentials도 업데이트
        if [ "$refresh_result" = "REFRESHED" ]; then
          update_active_if_current "$name" "$cred_file"
        fi
      fi
      ;;
    expired)
      log "[$name] EXPIRED — /login 필요"
      ;;
  esac
}

# 현재 활성 프로필이면 active credentials도 같이 업데이트
update_active_if_current() {
  local profile_name="$1"
  local profile_cred="$2"
  local active_cred="$CLAUDE_DIR/.credentials.json"

  python3 -c "
import json

active = json.load(open('$active_cred'))
profile = json.load(open('$profile_cred'))

active_rt = active.get('claudeAiOauth', {}).get('refreshToken', 'a')
profile_rt_old = profile.get('claudeAiOauth', {}).get('refreshToken', 'b')

# refreshToken이 갱신되었을 수 있으므로, subscriptionType + scopes로 비교
active_sub = active.get('claudeAiOauth', {}).get('subscriptionType', '')
profile_sub = profile.get('claudeAiOauth', {}).get('subscriptionType', '')
active_tier = active.get('claudeAiOauth', {}).get('rateLimitTier', '')
profile_tier = profile.get('claudeAiOauth', {}).get('rateLimitTier', '')

if active_sub == profile_sub and active_tier == profile_tier:
    print('MATCH')
else:
    print('DIFFERENT')
" 2>/dev/null | grep -q "MATCH" && {
    cp "$profile_cred" "$active_cred"
    chmod 600 "$active_cred"
    log "[$profile_name] Active credentials도 갱신됨"
  }
}

# --- 메인 ---

main() {
  mkdir -p "$PROFILES_DIR"

  log "=== Token Keeper 실행 ==="

  # 활성 credentials도 체크
  if [ -f "$CLAUDE_DIR/.credentials.json" ]; then
    log "[active] 현재 활성 토큰 확인..."
    local result
    result=$(check_token_expiry "$CLAUDE_DIR/.credentials.json")
    local status=$(echo "$result" | cut -d'|' -f1)
    local hours=$(echo "$result" | cut -d'|' -f2)
    log "[active] Status: $status (${hours}h remaining)"
  fi

  # 프로필별 처리
  if [ -n "$TARGET_PROFILE" ]; then
    process_profile "$TARGET_PROFILE"
  else
    for dir in "$PROFILES_DIR"/*/; do
      local name
      name=$(basename "$dir")
      [ "$name" = "_previous" ] && continue
      process_profile "$name"
    done
  fi

  log "=== Token Keeper 완료 ==="
}

main
