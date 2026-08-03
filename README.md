# ai-skills

A [Claude Code](https://code.claude.com) plugin marketplace containing **kyles-got-skills**, a
collection of skills for Claude Code.

## Install

```bash
claude plugin marketplace add ScreamingSum12/ai-skills
claude plugin install kyles-got-skills@ai-skills
```

Restart Claude Code afterward so the skills load.

## What's inside

| Skill | Invoke | What it does |
|---|---|---|
| **artifact-mode** | `/kyles-got-skills:artifact-mode` | Keeps a living, visual claude.ai artifact in sync with your session — the prototype you're building rendered as the primary visualization up top, the conversation's story below it. [Full guide →](docs/artifact-mode.md) |

## Requirements

- **Claude Code** with plugin marketplace support. Developed and tested against `2.1.220`.
- **`jq`** — a hard dependency of artifact-mode's scripts. `brew install jq` on macOS.
- **bash**, and a macOS or Linux host. The session-location logic reads Claude Code's transcript
  directory layout and has not been tested on Windows.

## Repository layout

```
.claude-plugin/
  marketplace.json           # marketplace manifest — lists the plugins below
plugins/
  kyles-got-skills/
    .claude-plugin/
      plugin.json            # plugin manifest
    skills/
      artifact-mode/
        SKILL.md             # the skill itself (instructions Claude reads)
        assets/              # scripts and prompts the skill calls
docs/
  artifact-mode.md           # human-facing guide
```

Two manifests are involved, and they are different things: `marketplace.json` advertises which
plugins exist and where to find them, while each plugin's `plugin.json` describes that one
plugin. Both must agree on the plugin's `name` and `version`.

## Updating

```bash
claude plugin marketplace update ai-skills
claude plugin update kyles-got-skills@ai-skills
```

If you're developing against a local checkout instead of GitHub, point the marketplace at the
directory — it reads straight from your working tree, so edits show up on the next
`marketplace update`:

```bash
claude plugin marketplace add /path/to/ai-skills
```

Bump `version` in **both** `plugin.json` and `marketplace.json` when publishing a change. The
install cache is keyed on it, and a stale version can leave users on old files.

## Adding a skill

1. Create `plugins/kyles-got-skills/skills/<skill-name>/SKILL.md` with YAML frontmatter:

   ```yaml
   ---
   name: your-skill
   description: What it does, and the phrases that should trigger it.
   ---
   ```

2. Put any scripts or supporting prompts in an `assets/` directory beside it. Reference them from
   SKILL.md with `${CLAUDE_PLUGIN_ROOT}`, which Claude Code expands to the installed plugin root
   before the model reads the file:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/your-skill/assets/do-thing.sh
   ```

   Never hardcode `~/.claude/skills/...` — that path doesn't exist for a plugin install.

3. Validate both manifests before committing:

   ```bash
   claude plugin validate .
   claude plugin validate plugins/kyles-got-skills
   ```

### Naming: skills are always namespaced

A plugin skill is invoked as `<plugin-name>:<skill-name>`, and **no manifest field suppresses the
prefix**. That's why the plugin is named for the collection (`kyles-got-skills`) rather than for
any one skill — a plugin named `artifact-mode` holding a skill named `artifact-mode` surfaces as
the redundant `/artifact-mode:artifact-mode`. This mirrors the convention Anthropic uses for its
own bundles (`anthropic-skills:docx`, `anthropic-skills:pdf`).

Note that `plugin.json` accepts no `displayName` key — `claude plugin validate` rejects it.

## License

[MIT](LICENSE)
