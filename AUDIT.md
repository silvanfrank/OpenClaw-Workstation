# Telegram channel crash-loop audit

Date: 2026-05-03
Last commit fixing this in repo: `2545860` (and `e6a8ec6`)
Status: **fixed in repo, not yet deployed to the running container**

## What the gateway is failing on

```
Gateway failed to start: Error: Invalid config at /config/.openclaw/openclaw.json.
channels.telegram: invalid config: must NOT have additional properties
```

OpenClaw's config schema for `channels.telegram` no longer accepts:

- `enabled`
- `botToken`
- `dmPolicy`
- `groupPolicy`
- `streamMode`
- `allowFrom`

The current valid shape is `{ tokenFile: "..." }` (matching what the
first-boot template at `openclaw-run:148` already produces). The Telegram
gateway-level options (`enabled`) and the bot-level options
(`dmPolicy`/`groupPolicy`/`streamMode`/`allowFrom`) appear to have moved to
`plugins.entries.telegram` — the deployed config already has
`plugins.entries.telegram = { enabled: true }` — but where the rest of those
fields live now is unconfirmed and was *not* migrated by my fix.

## What `openclaw-run` does in the repo right now (post-fix)

After commit `2545860`, the merge path:

1. Unconditionally deletes `.channels.telegram`, `.channels.discord`, and
   `.channels.slack` (`openclaw-run:276`).
2. Re-adds them from ENV using the modern `{ tokenFile }` shape only when
   `TELEGRAM_BOT_TOKEN` / `DISCORD_BOT_TOKEN` / `SLACK_BOT_TOKEN`+`SLACK_APP_TOKEN`
   are set (`openclaw-run:281-301`).
3. Drops `.channels` entirely if it ends up empty (`openclaw-run:304`).

This is correct. If the script ran, the bad block could not survive a restart.

## Why the container is still crash-looping

The script is correct. The deployed container is not running it.

**Evidence (latest log dump, 23:17:45):**

The script prints these markers in order on every start:

```
📄 Merging environment updates into existing config...
[possibly: 📱 Configuring Telegram from ENV...]
✅ Gateway config updated/verified at /config/.openclaw/openclaw.json
```

The `📱 Configuring Telegram from ENV...` line only fires when
`TELEGRAM_BOT_TOKEN` is set. In the latest run it does **not** appear —
implying the branch was skipped, ENV is unset, or the new script branches
aren't there at all.

But the printed config still contains:

```json
"channels": { "telegram": {
  "enabled": true, "botToken": "...",
  "dmPolicy": "pairing", "groupPolicy": "allowlist",
  "streamMode": "partial", "allowFrom": ["..."]
}}
```

