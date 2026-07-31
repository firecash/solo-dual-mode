#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
say(){ printf '%s\n' "$*"; }
die(){ say "error: $*" >&2; exit 1; }
saved(){ sed -n "s/^$1=//p" /etc/zkas-solo/solo.conf 2>/dev/null | head -1; }

OLD_ADDRESS=$(saved ZKAS_ADDRESS)
OLD_MODE=$(saved ZKAS_MODE)
OLD_KASPA_MODE=$(saved KASPA_MODE)
OLD_KASPA_PAY=$(saved KASPA_PAY_ADDRESS)
OLD_ZKAS_RPC=$(saved ZKAS_RPC)
OLD_KASPA_RPC=$(saved KASPA_RPC)
OLD_ZKAS_P2P=$(saved ZKAS_P2P)
OLD_KASPA_P2P=$(saved KASPA_P2P)
OLD_STRATUM=$(saved STRATUM_ENDPOINT)
OLD_INSTALL=$(saved INSTALL_DIR)
OLD_CONFIG=$(saved CONFIG_DIR)
OLD_DATA=$(saved DATA_DIR)
if [[ -n $OLD_ADDRESS ]]; then say "Existing configuration found in /etc/zkas-solo/solo.conf"; fi

say 'ZKas Solo Gateway setup'
say 'This wizard uses safe defaults and writes no chain data until you confirm.'
printf 'ZKas shielded payout address (zkas:...) [%s]: ' "${OLD_ADDRESS:-required}"
read -r ZKAS_ADDRESS
ZKAS_ADDRESS=${ZKAS_ADDRESS:-$OLD_ADDRESS}
[[ $ZKAS_ADDRESS == zkas:* ]] || die 'address must start with zkas:'

say ''
say 'Choose node mode:'
say '  1) Use local ZKas node + native ZKas mining (default)'
say '  2) Use local ZKas + local Kaspa node (merged mining)'
say '  3) Connect to existing ZKas/Kaspa nodes'
default_choice=1
[[ $OLD_MODE == external ]] && default_choice=3
[[ $OLD_KASPA_MODE == managed ]] && default_choice=2
printf 'Selection [%s]: ' "$default_choice"
read -r choice
choice=${choice:-$default_choice}

NODE_BIN="${ZKAS_NODE_BIN:-}"
BRIDGE_BIN="${BRIDGE_BIN:-}"
KASPA_BIN="${KASPA_NODE_BIN:-}"
if [[ -z $NODE_BIN && -x "$ROOT/../zkas-node" ]]; then NODE_BIN="$ROOT/../zkas-node"; fi
if [[ -z $BRIDGE_BIN && -x "$ROOT/../zkas-pool/bin/stratum-bridge" ]]; then BRIDGE_BIN="$ROOT/../zkas-pool/bin/stratum-bridge"; fi

