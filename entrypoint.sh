#!/bin/sh
# Anvil with persistent state. Defaults bake in --host (for Docker port forwarding),
# --state (the persisted state file), and --state-interval (anvil's native periodic
# dump). Extra args from `command:` (compose) or `docker run ... <image> <args>`
# are appended via "$@".
exec anvil \
  --host 0.0.0.0 \
  --state /data/anvil-state.json \
  --state-interval "${STATE_INTERVAL:-1800}" \
  "$@"
