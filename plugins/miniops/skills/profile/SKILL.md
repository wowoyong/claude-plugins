---
name: profile
description: Claude Code 멀티 계정 관리 — 프로필 전환, 사용량 밸런싱, 토큰 자동 갱신. "계정 전환", "프로필", "switch account", "밸런싱", "토큰 갱신" 등에 트리거.
argument-hint: "<command> [name]  (예: list, save work, switch personal, balance, keeper, status)"
---

# Claude Code 프로필 관리

**Input**: $ARGUMENTS

여러 Claude 계정을 프로필로 관리합니다. `/login` 없이 전환하고, 사용량 기반으로 자동 밸런싱합니다.

## 경로

```
~/.claude/profiles/
  ├── {name}/.credentials.json    # 저장된 인증 정보
  ├── {name}/meta.json            # 프로필 메타 (구독 타입, 저장일시, 이메일)
  ├── _previous/.credentials.json # 자동 백업
  └── .usage.json                 # 프로필별 일일 사용량 DB
```

활성 인증: `~/.claude/.credentials.json`
사용량 출처: `~/.claude/stats-cache.json` (dailyModelTokens)

## 명령어 라우팅

| 인자 | 동작 |
|------|------|
| `list` 또는 인자 없음 | 프로필 목록 + 사용량 + 토큰 상태 |
| `save <name>` | 현재 인증을 프로필로 저장 |
| `switch <name>` | 수동 전환 |
| `balance` | 사용량 가장 적은 프로필로 자동 전환 |
| `status` | 모든 프로필 토큰 만료 시간 + 오늘 사용량 |
| `keeper` | 토큰 키퍼 실행 (만료 임박 토큰 갱신) |
| `keeper setup` | 토큰 키퍼 크론 등록 |
| `delete <name>` | 프로필 삭제 |

## 핵심 기능 1: 사용량 밸런싱

`stats-cache.json`의 `dailyModelTokens`에서 오늘 사용량을 추적합니다.

```dot
digraph balance {
  rankdir=LR;
  node [shape=box];
  start [label="세션 시작"];
  check [label="프로필별\n오늘 사용량 확인"];
  compare [label="A: 30만 tokens\nB: 20만 tokens" shape=note];
  select [label="B 선택\n(사용량 적음)"];
  apply [label="credentials 교체\n→ 새 세션에서 적용"];
  start -> check -> compare -> select -> apply;
}
```

### balance 구현

```bash
# scripts/smart-select.sh 실행
bash "$(dirname "$0")/scripts/smart-select.sh"
```

스크립트 동작:
1. 모든 프로필의 `.credentials.json` 확인
2. `.usage.json`에서 프로필별 오늘 토큰 사용량 조회
3. 만료되지 않은 프로필 중 사용량 최소인 것 선택
4. 현재 프로필과 다르면 credentials 교체

**수동 전환과 다른 점**: `switch`는 이름으로 지정, `balance`는 사용량 기준 자동 선택.

### 사용량 기록

세션 종료 시 또는 `balance` 호출 시 현재 프로필의 사용량을 `.usage.json`에 기록:

```python
# stats-cache.json에서 오늘 토큰 추출
import json, datetime
stats = json.load(open('~/.claude/stats-cache.json'))
today = datetime.date.today().isoformat()
for day in stats.get('dailyModelTokens', []):
    if day['date'] == today:
        total = sum(day.get('tokensByModel', {}).values())
        # .usage.json에 프로필별로 기록
```

## 핵심 기능 2: 토큰 키퍼

모든 저장된 프로필의 토큰을 주기적으로 갱신하여 만료를 방지합니다.

### 동작 원리

```
OAuth2 Refresh Flow:
  refreshToken → POST console.anthropic.com/v1/oauth/token
               → 새 accessToken + refreshToken + expiresAt
```

현재 토큰 만료까지: 약 6시간 (확인됨). 4시간마다 갱신하면 안전.

### keeper 구현

```bash
# 모든 프로필 토큰 상태 확인 + 갱신
bash "$(dirname "$0")/scripts/token-keeper.sh"
```

### keeper setup — 크론 등록

```bash
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/scripts/token-keeper.sh"

# 기존 등록 확인
if crontab -l 2>/dev/null | grep -q "token-keeper"; then
  echo "이미 등록되어 있습니다."
  crontab -l | grep "token-keeper"
else
  # 4시간마다 실행
  (crontab -l 2>/dev/null; echo "0 */4 * * * $SCRIPT_PATH >> $HOME/.claude/profiles/.token-keeper.log 2>&1") | crontab -
  echo "크론 등록 완료: 매 4시간마다 토큰 갱신"
fi
```