args=("--zkas-address=$ZKAS_ADDRESS")
[[ -n $OLD_INSTALL ]] && args+=("--install-dir=$OLD_INSTALL")
[[ -n $OLD_CONFIG ]] && args+=("--config-dir=$OLD_CONFIG")
[[ -n $OLD_DATA ]] && args+=("--data-dir=$OLD_DATA")
[[ -n $OLD_ZKAS_P2P ]] && args+=("--zkas-p2p=$OLD_ZKAS_P2P")
[[ -n $OLD_KASPA_P2P ]] && args+=("--kaspa-p2p=$OLD_KASPA_P2P")
[[ -n $OLD_STRATUM ]] && args+=("--stratum-bind=$OLD_STRATUM")
case "$choice" in
  1)
    if [[ -n $NODE_BIN && -n $BRIDGE_BIN ]]; then
      args+=(--zkas-node=managed "--zkas-node-bin=$NODE_BIN" "--bridge-bin=$BRIDGE_BIN")
    else
      [[ -n ${ZKAS_RELEASE_MANIFEST_URL:-} && -n ${ZKAS_BRIDGE_MANIFEST_URL:-} ]] || die 'local binaries not found; set ZKAS_RELEASE_MANIFEST_URL and ZKAS_BRIDGE_MANIFEST_URL, then rerun'
      args+=(--zkas-node=download "--zkas-release-manifest=$ZKAS_RELEASE_MANIFEST_URL" "--bridge-release-manifest=$ZKAS_BRIDGE_MANIFEST_URL")
    fi
    ;;
  2)
    printf 'Kaspa payout address (kaspa:...) [%s]: ' "${OLD_KASPA_PAY:-required}"
    read -r KASPA_PAY
    KASPA_PAY=${KASPA_PAY:-$OLD_KASPA_PAY}
    [[ $KASPA_PAY == kaspa:* ]] || die 'Kaspa address must start with kaspa:'
    if [[ -n $NODE_BIN && -n $BRIDGE_BIN && -n $KASPA_BIN ]]; then
      args+=(--zkas-node=managed "--zkas-node-bin=$NODE_BIN" --kaspa-node=managed "--kaspa-node-bin=$KASPA_BIN" "--kaspa-pay-address=$KASPA_PAY" "--bridge-bin=$BRIDGE_BIN")
    else
      [[ -n ${ZKAS_RELEASE_MANIFEST_URL:-} && -n ${KASPA_RELEASE_MANIFEST_URL:-} && -n ${ZKAS_BRIDGE_MANIFEST_URL:-} ]] || die 'local binaries not found; set all three release manifest URLs, then rerun'
      args+=(--zkas-node=download "--kaspa-node=download" "--zkas-release-manifest=$ZKAS_RELEASE_MANIFEST_URL" "--kaspa-release-manifest=$KASPA_RELEASE_MANIFEST_URL" "--bridge-release-manifest=$ZKAS_BRIDGE_MANIFEST_URL" "--kaspa-pay-address=$KASPA_PAY")
    fi
    ;;
  3)
    printf 'Existing ZKas RPC [%s]: ' "${OLD_ZKAS_RPC:-127.0.0.1:16810}"
    read -r ZKAS_RPC; ZKAS_RPC=${ZKAS_RPC:-${OLD_ZKAS_RPC:-127.0.0.1:16810}}
    printf 'Use an existing Kaspa node too? [y/N]: '
    read -r use_kaspa
    args+=(--zkas-node=external "--zkas-rpc=$ZKAS_RPC")
    if [[ ${use_kaspa,,} == y || ${use_kaspa,,} == yes ]]; then
      printf 'Existing Kaspa RPC [%s]: ' "${OLD_KASPA_RPC:-127.0.0.1:16110}"
      read -r KASPA_RPC; KASPA_RPC=${KASPA_RPC:-${OLD_KASPA_RPC:-127.0.0.1:16110}}
      printf 'Kaspa payout address (kaspa:...) [%s]: ' "${OLD_KASPA_PAY:-required}"
      read -r KASPA_PAY
      KASPA_PAY=${KASPA_PAY:-$OLD_KASPA_PAY}
      [[ $KASPA_PAY == kaspa:* ]] || die 'Kaspa address must start with kaspa:'
      args+=(--kaspa-node=external "--kaspa-rpc=$KASPA_RPC" "--kaspa-pay-address=$KASPA_PAY")
    fi
    [[ -n $BRIDGE_BIN ]] || die 'bridge binary not found; set BRIDGE_BIN=/path/to/stratum-bridge'
    args+=("--bridge-bin=$BRIDGE_BIN")
    ;;
  *) die 'invalid selection' ;;
esac

say ''
printf 'Install with these settings? [Y/n]: '
read -r confirm
[[ -z $confirm || ${confirm,,} == y || ${confirm,,} == yes ]] || exit 0
exec "$ROOT/install.sh" "${args[@]}"
