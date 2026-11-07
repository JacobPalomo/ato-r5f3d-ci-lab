#!/usr/bin/env bash
# Run ONLY on GitHub-hosted Ubuntu ARM64 runner. CI smoke; no production data.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p reports
PHASE=INIT
RAILS_EXECUTED=false
SCHEMA_READY=false
IMAGE_MATCHED=false
CLEANUP_OK=false
EXPECTED_IMAGE='sha256:efb1f9fa48a922e74ce7960d44830d7d4d61764bb2295f9bca9d1470cce18275'
COMPOSE=(docker compose -p ato-r5f3d-ci -f docker-compose.r5f3d.yaml)
export R5F3D_SECRET_KEY_BASE="$(python3 -c 'import secrets; print(secrets.token_hex(64))')"
export R5F3F_INTERNAL_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

finish() {
  local exit_code="$?"
  trap - EXIT
  local cleanup_code=0
  if [ "$PHASE" != 'INIT' ]; then
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || cleanup_code=1
  fi
  [ "$cleanup_code" -eq 0 ] && CLEANUP_OK=true
  R5F3D_EXIT="$exit_code" R5F3D_PHASE="$PHASE" R5F3D_RAILS="$RAILS_EXECUTED" \
    R5F3D_SCHEMA="$SCHEMA_READY" R5F3D_IMAGE="$IMAGE_MATCHED" \
    R5F3D_CLEANUP="$CLEANUP_OK" \
    python3 scripts/report_r5f3d.py --output reports/ato-r5f3d-result.json || true
  if [ "$cleanup_code" -ne 0 ]; then
    echo 'FAIL: cleanup of isolated CI containers did not complete' >&2
    [ "$exit_code" -eq 0 ] && exit_code=90
  fi
  exit "$exit_code"
}
trap finish EXIT

# Fail closed against accidentally running on a user's Mac or another host.
if [[ "${GITHUB_ACTIONS:-}" != true || "${CI:-}" != true || "${R5F3D_JOB:-}" != true || "${RUNNER_OS:-}" != Linux || "${RUNNER_ARCH:-}" != ARM64 || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "${GITHUB_WORKSPACE:-}" != "$ROOT" ]]; then
  echo 'REFUSED: R5F-3D runs only on the selected GitHub Actions ARM64 runner.' >&2
  exit 10
fi

mem_bytes=$(awk '/^MemTotal:/ {printf "%.0f", $2 * 1024}' /proc/meminfo)
free_kb=$(df -Pk "$ROOT" | awk 'NR==2{print $4}')
echo "R5F-3D CI capacity: RAM=$((mem_bytes / 1024 / 1024)) MiB, free_disk=$((free_kb / 1024)) MiB"
if (( mem_bytes < 6 * 1024 * 1024 * 1024 || free_kb < 10 * 1024 * 1024 )); then
  echo 'BLOCKED_CAPACITY: runner below 6 GiB RAM or 10 GiB free disk before pull.' >&2
  exit 11
fi

# Refuse to claim or clean up an already occupied Compose project.
if [ -n "$(docker ps -a --filter label=com.docker.compose.project=ato-r5f3d-ci --format '{{.ID}}')" ]; then
  echo 'REFUSED: pre-existing ato-r5f3d-ci container found on runner.' >&2
  exit 13
fi

# Never contact the real ATO/Chatwoot gateway. Only public image registry pulls.
PHASE=IMAGE_PULL
docker pull --quiet chatwoot/chatwoot:v4.19.0
IMAGE_ID="$(docker image inspect --format '{{.Id}}' chatwoot/chatwoot:v4.19.0)"
if [ "$IMAGE_ID" != "$EXPECTED_IMAGE" ]; then
  echo 'REFUSED: Chatwoot image ID differs from R5F-1 verified ARM64 image.' >&2
  exit 12
fi
IMAGE_MATCHED=true
PHASE=IMAGE_VERIFIED

docker pull --quiet pgvector/pgvector:pg16
docker pull --quiet redis:7-alpine
PHASE=STARTING_ISOLATED_SERVICES
"${COMPOSE[@]}" up -d --wait postgres redis

