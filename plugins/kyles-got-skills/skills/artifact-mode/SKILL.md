---
name: artifact-mode
description: Maintain a living, visual claude.ai artifact for the CURRENT session — the prototype or project under discussion rendered as the primary visualization up top, with the conversation's story below it — refreshed after each turn by a persistent background keeper sub-agent. Use when the user says "/artifact-mode", "turn on artifact mode", "keep a living artifact of this conversation", "start/stop the conversation artifact", or asks for an auto-updating visual summary of the chat. Opt-in per session.
---

# Artifact Mode

Keep a single **visual claude.ai artifact** in sync with the session. The page has two zones:

- **Zone A — The Work:** the prototype/project under discussion, rendered as the primary
  visualization at the top. For a web prototype that means embedding it *live*.
- **Zone B — The Conversation:** the story of how the session got here, below Zone A.

If nothing showable exists yet, Zone A is omitted and Zone B is the whole page.

A persistent background **keeper** sub-agent owns the artifact and publishes it; you (the primary
agent) are just the dispatcher — after each of your responses you feed the keeper a short
**delta** and it updates the artifact in place at a stable claude.ai URL.

This works because it runs inside the interactive session: a headless `claude -p` has no
`Artifact` tool, but a sub-agent spawned via the Agent tool does. The keeper stays warm across
the session (resumed via SendMessage with its context intact), so updates are cheap deltas.

## Passive operation (most important rule)

This is a **silent, passive background system.** The user should almost never hear about it.

- **Never mention the keeper, the delta, the dispatch, the render, or "updating the artifact"**
  in your replies. Do not narrate these steps or announce that an update ran.
- Feed the keeper quietly at the very end of your turn. The Agent/SendMessage calls and their
  notifications are harness UI; your own prose must not reference them.
- **Surface the artifact link exactly once** — the moment it is first created — as a single
  minimal line, then never bring it up again on your own.
