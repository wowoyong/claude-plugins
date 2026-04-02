# 프로젝트 타입별 검증 패턴

## Node/TypeScript

### 감지 조건
- `tsconfig.json` 존재

### 명령어

| 검증 | 명령어 | 자동수정 |
|------|--------|----------|
| lint | `npx eslint .` 또는 `npx biome check .` | `npx eslint . --fix` / `npx biome check . --write` |
| type | `npx tsc --noEmit` | — (수동 수정) |
| test | `CI=true npx vitest run` 또는 `CI=true npx jest` | — |
| build | `npm run build` | — |
| format | `npx prettier --check .` | `npx prettier --write .` |

### 테스트 프레임워크 감지

```bash
# package.json에서 확인
grep -E '"(vitest|jest|mocha|ava)"' package.json
# 설정 파일 존재 확인
ls vitest.config.* jest.config.* .mocharc.* 2>/dev/null
```

### 주의사항
- `vitest`는 기본 watch 모드 → `vitest run` 필수
- `jest`도 watch 가능 → `CI=true` 환경변수로 비활성화
- monorepo에서 `npx turbo run lint test` 사용 가능

---

## Node/JavaScript (TypeScript 없음)

### 감지 조건
- `package.json` 존재, `tsconfig.json` 없음

### 명령어

| 검증 | 명령어 | 자동수정 |
|------|--------|----------|
| lint | `npx eslint .` | `npx eslint . --fix` |
| test | `CI=true npm test` | — |

---

## Python

### 감지 조건
- `pyproject.toml` 또는 `requirements.txt` 존재

### 명령어

| 검증 | 명령어 | 자동수정 |
|------|--------|----------|
| lint | `ruff check .` 또는 `flake8 .` | `ruff check . --fix` |
| type | `mypy .` 또는 `pyright .` | — |
| test | `pytest -x --tb=short` | — |
| format | `ruff format --check .` | `ruff format .` |
| security | `pip audit` (설치되어 있으면) | — |

### 가상환경 감지

```bash
# 프로젝트 내 venv 확인
ls .venv/bin/python venv/bin/python 2>/dev/null
# poetry 확인
ls poetry.lock 2>/dev/null && echo "poetry run 접두어 사용"
```

---

## Flutter/Dart

### 감지 조건
- `pubspec.yaml` 존재

### 명령어

| 검증 | 명령어 | 자동수정 |
|------|--------|----------|
| lint | `flutter analyze` | — |
| test | `flutter test` | — |
| format | `dart format --set-exit-if-changed .` | `dart format .` |
| build | `flutter build apk --debug` (Android) | — |

### 주의사항
- `flutter test`는 전체 실행이 느릴 수 있음 → 변경 파일 관련만 실행
- iOS 빌드는 Mac 필수, CI에서 확인

---

## Swift/iOS

### 감지 조건
- `*.xcodeproj` 또는 `Package.swift` 존재

### 명령어

| 검증 | 명령어 | 자동수정 |
|------|--------|----------|
| lint | `swiftlint lint` | `swiftlint lint --fix` |
| test | `xcodebuild test -scheme ... -destination 'platform=iOS Simulator,...'` | — |
| build | `xcodebuild build -scheme ...` | — |

---

## Go

### 감지 조건
- `go.mod` 존재

### 명령어

| 검증 | 명령어 | 자동수정 |
|------|--------|----------|
| lint | `golangci-lint run` | `golangci-lint run --fix` |
| type/build | `go build ./...` | — |
| test | `go test ./...` | — |
| format | `gofmt -l .` | `gofmt -w .` |
| vet | `go vet ./...` | — |

---

## 공통: 보안 패턴

### 민감 정보 탐지 패턴

```regex
# API 키/시크릿 하드코딩
(?:api[_-]?key|secret[_-]?key|password|token|auth)\s*[:=]\s*['"][A-Za-z0-9+/=_-]{16,}['"]

# AWS 키
(?:AKIA|ASIA)[A-Z0-9]{16}

# 개인키
-----BEGIN (?:RSA |EC )?PRIVATE KEY-----

# JWT 토큰
eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+
```

### .gitignore 필수 항목

| 타입 | 필수 무시 항목 |
|------|---------------|
| 공통 | `.env`, `.env.local`, `.DS_Store`, `*.log` |
| Node | `node_modules/`, `dist/`, `.next/`, `.nuxt/` |
| Python | `__pycache__/`, `.venv/`, `*.pyc`, `.mypy_cache/` |
| Flutter | `.dart_tool/`, `build/`, `.flutter-plugins` |
| iOS | `Pods/`, `*.xcworkspace/xcuserdata/` |

---

## 공통: 크로스 검증 패턴

### Import 정합성

```bash
# 삭제된 파일을 import하는 코드 찾기
for deleted in $(git diff --cached --name-only --diff-filter=D); do
  basename=$(basename "$deleted" | sed 's/\.[^.]*$//')
  grep -rl "$basename" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.py" . 2>/dev/null
done
```

### 환경 변수 동기화

```bash
# 코드에서 사용하는 환경변수 vs .env.example
grep -roh 'process\.env\.\w\+' src/ | sort -u > /tmp/used_env
grep -v '^#' .env.example 2>/dev/null | cut -d= -f1 | sort -u > /tmp/defined_env
diff /tmp/used_env /tmp/defined_env
```

주의: `/tmp` 대신 `.claude/tmp/` 사용할 것 (보안 정책).