# First install the schema in a fresh, synthetic database. Rails runner can eager-load
# InstallationConfig before the installation_configs table exists (original R5F-3D failure).
# The image may lack test gems; this is only a production Rails smoke, NOT RSpec.
PHASE=RAILS_DB_SETUP
"${COMPOSE[@]}" run --rm --no-deps rails bundle exec rails db:chatwoot_prepare

# Fail closed: the prepare task returning zero does NOT by itself prove tables exist.
# This SELECT runs ONLY against the disposable database inside the isolated CI project.
schema_present="$("${COMPOSE[@]}" exec -T postgres \
  psql -XAt -v ON_ERROR_STOP=1 -U r5f3d_test_only -d chatwoot_production \
  -c "SELECT to_regclass('public.installation_configs') IS NOT NULL AND to_regclass('public.messages') IS NOT NULL AND to_regclass('public.conversations') IS NOT NULL AND to_regclass('public.accounts') IS NOT NULL")"
if [ "$schema_present" != 't' ]; then
  echo 'SCHEMA_INCOMPLETE: Chatwoot required tables not present after db:chatwoot_prepare' >&2
  exit 31
fi
SCHEMA_READY=true

PHASE=RAILS_BOOT
"${COMPOSE[@]}" run --rm --no-deps rails bundle exec rails runner 'puts "R5F3D_RAILS_BOOT_OK=#{Rails.version}"'
RAILS_EXECUTED=true

PHASE=RAILS_SMOKE
"${COMPOSE[@]}" run --rm --no-deps rails bundle exec rails runner /tmp/r5f3d_smoke.rb
# R5F-3E opt-in: real Chatwoot synthetic PRIVATE notes, no provider or Sidekiq.
if [[ "${R5F3E_ENABLED:-false}" == "true" ]]; then
  PHASE=R5F3E_REAL_MESSAGE_WRITE
  # Rails writes synthetic messages; emit verdict on stdout. The host owns reports/.
  R5F3E_LOG="$(mktemp "$ROOT/reports/.r5f3e-output.XXXXXXXX")"
  if ! "${COMPOSE[@]}" run --rm --no-deps rails bundle exec rails runner /tmp/r5f3e_write_test.rb 2>&1 | tee "$R5F3E_LOG"; then
    rm -f "$R5F3E_LOG"
    echo 'FAIL R5F-3E: Rails model write or assertions failed' >&2
    exit 52
  fi
  if ! python3 scripts/extract_r5f3e_report.py --input "$R5F3E_LOG" --output reports/ato-r5f3e-result.json; then
    rm -f "$R5F3E_LOG"
    echo 'FAIL R5F-3E: missing or invalid functional evidence' >&2
    exit 53
  fi
  rm -f "$R5F3E_LOG"
fi
# R5F-3F: Rails HTTP contract, synthetic private notes only.
# Runs only on GitHub-hosted ARM64 with Docker compose isolated:true.
if [[ "${R5F3F_ENABLED:-false}" == "true" ]]; then
  PHASE=R5F3F_HTTP_CONTRACT
  R5F3F_LOG="$(mktemp "$ROOT/reports/.r5f3f-output.XXXXXXXX")"
  if ! "${COMPOSE[@]}" run --rm --no-deps rails bundle exec rails runner /tmp/r5f3f_http_contract.rb 2>&1 | tee "$R5F3F_LOG"; then
    rm -f "$R5F3F_LOG"
    echo 'FAIL R5F-3F: Rails HTTP contract assertions failed' >&2
    exit 62
  fi
  if ! python3 scripts/extract_r5f3f_report.py --input "$R5F3F_LOG" --output reports/ato-r5f3f-result.json; then
    rm -f "$R5F3F_LOG"
    echo 'FAIL R5F-3F: invalid or absent HTTP verdict' >&2
    exit 63
  fi
  rm -f "$R5F3F_LOG"
fi
PHASE=SMOKE_PASS
printf '\nPASS R5F-3D RAILS RUNTIME SMOKE (not an idempotency/fencing certification)\n'
