# Persistent Anvil Dev Blockchain

Containerized [Foundry Anvil](https://getfoundry.sh/anvil/overview) dev node that persists chain state across container restarts.

## Quick start

```bash
docker compose up -d
```

RPC at `http://localhost:8545`, chain ID `31337`, default Foundry test accounts and keys.

```bash
curl -s -X POST http://localhost:8545 \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'
```

State survives `docker compose stop && docker compose start` (graceful flush) and is dumped to disk every 30 minutes by `--state-interval` (survives SIGKILL / OOM / `docker kill`).

## Customize

To pass extra anvil flags (block time, chain ID, mnemonic, etc.), copy the example override file and edit it, then run the container as normal:

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
# edit, then:
docker compose up -d
```

Tune `STATE_INTERVAL` (seconds, default `1800`) for a tighter dump cadence at the cost of more writes.

**Don't override `--host` or `--state`** — they're load-bearing for networking and persistence.

#### Custom initial chain state

For most needs, anvil flags cover what a `genesis.json` would: `--chain-id`, `--mnemonic`, `--accounts <N>`, `--balance <ETHER>`, `--hardfork <name>`, `--gas-limit <N>`. Set these in your override `command:`.

Anvil's CLI rejects `--init <genesis.json>` or `--fork-url <rpc-url>` together with `--state`, so a `genesis.json` or fetching mainnet state cannot be combined with the persistence flags directly. If you need seeded state (e.g. precompile contract code or mainnet contracts), bootstrap once *outside* this container, dump the result via the `anvil_dumpState` RPC, and place the JSON at `/data/anvil-state.json` in the volume — the normal `--state` flow takes over from there.

## Wipe the chain

```bash
docker compose down -v
```

## Tests

```bash
./test.sh
```

End-to-end tests of both persistence paths (graceful stop + SIGKILL recovery). CI runs them plus a Hadolint Dockerfile check on every push: [.github/workflows/test.yml](.github/workflows/test.yml).

## Caveats

- Anything between the last `--state-interval` dump and a hard crash is lost. For true durability use Reth/Geth in dev mode.
- On Windows, ensure `entrypoint.sh` has LF line endings (not CRLF), or the container fails with `exec format error`.
- Pin a Foundry version (`ghcr.io/foundry-rs/foundry:vX.Y.Z` in the [Dockerfile](Dockerfile)) for reproducible builds.