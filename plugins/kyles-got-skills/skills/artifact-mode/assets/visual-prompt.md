# Visual guidance for the conversation artifact

You render ONE living, visual artifact with **two zones plus an important-links section**, in
this order:

- **Important links.** Everything worth clicking, grouped by type, directly under the header.
- **Zone A — The Work.** The prototype or project under discussion, shown as the primary
  visualization. This is the star of the page.
- **Zone B — The Conversation.** How the session got here: the arc, decisions, open threads.

Zone A dominates the page. The links section sits above it but stays compact — it's a
navigation band, not a section with prose, and must never push Zone A below the fold.

**If there is no prototype or project** (pure discussion, research, planning), omit Zone A
entirely and let Zone B be the whole page — no empty placeholder, no apology.

## Medium

A self-contained page published via the Artifact tool. Inline CSS/JS only; no external fonts,
scripts, or images (embed as data URIs). A strict CSP blocks every external host. Theme-aware
(respect `prefers-color-scheme`, good in light and dark). Responsive: relative units, flex/grid,
`max-width:100%`; any wide element (tables, diagrams, code) scrolls inside its own
`overflow-x:auto` container so the page body never scrolls sideways.

---

## Important links

Everything worth clicking, in one compact band below the page header and above Zone A.

You are given the data as JSON (see the keeper instructions for how to refresh it):

```json
{ "available": true,
  "groups": [ { "type": "pull-request", "label": "Pull requests",
                "links": [ { "slug": "#2", "title": "…", "url": "…",
                             "state": "OPEN", "checks": "passing",
                             "review": "none", "current": true } ] } ] }
```

### Structure

**One sub-group per `type`, in the order given** — pull requests, issues, JIRA, commits,
artifacts, references. Label each group with its `label`. Groups are visually distinct (a small
heading, a column, or a bordered cluster) so the eye can jump straight to "the JIRA tickets" or
"the PRs" without reading every entry.

### Anchor on the slug, not the URL

Each link's clickable text is its **`slug`** — `#2`, `PROJ-412`, `9b8d486`, `docs.github.com`.
Slugs are short, scannable, and already meaningful to the reader. Render them in a monospace or
otherwise distinct face so they read as identifiers.

**Never show a raw URL as the link text.** A wall of `https://…` is exactly what this section
exists to replace.

### Titles carry the meaning

Where `title` is non-empty, show it **beside or beneath the slug** as the human-readable
explanation — `#2 · Surface pull requests prominently in the artifact`. The slug is the anchor;
the title is why anyone would click it. Wrap or clamp long titles to two lines rather than
truncating them to a few words.

Where `title` is empty, the slug stands alone. Don't invent a title, and don't pad with
placeholder text like "no title available".

### Status chips (pull requests and issues)

- **State**, colour-coded and legible in both themes:
  `DRAFT` grey · `OPEN` green · `MERGED` purple · `CLOSED` red
- **Checks** when present: `passing` green · `failing` red · `pending` amber · `mixed` amber.
  Omit entirely when `checks` is `none` — don't render "no checks", it's noise.
- **Review** only when meaningful (`APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`). Omit when
  `none`.

Anything marked `current: true` is the item tied to the checked-out branch — give it visible
emphasis (brighter border, accent background, or a small "current" tag).

### When there's nothing

If `available` is `false` or `groups` is empty, **omit the whole section.** Never render an empty
band, a "no links found" placeholder, or an error about `gh` being missing. A session with no
links should look like a page that was never going to have them. Likewise, omit any individual
group that has no entries.

Let groups wrap on narrow screens rather than forcing a horizontal scrollbar on the page body.

---

## Zone A — The Work (primary)

Lead with a compact header: what the thing is, one line, plus a status chip
(prototype / working / partial / broken). Then show it. How depends on the kind:

### `web` — a page, component, or UI

**Embed it live.** Inline the actual markup into a template block and hand it to a sandboxed
iframe. This avoids `srcdoc` attribute-escaping problems entirely:

```html
<script type="text/html" id="proto-src">
  <!-- the prototype's real HTML/CSS/JS, verbatim.
       Write any literal closing script tag as <\/script> -->
</script>
<iframe id="proto" sandbox="allow-scripts" title="Live prototype"
        style="width:100%;height:520px;border:1px solid var(--border);border-radius:8px"></iframe>
<script>
  document.getElementById('proto').srcdoc =
    document.getElementById('proto-src').textContent;
</script>
```

Give the frame a realistic height and caption it with the source filename. If the prototype needs
a build step, external packages, or is larger than ~150KB, do **not** embed — build a faithful
static recreation of its UI instead and show a key source excerpt beside it.

Always pair the embed with a short source excerpt or a one-line description of what the frame
should show, so Zone A still communicates something if the frame comes up empty in a given
viewer. Zone A must never render as a blank box.

### `cli` — a command-line tool or script

Render a terminal panel: the invocation, then real output in a monospace block styled like a
terminal. Add a small diagram of the flow if there are stages. Show actual observed output.

### `library` / `api` — code others call

Show the public surface: function or endpoint signatures as cards, each with a one-line purpose
and a minimal usage example. Diagram the module layout or request/response shape.

### `data` / `pipeline`

Diagram the flow (source → transform → sink) as inline SVG. Show a small sample of real records
in a scrollable table, plus headline stats (row counts, pass/fail, timings) as stat tiles.

### `design` / `doc`

Render the artifact itself — the layout, the structure, the document skeleton — as the visual.

**Truthfulness rule for Zone A:** show what the code actually is and does. Never invent output,
fake a passing test, or render a polished version of something that doesn't work yet. If it's
half-built, show it half-built and let the status chip say so.

---

## Zone B — The Conversation (secondary)

Separated from Zone A by a clear boundary (rule, heading, background shift). Keep it visual and
terse — this is the story, not a transcript.

- A **timeline / journey**: one node per meaningful turn or phase, in order. Zone B's backbone.
- **Decision cards**: key choices, forks taken, questions answered. Prefer cards, chips, and
  badges over paragraphs.
- **Diagrams** for anything structural discussed but not yet built. Inline SVG only — never rely
  on a CDN, and only use `<pre class="mermaid">` if you also inline a working mermaid runtime.
- **Open questions / next steps** panel where it fits.

Keep text terse — labels and short phrases, at most a sentence or two per card. If you're about
to write a paragraph, turn it into a visual instead.

---

## Continuity across turns

You re-render the SAME artifact as the session grows. Update discipline differs by zone:

- **Important links: rebuild from the fresh JSON every turn.** Link state moves on GitHub's
  clock, not the conversation's — a PR can go from open to merged, or checks from pending to
  failing, without anyone mentioning it. Never carry a stale chip forward, and never drop a link
  that's still in the data just because it was mentioned a long time ago.
- **Zone A: replace wholesale** when the prototype changed. It should always reflect the current
  state of the code, not an accumulation of past states.
- **Zone B: append.** Extend the timeline, flip the status chip, add a card. Don't rewrite
  history that's already rendered.

Keep the title and favicon **stable** across every update — pick a topic-fitting favicon emoji on
the first render and keep it. The page should read as one continuous artifact that grew, not a
different page each turn.

## Tone

Clear, a little playful, genuinely useful — a companion visual, not a formal report. If the
conversation turns to a sensitive topic, drop the playfulness and keep it plain and respectful.
