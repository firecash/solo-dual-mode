#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${ZKAS_SOLO_CONFIG_DIR:-/etc/zkas-solo}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[[ -f "$SCRIPT_DIR/healthcheck.env" ]] && . "$SCRIPT_DIR/healthcheck.env"
[[ -f "$CONFIG_DIR/healthcheck.env" ]] && . "$CONFIG_DIR/healthcheck.env"
ZKAS_RPC_PORT="${ZKAS_RPC_PORT:-16810}"
ZKAS_P2P_PORT="${ZKAS_P2P_PORT:-16811}"
STRATUM_PORT="${STRATUM_PORT:-5555}"
HEALTH_PORT="${HEALTH_PORT:-18080}"
echo "== services =="
systemctl is-active --quiet zkas-solo-node && echo "zkas node: active" || echo "zkas node: NOT active"
systemctl is-active --quiet zkas-solo-bridge && echo "bridge: active" || echo "bridge: NOT active"
echo "== listeners =="
ss -ltn | grep -E ":(${ZKAS_RPC_PORT}|${ZKAS_P2P_PORT}|${STRATUM_PORT})\b" || true
echo "== ZKas RPC =="
if command -v curl >/dev/null 2>&1; then
  curl -fsS --max-time 3 "http://127.0.0.1:${ZKAS_RPC_PORT}/" >/dev/null 2>&1 && echo "RPC reachable" || echo "RPC probe unavailable (gRPC/wRPC may still be healthy)"
fi
echo "== bridge health =="
curl -fsS --max-time 3 "http://127.0.0.1:${HEALTH_PORT}/health" 2>/dev/null || true
