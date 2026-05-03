#!/usr/bin/env bash
# End-to-end tests for anvil-persistent.
#
# Test 1: graceful shutdown — chain state survives docker stop/start via --state flush.
# Test 2: --state-interval — chain state survives a SIGKILL because anvil's native
#         periodic dump wrote it to disk before the kill.
#
# Requires: docker, docker compose v2.24+, jq, curl.
# Uses host port 18545 (not 8545) so it does not conflict with a running prod container.
set -euo pipefail

PROJECT=anvil-persist-test
CONTAINER=anvil-test
COMPOSE=(docker compose -p "$PROJECT" -f docker-compose.yml -f docker-compose.test.yml)
RPC=http://localhost:18545

SENDER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
ONE_ETH_HEX=0xde0b6b3a7640000

cleanup() {
  echo "==> Cleanup"
  "${COMPOSE[@]}" down -v --rmi local --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

rpc() {
  local method=$1 params=${2:-[]}
  curl -fsS -X POST "$RPC" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}"
}

wait_for_rpc() {
  for i in $(seq 1 60); do
    if rpc web3_clientVersion >/dev/null 2>&1; then
      echo "    RPC up after ${i}s"
      return
    fi
    sleep 1
  done
  echo "FAIL: RPC never came up" >&2
  "${COMPOSE[@]}" logs >&2
  exit 1
}

wait_for_state_file() {
  for i in $(seq 1 30); do
    if docker exec "$CONTAINER" test -s /data/anvil-state.json 2>/dev/null; then
      echo "    state file written after ${i}s"
      return
    fi
    sleep 1
  done
  echo "FAIL: state file never appeared in /data" >&2
  "${COMPOSE[@]}" logs >&2
  exit 1
}

balance_of() { rpc eth_getBalance "[\"$1\",\"latest\"]" | jq -r .result; }
block_number() { rpc eth_blockNumber | jq -r .result; }
send_one_eth() {
  rpc eth_sendTransaction \
    "[{\"from\":\"$SENDER\",\"to\":\"$RECIPIENT\",\"value\":\"$ONE_ETH_HEX\"}]" >/dev/null
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: expected '$2', got '$1'" >&2
    exit 1
  fi
}

reset_env() {
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}

banner() {
  echo
  echo "============================================================"
  echo "TEST: $1"
  echo "============================================================"
}

# ---------- Test 1: graceful shutdown ----------
test_graceful_shutdown() {
  banner "graceful shutdown persists state via --state flag"
  reset_env
  "${COMPOSE[@]}" up -d
  wait_for_rpc

  send_one_eth
  local bal_before block_before
  bal_before=$(balance_of "$RECIPIENT")
  block_before=$(block_number)
  echo "    pre-stop  balance=$bal_before block=$block_before"

  echo "==> Stop (SIGINT, triggers --state flush)"
  "${COMPOSE[@]}" stop
  echo "==> Start (loads state file)"
  "${COMPOSE[@]}" start
  wait_for_rpc

  local bal_after block_after
  bal_after=$(balance_of "$RECIPIENT")
  block_after=$(block_number)
  echo "    post-stop balance=$bal_after block=$block_after"

  assert_eq "$bal_after"   "$bal_before"
  assert_eq "$block_after" "$block_before"
  echo "PASS"
}

# ---------- Test 2: --state-interval survives SIGKILL ----------
test_state_interval_survives_kill() {
  banner "--state-interval persists state across SIGKILL (hard crash)"
  reset_env
  STATE_INTERVAL=5 "${COMPOSE[@]}" up -d
  wait_for_rpc

  send_one_eth
  local bal_before block_before
  bal_before=$(balance_of "$RECIPIENT")
  block_before=$(block_number)
  echo "    pre-kill  balance=$bal_before block=$block_before"

  echo "==> Wait for --state-interval to write state file (interval=5s)"
  wait_for_state_file

  echo "==> SIGKILL container (no graceful shutdown, --state final flush skipped)"
  docker kill "$CONTAINER" >/dev/null

  echo "==> Start (only the periodic dump's last write can save us now)"
  "${COMPOSE[@]}" start
  wait_for_rpc

  local bal_after block_after
  bal_after=$(balance_of "$RECIPIENT")
  block_after=$(block_number)
  echo "    post-kill balance=$bal_after block=$block_after"

  assert_eq "$bal_after"   "$bal_before"
  assert_eq "$block_after" "$block_before"
  echo "PASS"
}

echo "==> Build"
"${COMPOSE[@]}" build

test_graceful_shutdown
test_state_interval_survives_kill

echo
echo "ALL TESTS PASSED"