주의: OAuth refresh endpoint가 변경될 수 있음. 갱신 실패 시 `/login` 필요.

## 기본 명령어

### list

```bash
echo "=== Claude Profiles ==="
echo ""

# 현재 활성 계정
python3 -c "
import json, datetime, time, os

cred = json.load(open(os.path.expanduser('~/.claude/.credentials.json')))
oauth = cred.get('claudeAiOauth', {})
exp = oauth.get('expiresAt', 0)
remaining_h = (exp - time.time() * 1000) / 1000 / 3600
status_icon = '✅' if remaining_h > 6 else ('⚠️' if remaining_h > 0 else '❌')
print(f\"Active: {oauth.get('subscriptionType','?')} ({oauth.get('rateLimitTier','?')})\")
print(f\"  Token: {status_icon} {remaining_h:.1f}h remaining\")
"

echo ""

# 저장된 프로필 + 사용량
python3 -c "
import json, os, datetime, time

profiles_dir = os.path.expanduser('~/.claude/profiles')
usage_file = os.path.join(profiles_dir, '.usage.json')
today = datetime.date.today().isoformat()

try:
    usage_db = json.load(open(usage_file))
except:
    usage_db = {}

for name in sorted(os.listdir(profiles_dir)):
    meta_path = os.path.join(profiles_dir, name, 'meta.json')
    cred_path = os.path.join(profiles_dir, name, '.credentials.json')
    if name.startswith('.') or name == '_previous' or not os.path.isfile(cred_path):
        continue

    # 메타 정보
    try:
        meta = json.load(open(meta_path))
        sub = meta.get('subscriptionType', '?')
        email = meta.get('email', '')
    except:
        sub = '?'
        email = ''

    # 토큰 상태
    try:
        cred = json.load(open(cred_path))
        exp = cred.get('claudeAiOauth', {}).get('expiresAt', 0)
        remaining_h = (exp - time.time() * 1000) / 1000 / 3600
        tok_status = '✅' if remaining_h > 6 else ('⚠️' if remaining_h > 0 else '❌')
        tok_info = f'{remaining_h:.1f}h'
    except:
        tok_status = '❓'
        tok_info = 'unknown'

    # 오늘 사용량
    today_tokens = usage_db.get(name, {}).get('daily', {}).get(today, 0)
    total_tokens = usage_db.get(name, {}).get('total', 0)

    label = f'{email} ' if email else ''
    print(f'  [{name}] {label}{sub} | Token: {tok_status} {tok_info} | Today: {today_tokens:,} tokens | Total: {total_tokens:,}')
"
```

### save \<name\>

```bash
NAME="$1"
PROFILE_DIR="$HOME/.claude/profiles/$NAME"
mkdir -p "$PROFILE_DIR"

# 현재 인증 복사
cp ~/.claude/.credentials.json "$PROFILE_DIR/.credentials.json"
chmod 600 "$PROFILE_DIR/.credentials.json"

# 메타 정보 저장 (이메일 포함)
python3 -c "
import json, datetime, subprocess
cred = json.load(open('$HOME/.claude/.credentials.json'))
oauth = cred.get('claudeAiOauth', {})

# claude auth status에서 이메일 가져오기
try:
    status = subprocess.run(['claude', 'auth', 'status', '--json'],
                          capture_output=True, text=True, timeout=5)
    auth_info = json.loads(status.stdout)
    email = auth_info.get('email', '')
except:
    email = ''

meta = {
    'subscriptionType': oauth.get('subscriptionType', 'unknown'),
    'rateLimitTier': oauth.get('rateLimitTier', 'unknown'),
    'email': email,
    'scopes': oauth.get('scopes', []),
    'savedAt': datetime.datetime.now().isoformat()
}
json.dump(meta, open('$PROFILE_DIR/meta.json', 'w'), indent=2)
print(f\"Profile '$NAME' saved ({email or oauth.get('subscriptionType','')})\")
"
```

### switch \<name\>

