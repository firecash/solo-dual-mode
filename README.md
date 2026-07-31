# ZKas Solo Gateway

One-command Linux deployment for running a **public ZKas mainnet node** and
mining directly through a local `katpool`/ZKas Stratum bridge.

This is deliberately **not a pooled-mining installation**:

- every miner supplies its own `zkas:` payout address;
- the node template pays the finding miner directly;
- there is no PostgreSQL, share accounting, treasury, payout sweep, or public
  pool dashboard; the installer pins the bridge's legacy malformed-address
  fallback to the operator's own address rather than a project treasury;
- an optional local Kaspa node enables AuxPoW merged mining (one hash can earn
  KAS and ZKAS).

Linux (systemd) and Windows (PowerShell) are supported. Linux gets managed
systemd services; Windows gets a portable foreground runner. Each node can be
independently **managed** (downloaded and supervised by this kit) or
**external** (an existing node selected by RPC host/port). The bridge can use
ZKas managed + Kaspa managed, ZKas managed + Kaspa external, native-only, or
both nodes external. No existing data directory is reused or wiped.

## Architecture

```text
ASIC / Kaspa-compatible miner
          │ Stratum TCP :5555 (LAN/VPN by default)
          ▼
katpool stratum bridge (direct payout)
       │                    │ optional AuxPoW
       │ gRPC               │ gRPC
       ▼                    ▼
ZKas node :16810       Kaspa node :16110
ZKas P2P :16811        Kaspa P2P :16111
```

The bridge always submits native ZKas blocks to the ZKas node. When merged
mining is enabled, the bridge also obtains a Kaspa parent template and submits
Kaspa-target-clearing results to both nodes. Native ZKas mining remains valid if
the Kaspa parent is unavailable.

## Quick start from this checkout

There are two modes. **Managed** downloads a release selected by a maintainer
manifest (HTTPS + SHA-256; signature verification is a release-hardening step)
manifest and creates isolated services. **External** only configures the bridge
against nodes that already exist; it never starts, upgrades, or wipes them.

Build or copy the two binaries first:

```bash
cd /path/to/zkas-solo
sudo ./install.sh \
  --zkas-node-bin=/path/to/zkas-node \
  --bridge-bin=/path/to/stratum-bridge \
  --zkas-address=zkas:<your-shielded-address>
```

The address is only used as a validation/default test address. Miners still
authorize with their own address; no reward is redirected to the installer.

Enable merged mining by supplying a local Kaspa node and a Kaspa payout address:

```bash
sudo ./install.sh \
  --zkas-node-bin=/path/to/zkas-node \
  --bridge-bin=/path/to/stratum-bridge \
  --zkas-address=zkas:<your-address> \
  --kaspa-node-bin=/path/to/kaspad \
  --kaspa-pay-address=kaspa:<your-address>
```

After installation:

```bash
systemctl status zkas-solo-node zkas-solo-bridge
journalctl -u zkas-solo-node -f
journalctl -u zkas-solo-bridge -f
```

Managed-node example:

```bash
sudo ./install.sh \
  --zkas-node=download --kaspa-node=download \
  --zkas-address=zkas:<operator-address> \
  --kaspa-pay-address=kaspa:<operator-address>
```

External-node example (custom ports are supported):

```bash
sudo ./install.sh \
  --zkas-node=external --zkas-rpc=192.168.1.20:18010 \
  --kaspa-node=external --kaspa-rpc=127.0.0.1:17110 \
  --zkas-address=zkas:<operator-address> \
  --kaspa-pay-address=kaspa:<operator-address>
```

Linux path overrides are `--install-dir`, `--config-dir`, and `--data-dir`;
RPC/P2P overrides are `--zkas-rpc`, `--zkas-p2p`, `--kaspa-rpc`, and
`--kaspa-p2p`.
The installer refuses to reuse a non-empty data directory unless it carries
the kit ownership marker, preventing accidental attachment to another chain.

For managed downloads, pin an HTTPS release manifest with
`--zkas-release-manifest`, `--kaspa-release-manifest`, and
`--bridge-release-manifest`; each manifest contains
the platform asset URL and SHA-256. The installer never guesses an asset name
or executes an unchecked binary. The current kit does not yet embed a
maintainer public key for detached-signature verification; add that before
publishing a public installer. `--no-start` installs without launching.

The expected manifest shape is shown in
[`release-manifest.example.json`](release-manifest.example.json). A production
release should publish separate manifests for ZKas node, Kaspa node, and bridge
with immutable versioned URLs, signed manifests, and signed checksums. “Latest” should mean a
maintainer-updated manifest pointer, not an unpinned GitHub API asset lookup.

Windows has the equivalent `install.ps1` and `run.ps1`. The PowerShell path
uses the same explicit RPC/data-directory model and can run foreground without
administrator privileges. A Windows service wrapper can be added later without
changing the node or bridge configuration.

Point miners at `stratum+tcp://<host>:5555`, using their full `zkas:` address
as username and `x` as password. Do not expose the node RPC ports to the
internet. Open P2P `16811` if this is intended to be a public node.

## Mainnet safety rules

1. The installer refuses a non-`zkas:` operator address and never uses a
   project/pool treasury. The current bridge accepts malformed miner usernames
   for compatibility; those are routed to the operator address and are logged.
   A future strict-address bridge mode should reject them instead.
2. `--enable-unsynced-mining` is not used. A fresh node must sync before it can
   submit valid mainnet work.
3. ZKas RPC is bound to loopback. Only P2P and the explicitly selected Stratum
   port are exposed.
4. The bridge uses the ZKas template coinbase verbatim. The ZKas shielded root
   and mandatory dev-fee output must not be reconstructed by the wrapper.
5. The bridge is run in `external` node mode. The node and bridge have separate
   systemd units and restart independently without deleting chain data.
6. The installer makes no chain-data changes on an existing install. A separate
   `--reset-data` flag is intentionally not provided.

## Configuration

Installation files live below `/var/lib/zkas-solo` (data) and
`/etc/zkas-solo` (configuration):

| File | Purpose |
|---|---|
| `zkas-node.env` | Node paths, peers, RPC/P2P bind settings |
| `bridge.yaml` | One auto-vardiff Stratum instance |
| `kaspa-node.env` | Optional parent-node settings |
| `manifest.sha256` | Installed binary hashes |
| `healthcheck.sh` | Read-only service/node/port check |

The bridge is configured with `var_diff: true`, `shares_per_min: 20`, and an
ASIC-safe floor of `8192`. This controls share reporting only; it does not
change ZKas consensus difficulty or the miner's chance of finding a block.

## What is intentionally omitted

The full public pool stack (`katpool` accountant/API, Postgres, redactor,
treasury, PROP/PPLNS, and payout engines) is not installed. Those components
are for a custodial multi-miner pool and would create unnecessary custody and
accounting risk in a self-hosted solo setup.

## Recovery

```bash
/var/lib/zkas-solo/healthcheck.sh
systemctl restart zkas-solo-node
systemctl restart zkas-solo-bridge
```

Restarting either service preserves `/var/lib/zkas-solo/zkas-data` and never
wipes chain blocks. A node restart may temporarily stop new templates while it
reconnects and resynchronizes.
