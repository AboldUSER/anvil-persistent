# Persistent Anvil Dev Blockchain

Containerized anvil dev node that persists chain state across container restarts. State is written to disk every 30 minutes by default and again on graceful shutdown.

## Run

```bash
docker compose up -d
```

RPC at `http://localhost:8545`, chain ID `31337`, default Foundry test accounts and keys.

## Verify

```bash
curl -s -X POST http://localhost:8545 \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'
```

`docker compose stop && docker compose start` — block height and deployed contracts survive.

## How persistence works

The entrypoint runs:

```
anvil --host 0.0.0.0 --state /data/anvil-state.json --state-interval $STATE_INTERVAL "$@"
```

Two anvil flags do the work:

1. **`--state /data/anvil-state.json`** — loads the file on startup (if it exists), and flushes on graceful shutdown (SIGINT/SIGTERM). Triggered by `docker compose stop`, Docker Desktop's Stop button, or any clean signal within `stop_grace_period` (30s).
2. **`--state-interval <seconds>`** — anvil writes the state to the same file every N seconds. This is what protects you from SIGKILL / OOM / `docker kill`.

## Configuration

- `STATE_INTERVAL` (seconds) — defaults to `1800` (30 min). Lower = less data loss on hard crash, more write overhead.
- State file lives at `/data/anvil-state.json` inside the container, backed by the `anvil-data` named volume.

### Custom anvil flags

To pass additional flags to anvil (block time, chain ID, custom mnemonic, genesis file, etc.) without editing tracked files, copy the example override file and edit it:

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
# edit docker-compose.override.yml
docker compose up -d
```

Compose auto-merges `docker-compose.override.yml` on top of [docker-compose.yml](docker-compose.yml), and the file is gitignored so your local tweaks stay local. The flags are appended to:

```
anvil --host 0.0.0.0 --state /data/anvil-state.json --state-interval $STATE_INTERVAL <YOUR FLAGS>
```

**Don't override `--host` or `--state` — they're required for proper networking and persistence.**

#### Custom initial chain state

Anvil's CLI rejects `--init <genesis.json>` together with `--state` or `--dump-state`, so a `genesis.json` cannot be combined with our persistence flags directly. For most dev needs, anvil flags cover what `genesis.json` would do:

- **Chain ID** — `--chain-id 1337`
- **Prefunded accounts** — `--mnemonic "..."` and `--accounts <N>` (each gets 10000 ETH)
- **Per-account starting balance** — `--balance <ETHER>`
- **Hardfork** — `--hardfork <name>`
- **Gas limit** — `--gas-limit <N>`

Add these to your `command:` in `docker-compose.override.yml`.

If you genuinely need a `genesis.json` (e.g. to preload contract code at specific addresses or set storage slots), the workaround is to bootstrap once *outside* this container, dump the resulting state via the `anvil_dumpState` RPC, and place that state JSON at `/data/anvil-state.json` in the named volume. After that, our normal `--state` flow takes over.

## Wipe the chain

```bash
docker compose down -v
```

## Tests

End-to-end tests live in [test.sh](test.sh) and exercise both persistence paths:

```bash
./test.sh
```

- **Test 1**: send a tx, `docker compose stop` (SIGINT), `start`, assert balance + block height survived.
- **Test 2**: set `STATE_INTERVAL=5`, send a tx, wait for the periodic dump to write the state file, `docker kill` (SIGKILL — no graceful flush), restart, assert state survived. This is the test that actually exercises `--state-interval`.

The tests use a separate compose project (`anvil-persist-test`), an override file ([docker-compose.test.yml](docker-compose.test.yml)) that publishes RPC on host port `18545` to avoid conflict with dev container, and the test container, volume, and built image are cleaned up on exit.

CI runs both the tests and a Hadolint Dockerfile lint on every push: [.github/workflows/test.yml](.github/workflows/test.yml).

## Caveats

- Anything between the last `--state-interval` dump and a hard crash is lost. For true durability, use Reth/Geth in dev mode instead.
- Force-stop / Kill in Docker Desktop (or `docker kill`) sends SIGKILL — no `--state` flush, only the periodic dump's last write survives.
- On Windows, ensure `entrypoint.sh` has LF line endings (not CRLF), otherwise the container fails with `exec format error`.
- `latest` tag drift: pin `ghcr.io/foundry-rs/foundry:vX.Y.Z` in the Dockerfile for reproducible builds across teammates.