That is impossible if the new script were executing — the unconditional
`jq 'del(.channels.telegram, ...)'` at `openclaw-run:276` runs **before**
any ENV-conditional branches. After that delete, the only way `botToken`
etc. could reappear is if ENV was set (it isn't, no Telegram log line) or
if the script that ran was the *old* version.

**Conclusion:** the running image was built before commit `e6a8ec6`. The
restart picked up the persisted `openclaw.json` from the volume but used
the old `openclaw-run` baked into the image.

### Why the rebuild didn't happen

Likely causes (in order of likelihood):

1. **Coolify "Restart" instead of "Redeploy + Rebuild".** A restart reuses
   the existing image. Only a rebuild copies the new `openclaw-run` from
   the repo into a new image layer.
2. **Coolify build cache hit on the `COPY openclaw-run …` layer.**
   Less likely — changing the file should invalidate that layer's hash —
   but if the platform short-circuited to a cached image tag, the new
   layer never got built.
3. **Build hadn't finished by the time of the restart.** The Dockerfile
   does `git clone`, `pnpm install`, `pnpm build`, and `pnpm ui:build`.
   That's many minutes on a fresh build. Commits landed at 23:11; restart
   at 23:17 — too tight for a clean rebuild without cache.

## What to do to actually deploy the fix

1. **Force a clean rebuild in Coolify** ("Build without cache" / "Force
   rebuild" — not "Restart"). Confirm the new image gets a different ID.
2. **One-shot repair the live config** so even if S6 wins the race, the
   gateway can come up:

   ```bash
   # exec into the running container
   jq 'del(.channels.telegram)
       | .channels.telegram = { "tokenFile": "/config/.openclaw/credentials/telegram-bot-token" }' \
     /config/.openclaw/openclaw.json > /tmp/c.json && mv /tmp/c.json /config/.openclaw/openclaw.json

   mkdir -p /config/.openclaw/credentials
   echo -n "$TELEGRAM_BOT_TOKEN" > /config/.openclaw/credentials/telegram-bot-token
   chmod 600 /config/.openclaw/credentials/telegram-bot-token
   ```

3. **Verify the image actually ran the new script** after the rebuild.
   The new script always logs `🔧 Setting permissions on /config/.openclaw...`
   *after* the channel-rewrite block. To prove the new code is live, exec in:

   ```bash
   grep -n "del(.channels.telegram" /etc/services.d/openclaw/run
   ```

   Should print line ~276. If that grep is empty, the image wasn't rebuilt.

## Behavioral regressions introduced by the fix

The legacy config carried these settings that the new shape silently drops:

| Field | Old value | What it controlled |
|---|---|---|
| `dmPolicy` | `"pairing"` | DM access policy |
| `groupPolicy` | `"allowlist"` | Group chat policy |
| `allowFrom` | `["5851065830"]` | **Telegram user allowlist** |
| `streamMode` | `"partial"` | Stream chunking |

**The `allowFrom` allowlist is the security-relevant one.** Once the
gateway comes up after this fix, the bot may accept messages from anyone
who can DM it. If the bot username/token is public (and they are now —
both leaked in the logs pasted into the chat), this is exploitable.

These options likely live under `plugins.entries.telegram` in the new
schema, but the exact field names and shape are **not confirmed**. The
fix in this repo does not migrate them. Two options:

- **(a)** Inspect the OpenClaw source / schema (`/opt/openclaw` in the
  container, or the upstream repo) to find the new home for these fields,
  then add a jq block to write them under `plugins.entries.telegram`.
- **(b)** Accept the regression and rely on Telegram's own bot privacy
  settings + the secret bot username.

## Pre-existing issues uncovered while debugging

These were not introduced by my change but are worth flagging:

1. **Image pulls OpenClaw `main` unpinned.** `Dockerfile:45` does
   `git clone --depth 1 https://github.com/openclaw/openclaw.git`. Every
   rebuild gets whatever HEAD is. The next breaking schema change will
   reproduce this same crash-loop with a different field name. **Pin to a
   tag or SHA.**

2. **Bot token / API key / gateway token written world-readable.**
   `openclaw-run:322` runs `chmod -R 755 "$CONFIG_DIR"` over the entire
   `/config/.openclaw` tree, including `credentials/telegram-bot-token`
   and `openclaw.json` (which embeds the OpenRouter/transcript API keys
   inline). Inside the container, any user can read them. Not catastrophic
   in a single-tenant container but unnecessary.

3. **Secrets re-printed verbatim on every start.** `openclaw-run:326`
   prints the full config (with embedded `gateway.auth.token` and
   `skills.entries.transcriptapi.apiKey`) and the script also `log`s
   `Auth Token: …` at line 114. Anyone with log access has the gateway
   token forever. Useful for debugging, costly for security.

4. **Crash-loop has no backoff.** S6 restarts the gateway as fast as it
   can crash — the logs show ~8 attempts per minute. Each writes a
   stability bundle to `/config/.openclaw/logs/stability/` which will
   eventually fill the volume.

5. **`bug` repaired by every restart.** `openclaw-run` mutates the same
   `openclaw.json` Coolify users may also edit via the OpenClaw control
   UI. Channel edits made through the UI will be wiped on next restart
   (the fix is "delete and rebuild from ENV"). ENV is now the only source
   of truth for channels.

## Secrets exposed in this debugging session

The following appeared multiple times in the pasted logs / config file
content. Treat them as compromised and rotate:

- Gateway auth token: `b2f8a13c...91c60`
- Telegram bot token: `8594209516:AAHu...`
- TranscriptAPI key: `sk_c5Nj9Lyx...`

Rotate via Coolify env vars and redeploy.
