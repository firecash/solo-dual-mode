#!/usr/bin/env bash
set -euo pipefail

PREFIX=/usr/local/lib/zkas-solo
ETC=/etc/zkas-solo
DATA=/var/lib/zkas-solo
NODE_BIN=""
BRIDGE_BIN=""
KASPA_BIN=""
ZKAS_MODE="existing"
KASPA_MODE="disabled"
ZKAS_RPC="127.0.0.1:16810"
KASPA_RPC="127.0.0.1:16110"
ZKAS_P2P="0.0.0.0:16811"
KASPA_P2P="0.0.0.0:16111"
ZKAS_MANIFEST="${ZKAS_RELEASE_MANIFEST_URL:-}"
KASPA_MANIFEST="${KASPA_RELEASE_MANIFEST_URL:-}"
BRIDGE_MANIFEST="${ZKAS_BRIDGE_MANIFEST_URL:-}"
ZKAS_ADDRESS=""
KASPA_PAY=""
P2P_PEERS=""
STRATUM_BIND="0.0.0.0"
NO_START=false

die(){ echo "error: $*" >&2; exit 1; }
usage(){ sed -n '1,100p' "$0"; exit 0; }
for arg in "$@"; do
  case "$arg" in
    --zkas-node=download) ZKAS_MODE=managed ;;
    --zkas-node=*) ZKAS_MODE=${arg#*=} ;;
    --kaspa-node=download) KASPA_MODE=managed ;;
    --kaspa-node=*) KASPA_MODE=${arg#*=} ;;
    --zkas-rpc=*) ZKAS_RPC=${arg#*=} ;;
    --kaspa-rpc=*) KASPA_RPC=${arg#*=} ;;
    --zkas-p2p=*) ZKAS_P2P=${arg#*=} ;;
    --kaspa-p2p=*) KASPA_P2P=${arg#*=} ;;
    --zkas-release-manifest=*) ZKAS_MANIFEST=${arg#*=} ;;
    --kaspa-release-manifest=*) KASPA_MANIFEST=${arg#*=} ;;
    --bridge-release-manifest=*) BRIDGE_MANIFEST=${arg#*=} ;;
    --zkas-node-bin=*) NODE_BIN=${arg#*=} ;;
    --bridge-bin=*) BRIDGE_BIN=${arg#*=} ;;
    --kaspa-node-bin=*) KASPA_BIN=${arg#*=} ;;
    --zkas-address=*) ZKAS_ADDRESS=${arg#*=} ;;
    --kaspa-pay-address=*) KASPA_PAY=${arg#*=} ;;
    --p2p-peer=*) P2P_PEERS="${P2P_PEERS} ${arg#*=}" ;;
    --stratum-bind=*) STRATUM_BIND=${arg#*=} ;;
    --install-dir=*) PREFIX=${arg#*=} ;;
    --config-dir=*) ETC=${arg#*=} ;;
    --data-dir=*) DATA=${arg#*=} ;;
    --no-start) NO_START=true ;;
    --help|-h) usage ;;
    *) die "unknown option: $arg" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "run as root (sudo ./install.sh ...)"