```bash
NAME="$1"
PROFILE_DIR="$HOME/.claude/profiles/$NAME"

if [ ! -f "$PROFILE_DIR/.credentials.json" ]; then
  echo "ERROR: Profile '$NAME' not found"
  echo "Available: $(ls ~/.claude/profiles/ 2>/dev/null | grep -v '_previous' | grep -v '^\.' | tr '\n' ' ')"
  exit 1
fi

# 토큰 만료 확인
python3 -c "
import json, time
cred = json.load(open('$PROFILE_DIR/.credentials.json'))
exp = cred.get('claudeAiOauth', {}).get('expiresAt', 0)
remaining_h = (exp - time.time() * 1000) / 1000 / 3600
if remaining_h <= 0:
    print('WARNING: 토큰 만료됨. /login 필요할 수 있습니다.')
elif remaining_h <= 2:
    print(f'WARNING: 토큰 만료 임박 ({remaining_h:.1f}h)')
" 2>/dev/null

# 현재 사용량 기록 후 백업
BACKUP_DIR="$HOME/.claude/profiles/_previous"
mkdir -p "$BACKUP_DIR"
cp ~/.claude/.credentials.json "$BACKUP_DIR/.credentials.json" 2>/dev/null || true

# 프로필 적용
cp "$PROFILE_DIR/.credentials.json" ~/.claude/.credentials.json
chmod 600 ~/.claude/.credentials.json

echo "Switched to '$NAME'"
echo "NOTE: 새 세션에서 적용됩니다."
```

### status

```bash
echo "=== Profile Status ==="
python3 -c "
import json, os, time, datetime

profiles_dir = os.path.expanduser('~/.claude/profiles')
usage_file = os.path.join(profiles_dir, '.usage.json')
today = datetime.date.today().isoformat()

try:
    usage_db = json.load(open(usage_file))
except:
    usage_db = {}

# 활성 토큰
cred = json.load(open(os.path.expanduser('~/.claude/.credentials.json')))
exp = cred.get('claudeAiOauth', {}).get('expiresAt', 0)
remaining = (exp - time.time() * 1000) / 1000 / 3600
print(f'Active token: {remaining:.1f}h remaining')
print()

# 프로필별 상세
for name in sorted(os.listdir(profiles_dir)):
    cred_path = os.path.join(profiles_dir, name, '.credentials.json')
    if name.startswith('.') or name == '_previous' or not os.path.isfile(cred_path):
        continue

    cred = json.load(open(cred_path))
    exp = cred.get('claudeAiOauth', {}).get('expiresAt', 0)
    remaining = (exp - time.time() * 1000) / 1000 / 3600

    today_tokens = usage_db.get(name, {}).get('daily', {}).get(today, 0)

    icon = '✅' if remaining > 6 else ('⚠️' if remaining > 0 else '❌')
    print(f'{icon} [{name}] Token: {remaining:.1f}h | Today: {today_tokens:,} tokens')

# 토큰 키퍼 로그 마지막 실행
log_file = os.path.join(profiles_dir, '.token-keeper.log')
if os.path.isfile(log_file):
    with open(log_file) as f:
        lines = f.readlines()
    last_run = [l for l in lines if 'Token Keeper 완료' in l]
    if last_run:
        print(f\"\nLast keeper run: {last_run[-1].strip()}\")
"
```

### delete \<name\>

```bash
NAME="$1"
if [ "$NAME" = "_previous" ]; then
  echo "ERROR: '_previous'는 자동 백업이라 삭제할 수 없습니다."
  exit 1
fi
rm -rf "$HOME/.claude/profiles/$NAME"
echo "Profile '$NAME' deleted"
```

## 초기 설정 가이드

```
# Step 1: 계정 A (현재 로그인) 저장
/profile save account-a

# Step 2: 계정 B 로그인 후 저장
# (현재 세션에서) ! claude auth login
# (새 세션에서) /profile save account-b

# Step 3: 토큰 키퍼 설정 (자동 갱신)
/profile keeper setup

# Step 4: 사용
/profile balance          → 사용량 적은 계정으로 자동 전환
/profile switch account-a → 수동 전환
/profile status           → 전체 상태 확인
```

## 안전장치

- `switch`/`balance` 시 현재 인증을 `_previous`에 자동 백업
- 토큰 만료 임박(2h 이하) 경고
- `_previous` 프로필 삭제 불가
- `.credentials.json`은 `chmod 600` 유지
- 토큰 키퍼 로그: `~/.claude/profiles/.token-keeper.log`

## 자주 하는 실수

- 전환 후 현재 세션에서 바로 적용 기대 → **새 세션 필요**
- refresh token까지 만료 → 해당 계정으로 `/login` 한번 후 다시 `save`
- mcpOAuth 키도 프로필에 포함됨 → 계정별 MCP 인증도 같이 전환
- stats-cache.json은 계정 구분 없이 누적 → .usage.json이 프로필별 추적 담당
