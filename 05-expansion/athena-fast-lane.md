# Expansion: adding Athena as an on-demand fast lane

Nothing in the company knows which machine a model runs on. Agents ask the gateway
for `coder-fast` or `coder-accurate`; llama-swap decides where that goes. Adding
Athena is therefore three steps on the Hermes box's gateway config and one wake
script. No agent, profile, Pi config, or Paperclip setting changes.

## What Athena would serve

RTX PRO 5000 (48 GB GDDR7, 1.3 TB/s) runs a 30–35B-class MoE **at Q8 in VRAM**
with prompt processing an order of magnitude faster than the Hermes box. That is
the fast lane. gpt-oss-120b stays on the Hermes box (it does not fit 48 GB without
paging experts over DDR5).

Suggested Athena model for `coder-fast-gpu`: Qwen3-Coder-30B-A3B at Q8_0 (~32 GB),
or whatever the current best 30–35B coder is when you get there. vLLM with prefix
caching is the better server on CUDA; llama-swap's `unified-cuda13` container is
the lower-effort one and matches this package.

## 1. Athena: serve it

Bare metal or Docker, not Proxmox passthrough (one less layer to debug).

```bash
# Ubuntu + NVIDIA driver + container toolkit installed. Then:
mkdir -p /opt/models /opt/llama-swap
docker run -d --name llama-swap --restart unless-stopped --runtime nvidia \
  -p 8080:8080 -v /opt/models:/models -v /opt/llama-swap:/etc/llama-swap/config \
  -e LLAMA_SWAP_LISTEN=0.0.0.0:8080 \
  ghcr.io/mostlygeek/llama-swap:unified-cuda13
```

`/opt/llama-swap/config.yaml` on Athena:

```yaml
healthCheckTimeout: 300
apiKeys:
  - "${env.ATHENA_GATEWAY_KEY}"      # export in the container env; the Hermes box sends it
models:
  "coder-fast-gpu":
    cmd: >
      llama-server --host 0.0.0.0 --port ${PORT} -ngl 99 -fa on --jinja
      --model /models/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf
      --ctx-size 262144 --parallel 4
      --cache-type-k q8_0 --cache-type-v q8_0
      --temp 0.7 --top-p 0.8 --top-k 20 --repeat-penalty 1.05
    ttl: 0
    capabilities: {tools: true, context: 65536, in: [text], out: [text]}
hooks:
  on_startup:
    preload: ["coder-fast-gpu"]
```

Four parallel slots at 64K each: that is the concurrency the Hermes box cannot give you.

## 2. Hermes box: make the fast lane route to Athena when it's up

In `/opt/llama-swap/config.yaml`:

1. Rename the local fast model `coder-fast` → `coder-fast-local` (and its entry in
   the `local` group and the preload list).
2. Add Athena as a peer and a selector that prefers it:

```yaml
peers:
  athena:
    proxy: http://athena.lan:8080
    apiKey: ${env.ATHENA_GATEWAY_KEY}
    models:
      - coder-fast-gpu
    timeouts: {connect: 5, responseHeader: 120}

selectors:
  "coder-fast":
    strategy: warm            # first READY target wins; Athena asleep -> local
    targets:
      - "athena/coder-fast-gpu"
      - "coder-fast-local"
    name: "coder-fast"
```

Agents keep asking for `coder-fast`. When Athena is awake and healthy, requests go
there; when it's asleep, they stay local. Confirm with the gateway UI
(`/ui`) and `curl $GATEWAY/v1/models`. If `warm` does not treat an unreachable
peer as "not ready" in the version you're running, use the `profiles` feature
instead: a profile that pins `coder-fast` to `athena/coder-fast-gpu`, activated by
the wake script via `PUT /api/profiles/active` and cleared by the sleep script.

Since the gateway now has a secret (`ATHENA_GATEWAY_KEY`), add
`Environment=ATHENA_GATEWAY_KEY=...` to `~/.config/systemd/user/llama-swap.service`
or an `EnvironmentFile=` pointing at a mode-600 file, then
`systemctl --user daemon-reload && systemctl --user restart llama-swap`.

## 3. Wake / sleep on demand

Athena idles at ~80–100 W, so keep it asleep unless the backlog justifies it.

- BIOS: enable Wake-on-LAN. On Athena: `sudo ethtool -s <nic> wol g` (persist via
  a udev rule or NetworkManager `802-3-ethernet.wake-on-lan magic`).
- Copy `wake-athena.sh` to `/opt/devco/bin/` on the Hermes box and fill in the MAC.
- Give the `ops` profile an SSH key to Athena that can only run
  `systemctl suspend` (use a `command="..."` restriction in `authorized_keys`).

Then two Paperclip routines, both assigned to `ops` (local model, free):

```
Wake Athena if there are 5 or more tasks in "todo" or "in progress" assigned to
pyro, webby or ops. Run /opt/devco/bin/wake-athena.sh and report the result on
this ticket. Do nothing if fewer than 5.
```
schedule: every 30 minutes, 18:00–07:00

```
If Athena is reachable (curl -s http://athena.lan:8080/health) and no task has been
assigned to pyro, webby or ops in the last 60 minutes, put it to sleep with
/opt/devco/bin/sleep-athena.sh and report on this ticket.
```
schedule: hourly

## What you get

- Juniors on the fast lane turn around tickets several times faster, and five or
  more can run concurrently.
- The Hermes box's gpt-oss-120b becomes the review/accuracy tier only, so its
  slots stop queueing.
- Total power cost: Athena's load wattage × the hours the backlog actually needed it.

## What you don't get

Not a smarter company at the top. Opus and Fable stay the brains. If local quality
ever matters more than speed, the next step is QLoRA on Athena using the juniors'
trajectories, which is a separate project.