command -v systemctl >/dev/null || die "systemd is required"
[[ $ZKAS_ADDRESS == zkas:* ]] || die "--zkas-address must be a zkas: shielded address"
[[ $PREFIX == /* && $ETC == /* && $DATA == /* ]] || die "install/config/data paths must be absolute"
[[ $PREFIX != *' '* && $ETC != *' '* && $DATA != *' '* ]] || die "Linux paths may not contain spaces"
[[ $ZKAS_MODE == managed || $ZKAS_MODE == existing ]] || die "--zkas-node must be managed or existing"
[[ $KASPA_MODE == managed || $KASPA_MODE == existing || $KASPA_MODE == disabled ]] || die "--kaspa-node must be managed, existing, or disabled"
if [[ $ZKAS_MODE == managed && -n $NODE_BIN && ! -x $NODE_BIN ]]; then die "--zkas-node-bin must point to an executable"; fi
if [[ -z $BRIDGE_BIN && -z $BRIDGE_MANIFEST ]]; then die "provide --bridge-bin or --bridge-release-manifest"; fi
if [[ -n $KASPA_BIN && ! -x $KASPA_BIN ]]; then die "--kaspa-node-bin is not executable"; fi
if [[ -n $KASPA_PAY && $KASPA_PAY != kaspa:* ]]; then die "--kaspa-pay-address must be kaspa:"; fi
if [[ $KASPA_MODE != disabled && -z $KASPA_PAY ]]; then die "Kaspa mode requires --kaspa-pay-address"; fi
if [[ -n $KASPA_PAY && $KASPA_MODE == disabled ]]; then die "Kaspa payout supplied while Kaspa is disabled"; fi
if [[ $KASPA_MODE == managed && -n $KASPA_BIN && ! -x $KASPA_BIN ]]; then die "--kaspa-node-bin must point to an executable"; fi
if [[ $ZKAS_MODE == managed && -z $NODE_BIN && -z $ZKAS_MANIFEST ]]; then die "managed ZKas mode needs --zkas-node-bin or --zkas-release-manifest"; fi
if [[ $KASPA_MODE == managed && -z $KASPA_BIN && -z $KASPA_MANIFEST ]]; then die "managed Kaspa mode needs --kaspa-node-bin or --kaspa-release-manifest"; fi
command -v curl >/dev/null || die "curl is required for release downloads"
command -v python3 >/dev/null || die "python3 is required to parse release manifests"
command -v ss >/dev/null || die "iproute2/ss is required for port conflict checks"

port_in_use() { ss -H -ltn 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {found=1} END{exit !found}'; }
port_from_addr() { printf '%s' "$1" | awk -F: '{print $NF}'; }
host_from_addr() { printf '%s' "$1" | sed 's/:\[[^]]*\]$//' | sed 's/:[^:]*$//'; }
if [[ $STRATUM_BIND =~ :[0-9]+$ ]]; then STRATUM_ENDPOINT=$STRATUM_BIND; else STRATUM_ENDPOINT="${STRATUM_BIND}:5555"; fi
if [[ $ZKAS_MODE == managed && $(host_from_addr "$ZKAS_RPC") != 127.0.0.1 ]]; then die "managed ZKas RPC must bind to 127.0.0.1"; fi
if [[ $KASPA_MODE == managed && $(host_from_addr "$KASPA_RPC") != 127.0.0.1 ]]; then die "managed Kaspa RPC must bind to 127.0.0.1"; fi
if [[ $ZKAS_MODE == managed ]]; then
  zport=$(port_from_addr "$ZKAS_RPC"); port_in_use "$zport" && die "ZKas RPC port $zport is already listening; choose --zkas-rpc or external mode"
fi
if [[ $KASPA_MODE == managed ]]; then
  kport=$(port_from_addr "$KASPA_RPC"); port_in_use "$kport" && die "Kaspa RPC port $kport is already listening; choose --kaspa-rpc or external mode"
fi
sport=$(port_from_addr "$STRATUM_ENDPOINT"); port_in_use "$sport" && die "Stratum port $sport is already listening; choose --stratum-bind"

download_asset() {
  local manifest=$1 name=$2 dest=$3 tmp url sha platform
  tmp=$(mktemp)
  curl -fsSL --retry 3 "$manifest" -o "$tmp" || die "failed to fetch release manifest: $manifest"
  platform=$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)
  read -r url sha < <(python3 - "$tmp" "$platform" "$name" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); key=sys.argv[2]; name=sys.argv[3]
a=(d.get('assets') or {}).get(key) or (d.get('platforms') or {}).get(key)
if isinstance(a,dict) and name in a: a=a[name]
if not isinstance(a,dict) or not a.get('url') or not a.get('sha256'):
 raise SystemExit('manifest lacks '+key+'/'+name+' url+sha256')
print(a['url'],a['sha256'])
PY
  ) || die "invalid release manifest"
  curl -fsSL --retry 3 "$url" -o "$dest" || die "failed to download $name"
  echo "$sha  $dest" | sha256sum -c - || die "checksum mismatch for $name"
  rm -f "$tmp"
}
PEER_ARGS=""
for peer in $P2P_PEERS; do
  [[ $peer =~ ^[A-Za-z0-9_.:-]+$ ]] || die "invalid --p2p-peer value: $peer"
  PEER_ARGS+=" --addpeer=$peer"
done

install -d -m 0755 "$PREFIX" "$ETC" "$DATA/logs"
if [[ -n "$(find "$DATA" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" && ! -f "$DATA/.zkas-solo-owned" ]]; then
  die "data directory is non-empty and not owned by this installer: $DATA"
fi
touch "$DATA/.zkas-solo-owned"
if [[ $ZKAS_MODE == managed ]]; then
  if [[ -n $NODE_BIN ]]; then install -m 0755 "$NODE_BIN" "$PREFIX/zkas-node"; else download_asset "$ZKAS_MANIFEST" zkas-node "$PREFIX/zkas-node"; chmod 0755 "$PREFIX/zkas-node"; fi
  install -d -m 0755 "$DATA/zkas-data"
fi
if [[ -n $BRIDGE_BIN ]]; then install -m 0755 "$BRIDGE_BIN" "$PREFIX/stratum-bridge"; else download_asset "$BRIDGE_MANIFEST" stratum-bridge "$PREFIX/stratum-bridge"; chmod 0755 "$PREFIX/stratum-bridge"; fi
if [[ $KASPA_MODE == managed ]]; then
  if [[ -n $KASPA_BIN ]]; then install -m 0755 "$KASPA_BIN" "$PREFIX/kaspad"; else download_asset "$KASPA_MANIFEST" kaspad "$PREFIX/kaspad"; chmod 0755 "$PREFIX/kaspad"; fi
  install -d -m 0755 "$DATA/kaspa-data"
fi

cat > "$ETC/zkas-node.env" <<EOF
ZKAS_DATA=$DATA/zkas-data
ZKAS_RPC=$ZKAS_RPC
ZKAS_P2P=$ZKAS_P2P
EOF
cat > "$ETC/bridge.env" <<EOF
# Empty means native-only. AuxPoW is enabled only when both values are set.
ZKAS_KASPA_NODE=$([[ $KASPA_MODE == disabled ]] && echo || echo "$KASPA_RPC")
ZKAS_KASPA_PAY=$KASPA_PAY
# The bridge version currently accepts malformed usernames and routes them to
# POOL_FALLBACK_ADDRESS. In a solo install this is the operator's own address,
# never a project/pool treasury. Valid miners are always paid to their own
# authorized address.
POOL_FALLBACK_ADDRESS=$ZKAS_ADDRESS
EOF
sed -e "s|127.0.0.1:16810|$ZKAS_RPC|" \
    -e "s|merged_kaspa_address: \"\"|merged_kaspa_address: \"$([[ $KASPA_MODE == disabled ]] && echo || echo "$KASPA_RPC")\"|" \
    -e "s|merged_kaspa_pay_address: \"\"|merged_kaspa_pay_address: \"$KASPA_PAY\"|" \
    -e "s|:5555|$STRATUM_ENDPOINT|" \
    "$(dirname "$0")/bridge.yaml.template" > "$ETC/bridge.yaml"
printf '%s\n' "$P2P_PEERS" > "$ETC/peers"
cat > "$ETC/healthcheck.env" <<EOF
ZKAS_SOLO_CONFIG_DIR=$ETC
ZKAS_RPC_PORT=${ZKAS_RPC##*:}
ZKAS_P2P_PORT=${ZKAS_P2P##*:}
STRATUM_PORT=$sport
HEALTH_PORT=18080
EOF
cp "$ETC/healthcheck.env" "$DATA/healthcheck.env"
if [[ $ZKAS_MODE == managed ]]; then sha256sum "$PREFIX/zkas-node" "$PREFIX/stratum-bridge" > "$ETC/manifest.sha256"; else sha256sum "$PREFIX/stratum-bridge" > "$ETC/manifest.sha256"; fi
install -m 0755 "$(dirname "$0")/healthcheck.sh" "$DATA/healthcheck.sh"
if [[ $ZKAS_MODE == managed ]]; then
  sed -e "s|@PREFIX@|$PREFIX|g" -e "s|@ETC@|$ETC|g" -e "s|@DATA@|$DATA|g" \
    "$(dirname "$0")/systemd/zkas-solo-node.service" > /etc/systemd/system/zkas-solo-node.service
fi
sed -e "s|@PREFIX@|$PREFIX|g" -e "s|@ETC@|$ETC|g" -e "s|@DATA@|$DATA|g" \
  "$(dirname "$0")/systemd/zkas-solo-bridge.service" > /etc/systemd/system/zkas-solo-bridge.service
if [[ $ZKAS_MODE == managed && -n "$PEER_ARGS" ]]; then
  install -d -m 0755 /etc/systemd/system/zkas-solo-node.service.d
  cat > /etc/systemd/system/zkas-solo-node.service.d/peers.conf <<EOF
[Service]
ExecStart=
ExecStart=$PREFIX/zkas-node --appdir=$DATA/zkas-data --rpclisten=$ZKAS_RPC --listen=$ZKAS_P2P --utxoindex --disable-upnp --yes$PEER_ARGS
EOF
fi

if [[ $KASPA_MODE != disabled ]]; then
  cat > "$ETC/kaspa-node.env" <<EOF
KASPA_DATA=$DATA/kaspa-data
KASPA_RPC=$KASPA_RPC
KASPA_P2P=$KASPA_P2P
EOF
  if [[ $KASPA_MODE == managed ]]; then sed -e "s|@PREFIX@|$PREFIX|g" -e "s|@ETC@|$ETC|g" -e "s|@DATA@|$DATA|g" \
    "$(dirname "$0")/systemd/zkas-solo-kaspa.service" > /etc/systemd/system/zkas-solo-kaspa.service; fi
fi

systemctl daemon-reload
systemctl enable zkas-solo-bridge.service >/dev/null
if [[ $ZKAS_MODE == managed ]]; then systemctl enable zkas-solo-node.service >/dev/null; fi
if [[ $KASPA_MODE == managed ]]; then systemctl enable zkas-solo-kaspa.service >/dev/null; fi
if [[ $NO_START == false ]]; then
  if [[ $ZKAS_MODE == managed ]]; then systemctl restart zkas-solo-node.service; sleep 2; fi
  if [[ $KASPA_MODE == managed ]]; then systemctl restart zkas-solo-kaspa.service; sleep 2; fi
  systemctl restart zkas-solo-bridge.service
fi
echo "Installed ZKas solo gateway."
echo "Stratum: $STRATUM_ENDPOINT"
echo "Data: $DATA"
echo "Check: $DATA/healthcheck.sh"
if [[ $NO_START == true ]]; then echo "Services were installed but not started (--no-start)."; fi
if [[ $KASPA_MODE != disabled ]]; then
  echo "Merged mining: enabled (Kaspa RPC $KASPA_RPC)"
fi
