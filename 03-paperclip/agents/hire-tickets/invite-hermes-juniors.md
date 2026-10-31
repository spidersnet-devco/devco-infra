# Bringing the Hermes juniors (pyro, webby, ops) into Paperclip

Hermes agents are *external* agents: they run their own gateway process and join
the company by invite. Do this once per profile, after `04-hermes/create-profiles.sh`.

## 1. Generate the invite (Paperclip)

Agents -> New Agent -> **Invite an external agent**.

In "Optional message for the agent", paste (edit the port per profile):

```
Your gateway URL is http://127.0.0.1:8642 and the API key is in your own
~/.hermes/.env as API_SERVER_KEY. Paperclip is at http://127.0.0.1:3100 on
the same machine. Your title is Junior Engineer (Python); you report to the CEO.
```

Ports: pyro 8642, webby 8643, ops 8644 (from devco.env). Titles:
- pyro  -> Junior Engineer (Python)
- webby -> Junior Engineer (Web)
- ops   -> Junior Engineer (Ops)

Click **Generate onboarding prompt**. It copies a one-time onboarding letter. One
invite per agent; they are single-use.

CLI equivalent:
```bash
paperclipai invite create --company-id <company-id> --payload-json '{"requestType":"agent"}'
paperclipai invite onboarding:text <token>
```

## 2. Paste it into that profile's chat

```bash
pyro chat        # (or webby chat / ops chat)
```

Paste the whole letter. The agent reads it and submits its own join request
(adapter `hermes_gateway`, its API URL/key, and the Paperclip URL). Because
everything is on one box, it is loopback traffic and does not need the
`dangerouslyAllowInsecureRemoteHttp` flag the NetworkChuck video used across machines.

## 3. Approve the hire

Approvals -> Pending -> Approve. Or:
```bash
paperclipai join list --company-id <company-id> --status pending_approval
paperclipai join approve <request-id> --company-id <company-id>
```

## 4. The agent claims its key, then YOU finish the wiring

After approval the agent claims a one-time Paperclip API key and tells you its
agent id. The running gateway only sees it once these lines are in that profile's
`~/.hermes/profiles/<name>/.env` and the gateway is restarted:

```
PAPERCLIP_API_URL=http://127.0.0.1:3100
PAPERCLIP_API_KEY=<the key it claimed>
PAPERCLIP_AGENT_ID=<its agent id>
PAPERCLIP_COMPANY_ID=<your company id>
```

```bash
hermes -p pyro gateway restart
```

Skip this and the agent does real work and reports it to nobody.

## 5. Test

Create a task assigned to the CEO:

```
Talk to pyro and make sure they can take work. Give them a small test task
(report their hostname, the model they are using, and the output of
`python3 --version`), wait for the answer, and tell me on this ticket whether
they are good to go.
```

Repeat for webby and ops. Then set each junior's **Reports to** = CEO on its
Harness/Runtime tab if the join request didn't already.

## Three keys, never crossed

| Key | What it's for | Where it lives |
|---|---|---|
| (none) local model | Hermes's own thinking via llama-swap | `config.yaml` base_url |
| `API_SERVER_KEY` | Lets Paperclip call Hermes | Hermes `.env`, used by Paperclip |
| `PAPERCLIP_API_KEY` | Lets Hermes call Paperclip | Hermes `.env`, claimed after approval |
