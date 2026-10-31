# Expansion: adding Athena as an on-demand fast lane

Nothing in the company knows which machine a model runs on. Agents ask the gateway
for `coder-fast` or `coder-accurate`; llama-swap decides where that goes. Adding
Athena is therefore a peer entry and a profile on the Hermes box's gateway config,
plus a wake script. No agent, Hermes profile, Pi config, or Paperclip setting changes.

## What Athena would serve

RTX PRO 5000 Blackwell (48 GB GDDR7, ~1.3 TB/s) runs a 30–35B-class MoE **at Q8 in
VRAM** with prompt processing several times faster than the Hermes box. That is the
fast lane. gpt-oss-120b stays on the Hermes box (63 GB does not fit 48 GB without
paging experts over PCIe).

Suggested Athena model for `coder-fast-gpu`: `Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf` (38.5 GB,
same family as the local fast lane, so behaviour matches) or whatever the current
best 30–35B coder is when you get there. llama-swap's `unified-cuda13` container is
the lower-effort server and matches this package; vLLM with prefix caching is the
faster one if you want to tune.

## 1. Athena: serve it

Bare metal or Docker, not Proxmox passthrough (one less layer to debug).

```bash
# Ubuntu + NVIDIA driver + container toolkit installed. Then:
mkdir -p /opt/models /opt/llama-swap
docker run -d --name llama-swap --restart unless-stopped --runtime nvidia \
  -p 8080:8080 -v /opt/models:/models -v /opt/llama-swap:/etc/llama-swap/config \
  -e LLAMA_SWAP_LISTEN=0.0.0.0:8080 -e ATHENA_GATEWAY_KEY='<long random string>' \
  ghcr.io/mostlygeek/llama-swap:unified-cuda13
```

`/opt/llama-swap/config.yaml` on Athena (the `${env.…}` macro makes config loading
fail if the variable is missing, which is what you want):

```yaml
healthCheckTimeout: 300
apiKeys:
  - "${env.ATHENA_GATEWAY_KEY}"
models:
  "coder-fast-gpu":
    proxy: "http://127.0.0.1:${PORT}"
    cmd: >
      llama-server --host 127.0.0.1 --port ${PORT} -ngl 99 -fa on
      --model /models/Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf
      --ctx-size 262144 --parallel 4
      --cache-type-k q8_0 --cache-type-v q8_0 --cache-ram 2048
      --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0.0 --presence-penalty 1.5
    ttl: 0
    filters:
      setParamsByID:
        "${MODEL_ID}": {chat_template_kwargs: {enable_thinking: false}}
    capabilities: {tools: true, context: 65536, in: [text], out: [text]}
hooks:
  on_startup:
    preload: ["coder-fast-gpu"]
```

Four parallel slots at 64K each. If it OOMs at 48 GB, drop to `--parallel 3`.

## 2. Hermes box: route the fast lane to Athena only while it's awake

**Not a selector.** llama-swap's `warm` strategy requires local targets and rejects a
peer target at config load, and the other strategies never check whether a peer is
reachable. The mechanism that works is a **profile with a pin**: while the profile is
active, requests for `coder-fast` are rewritten to `athena/coder-fast-gpu`; when no
profile is active they go to the local `coder-fast`. The wake script activates the
profile after Athena answers; the sleep script clears it. A gateway restart activates
no profile, so it always falls back to local on its own.

Uncomment the block at the end of `/opt/llama-swap/config.yaml` (it is already there):

```yaml
peers:
  athena:
    proxy: http://athena.lan:8080
    apiKey: ${env.ATHENA_GATEWAY_KEY}
    models: [coder-fast-gpu]
    timeouts: {connect: 5, responseHeader: 120}
profiles:
  athena:
    description: "Fast lane served by Athena's RTX PRO 5000"
    pins:
      coder-fast: "athena/coder-fast-gpu"
```

The gateway now has a secret, so give the service an env file:

```bash
install -m 600 /dev/null ~/.config/llama-swap.env
echo 'ATHENA_GATEWAY_KEY=<the same string>' > ~/.config/llama-swap.env
# uncomment the EnvironmentFile= line in ~/.config/systemd/user/llama-swap.service, then:
/opt/llama-swap/llama-swap -config /opt/llama-swap/config.yaml -validate
systemctl --user daemon-reload && systemctl --user restart llama-swap
```

Check with `curl -s 127.0.0.1:8080/api/profiles` (lists `athena`) and, after a wake,
`curl -s 127.0.0.1:8080/api/profiles/active`.

## 3. Wake / sleep on demand

Athena idles at ~80–100 W, so keep it asleep unless the backlog justifies it.

- BIOS: enable Wake-on-LAN. On Athena: `sudo ethtool -s <nic> wol g` (persist via
  a udev rule or NetworkManager `802-3-ethernet.wake-on-lan magic`).
- Put Athena's MAC in `/opt/devco/devco.env` as `ATHENA_MAC`; `wake-athena.sh` and
  `sleep-athena.sh` are installed to `/opt/devco/bin/` by `install-paperclip.sh`.
- Give the `ops` profile an SSH key to Athena that can only run
  `systemctl suspend` (a `command="..."` restriction in `authorized_keys`; see the
  header of `sleep-athena.sh`).

Then two Paperclip routines, both assigned to `ops` (local model, free), both with
the `devco-infra` project set so they have a working directory:

```
Wake Athena if there are 5 or more tasks in "todo" or "in progress" assigned to
pyro, webby or ops. Run /opt/devco/bin/wake-athena.sh and report the result on
this task. Do nothing if fewer than 5.
```
schedule: `*/30 18-23,0-7 * * *` (every 30 minutes, 18:00–07:59)

```
If Athena is reachable (curl -s http://athena.lan:8080/health) and no task has been
assigned to pyro, webby or ops in the last 60 minutes, put it to sleep with
/opt/devco/bin/sleep-athena.sh and report on this task.
```
schedule: `0 * * * *` (hourly)

**Simpler alternative, no routines:** llama-swap ships `cmd/wol-proxy`, a tiny proxy
that sends the magic packet when its upstream is down and holds the request until
Athena's gateway connects. Run it on the Hermes box in front of Athena and point the
peer at it; Athena then wakes on the first real request. You still want the sleep
routine (or a BIOS idle timer) to put it back down.

## What you get

- Juniors on the fast lane turn around tickets several times faster, and four can
  run concurrently without touching the accuracy lane.
- The Hermes box's gpt-oss-120b becomes the review/accuracy tier only, so its
  slots stop queueing.
- Total power cost: Athena's load wattage × the hours the backlog actually needed it.

## What you don't get

Not a smarter company at the top. Opus and Fable stay the brains. If local quality
ever matters more than speed, the next step is QLoRA on Athena using the juniors'
trajectories, which is a separate project.