- Only discuss the artifact if the **user explicitly asks** ("where's the artifact?", "turn it
  off"). Then answer normally.
- If a dispatch/respawn fails, stay silent — do not surface errors unless asked. Try again next
  turn.

## Roles

- **Keeper = worker.** A background sub-agent named `artifact-keeper`. Owns the artifact: reads
  the prototype's source, builds both zones, edits the on-disk HTML, publishes it.
- **Primary (you) = dispatcher.** Each turn: run `turn.sh`, decide what the prototype is, send a
  delta. Never render or publish yourself.

## State (durable — survives keeper death *and* context compaction)

Under `~/.claude/conversation-artifacts/`, keyed by session id:

| file | purpose |
|---|---|
| `<SID>.state.json` | active flag, keeper name, current URL — the dispatcher's memory |
| `<SID>.artifact.html` | current page the keeper edits |
| `<SID>.url` | current artifact URL (absent until first publish) |
| `<SID>.digest.md` | conversation digest (rebuild/rehydrate source) |

**Never rely on remembering the session id, transcript path, or whether you already spawned the
keeper.** Long sessions get compacted and that memory is lost. `turn.sh` re-derives all of it
from disk on every call.

## Activation (one-time)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/turn.sh on
```

Then give the user **one** brief, low-key confirmation (e.g. "Artifact mode on — I'll keep a
visual artifact of this session updated in the background."). Don't explain the mechanism. This
is the only unprompted activation message. Do not spawn the keeper yet — that happens lazily.

## Each turn (at the very end of your reply — silently)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/turn.sh status
```

This refreshes the digest and prints `SESSION_ID`, `AM_DIR`, `DIGEST`, `ARTIFACT_HTML`,
`REPO_DIR`, `TURNS`, `KEEPER`, `URL`, `PUBLISHED`, and an `ACTION`. Act on `ACTION`:

- **`SKIP`** — done for this turn. (Either not active, or below the turn threshold: default 3
  real user turns, override with `AM_MIN_TURNS`.)
- **`SPAWN`** — spawn the keeper with the Agent tool: `name: "artifact-keeper"`,
  `subagent_type: general-purpose`, `model: sonnet`, `run_in_background: true`, description
  `"Conversation artifact keeper"`, using the **Keeper spawn prompt** below. Then record it:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/turn.sh mark-spawned artifact-keeper
  ```
- **`DISPATCH`** — `SendMessage` to the name in `KEEPER` with just the **delta** (see format
  below). Do not re-send the standing instructions.
  - If the SendMessage **fails** (keeper reaped), respawn exactly as in `SPAWN`, folding this
    turn's delta into the spawn prompt. It auto-rehydrates from disk.

Also: **skip the dispatch entirely for trivial turns** — acknowledgements, "thanks", "yes",
a one-word course correction. Nothing changed that's worth a render.

When the keeper replies `ARTIFACT_URL=<url>`, record it:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/turn.sh mark-published "<url>"
```

If `PUBLISHED` was `false` before this turn, surface one line — `📄 Session artifact: <url>` —
and never mention it again on your own.

## Identifying the prototype (each turn)

Decide whether this session has produced something **showable**: an app, page, component, script,
API, dataset, or document that exists on disk and could be demonstrated. If so, pick its **entry
points** — the smallest set of files (max ~5, absolute paths) that represent what it currently
is. Prefer the file a person would open to see the thing.

Classify it as one of: `web` | `cli` | `library` | `data` | `design` | `none`.

Use `none` when the session is pure discussion, research, or planning with nothing on disk yet.
Don't list the whole repo — list what should be *rendered*.

### Keeper spawn prompt (standing instructions — send once, on spawn/respawn)

```
You are `artifact-keeper`: a long-running background agent maintaining ONE living, visual
claude.ai artifact for a coding session. Work silently; your only reply each time is the URL line.

FIRST read the visual design guidance:
${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/visual-prompt.md
It defines a PR rail plus a two-zone page: Zone A = the prototype/project (primary), Zone B =
the conversation story (secondary, below).

THEN, on EVERY update (fresh or resuming), refresh pull-request state by running:
  cd <REPO_DIR> && bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/prs.sh
It prints JSON: {"available":bool,"prs":[{number,title,url,state,branch,review,checks,updated,
current}]}. Rebuild the PR rail from this output every single turn — PR state changes on GitHub's
clock whether or not the conversation mentions it, so a cached rail goes stale silently. If
`available` is false or `prs` is empty, omit the rail entirely and render nothing in its place.

Durable state (source of truth):
  HTML:   <ARTIFACT_HTML>
  URL:    <AM_DIR>/<SESSION_ID>.url
  digest: <DIGEST>
  repo:   <REPO_DIR>

Determine your mode by checking whether the URL file exists and is non-empty:
- RESUMING (url present): read the current .artifact.html to rehydrate your model of the page.
  Do NOT rebuild from scratch.
- FRESH (no url): read the digest and build the initial artifact HTML at the .artifact.html
  path. Pick a stable, concise title and a topic-fitting favicon emoji.

ZONE A: the PROTOTYPE line below gives a kind and file paths. READ THOSE FILES YOURSELF with the
Read tool — their contents are not inlined here. Render them as described in visual-prompt.md
(for `web`, embed live in a sandboxed iframe). If the kind is `none`, omit Zone A entirely.
Never invent output or fake a working state — render what the code actually is.

Then publish:
- FRESH: call the Artifact tool to publish the file (private is fine). Write the returned URL
  (only) to the .url file. Reply exactly: ARTIFACT_URL=<url>
- RESUMING: apply the delta — Zone A re-rendered wholesale if the prototype changed, Zone B
  extended with TARGETED Edit-tool changes (add a timeline node, flip the status chip, add a
  card). Do not regenerate Zone B. Then re-publish IN PLACE by passing url:<the stored URL> to
  the Artifact tool. Overwrite the .url file with the returned url.
  Reply exactly: ARTIFACT_URL=<url>

Always keep the title and favicon stable across updates. Never converse — just do the work and
reply with the ARTIFACT_URL line.

DELTA: <one or two sentences: what the user asked, what you did, any decision/result>
PROTOTYPE: <kind> | <comma-separated absolute paths, or "none">
```

### Delta message format (each subsequent turn, via SendMessage)

Just the newest change — the keeper already holds the story:

```
DELTA: <user asked X; we did/decided Y; result Z>
PROTOTYPE: <kind> | <paths, or "none">
```

Always include the `PROTOTYPE` line, even when unchanged — it's how the keeper knows whether to
re-render Zone A.

## Turning it off

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/artifact-mode/assets/turn.sh off
```

Every subsequent `status` returns `ACTION=SKIP`. The last published URL stays valid, and
`turn.sh on` resumes with the same artifact (keeper name and URL are preserved).

## Notes

- **Model:** Sonnet — good visuals at moderate cost.
- **Cost:** one sub-agent render per non-trivial turn once past the threshold. Raise
  `AM_MIN_TURNS` if that's too eager.
- **Privacy — check before activating.** Artifacts are private to the user's account by default,
  but this publishes session content to claude.ai every turn, and **Zone A publishes actual
  source code and UI**. If the project is proprietary or the conversation is sensitive, say so
  plainly, once. If the user says "conversation only", always send `PROTOTYPE: none` from then
  on and Zone A is dropped.
- **Why a warm keeper:** it remembers the page structure, so per-turn updates are cheap deltas
  with strong continuity. Durable disk state means a dead keeper is silently respawned and
  rehydrated — the user never notices.
