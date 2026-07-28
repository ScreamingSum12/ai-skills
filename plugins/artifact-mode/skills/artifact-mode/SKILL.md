---
name: artifact-mode
description: Maintain a living, visual claude.ai artifact that retells the story of the CURRENT conversation, refreshed after each turn by a persistent background keeper sub-agent. Use when the user says "/artifact-mode", "turn on artifact mode", "keep a living artifact of this conversation", "start/stop the conversation artifact", or asks for an auto-updating visual summary of the chat. Opt-in per session.
---

# Artifact Mode

Keep a single **visual claude.ai artifact** in sync with the conversation. A persistent background **keeper** sub-agent holds the artifact's context and publishes it; you (the primary agent) are just the dispatcher — after each of your responses you feed the keeper a short **delta** describing what changed, and it updates the artifact in place at a stable claude.ai URL.

This works because it runs inside the interactive session: a headless `claude -p` has no `Artifact` tool, but a sub-agent spawned via the Agent tool does. The keeper stays warm across the whole session (resumed via SendMessage with its context intact), so updates are cheap deltas — not full re-renders.

## Passive operation (most important rule)

This is a **silent, passive background system.** The user should almost never hear about it.

- **Never mention the keeper, the delta, the dispatch, the render, or "updating the artifact"** in your replies. Do not narrate these steps or announce that an update ran.
- Feed the keeper quietly at the very end of your turn. The Agent/SendMessage calls and their notifications are harness UI; your own prose must not reference them.
- **Surface the artifact link exactly once** — the moment it is first created — as a single minimal line, then never bring it up again on your own.
- Only discuss the artifact if the **user explicitly asks** (e.g. "where's the artifact?", "turn it off"). Then answer normally.
- If a dispatch/respawn fails, stay silent — do not surface errors unless asked. Just try again next turn.

## Roles
- **Keeper = worker.** A background sub-agent named `artifact-keeper`. Owns the artifact: builds it, edits the on-disk HTML, publishes/updates it, persists the URL.
- **Primary (you) = dispatcher.** Locate the session, refresh the digest, and send the keeper a short delta each turn. Never render or publish yourself.

## State (durable — source of truth, survives keeper death)
Under `~/.claude/conversation-artifacts/` (call it `<AM_DIR>`), keyed by `<SESSION_ID>`:
- `<SESSION_ID>.artifact.html` — current page the keeper edits
- `<SESSION_ID>.url` — current artifact URL (absent until first publish)
- `<SESSION_ID>.digest.md` — full conversation digest (rebuild/rehydrate source)

## Activation (one-time)
1. Locate this session's transcript and id:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/locate-session.sh
   ```
   It prints `<session_id>\t<transcript_path>`. Hold both for the session.
2. Give the user **one** brief, low-key confirmation (e.g. "Artifact mode on — I'll keep a visual artifact of our conversation updated in the background."). Do not explain the mechanism or the keeper. This is the only unprompted activation message.
3. Do **not** spawn the keeper yet — it's spawned lazily on the first qualifying turn.

## Each turn (at the very end of your reply — silently)
1. Refresh the digest and check the 3-turn threshold (substitute real values):
   ```bash
   AM_DIR="$HOME/.claude/conversation-artifacts"; mkdir -p "$AM_DIR"
   bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/digest.sh "<TRANSCRIPT_PATH>" > "$AM_DIR/<SESSION_ID>.digest.md"
   grep -c '^## Assistant' "$AM_DIR/<SESSION_ID>.digest.md"
   ```
   If the Assistant count is **< 3**, stop here for this turn.
2. **If the keeper is not running yet this session** (you have not spawned it): spawn it with the Agent tool — `name: "artifact-keeper"`, `subagent_type: general-purpose`, `model: sonnet`, `run_in_background: true`, description `"Conversation artifact keeper"` — using the **Keeper spawn prompt** below. Then you're done for this turn (the spawn message itself carries the first delta).
3. **If the keeper is already running:** `SendMessage` to `artifact-keeper` with a short **delta** (see format below). Do not re-send the standing instructions.
4. **If that SendMessage fails** (keeper died/timed out): respawn it exactly as in step 2 (the spawn prompt auto-rehydrates from disk), folding this turn's delta into the spawn message.
5. Handle the keeper's completion notifications silently. On the **first** publish only, surface one line: `📄 Conversation artifact: <url>`. Never again on your own.

### Keeper spawn prompt (standing instructions — send once, on spawn/respawn)
```
You are `artifact-keeper`: a long-running background agent maintaining ONE living, visual
claude.ai artifact for a conversation. Work silently; your only reply each time is the URL line.

Read the visual design guidance: ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/visual-prompt.md

Durable state (source of truth) under ~/.claude/conversation-artifacts/ :
  HTML:   <SESSION_ID>.artifact.html
  URL:    <SESSION_ID>.url
  digest: <SESSION_ID>.digest.md

FIRST, determine your mode by checking whether <SESSION_ID>.url exists and is non-empty:
- RESUMING (url present): read that url and the current .artifact.html to rehydrate your mental
  model of the artifact. Do NOT rebuild from scratch.
- FRESH (no url): read the .digest.md and build the initial artifact HTML at the .artifact.html
  path. Pick a stable, concise title and a topic-fitting favicon emoji.

Then publish:
- FRESH: call the Artifact tool to publish the file (private is fine). Write the returned URL
  (only) to the .url file. Reply exactly: ARTIFACT_URL=<url>
- RESUMING/updating: apply the delta below by making TARGETED Edit-tool changes to the on-disk
  .artifact.html (extend the timeline, flip the status chip, add a card) — do NOT regenerate the
  whole page; keep your context small. Then re-publish IN PLACE by passing url:<the stored URL>
  to the Artifact tool. Overwrite the .url file with the returned url. Reply exactly: ARTIFACT_URL=<url>

Always keep the title and favicon stable across updates. Stay lean and visual. Never converse —
just do the work and reply with the ARTIFACT_URL line.

DELTA (what changed this turn):
<one or two sentences: what the user asked, what you did, any decision/result>
```

### Delta message format (each subsequent turn, via SendMessage)
Just the newest change, one or two sentences — the keeper already holds the story:
```
DELTA: <user asked X; we did/decided Y; result Z>
```

## Turning it off
If the user says to stop / pause artifact mode, stop feeding the keeper for the rest of the session. You may leave the keeper idle (harmless) or let it be reaped. The last published URL stays valid.

## Notes
- **Model:** Sonnet — good visuals at moderate cost. Fires every turn from the 3rd onward.
- **Privacy:** artifacts are private to the user's account by default; this still publishes conversation content to claude.ai. Flag it only if the conversation is sensitive.
- **Why a warm keeper:** it remembers the artifact's structure, so per-turn updates are cheap deltas with strong continuity. Durable disk state means a dead keeper is silently respawned and rehydrated — the user never notices.
