# walk-me-through

A Claude Code skill that explains a superpowers implementation plan out loud.
It speaks like a colleague briefing you, not like a screen reader.
It goes section by section. After each section it stops and waits for your
typed feedback. At the end it applies your feedback to the plan file.

## Install

### Let Claude do it

Paste this into Claude Code on the new machine:

> Install the Claude Code skill from https://github.com/skast96/walk-me-through-skill.
>
> 1. Run `npx skills add skast96/walk-me-through-skill -g -a claude-code -y`.
> 2. If that fails, git clone the repository to `~/.claude/skills/walk-me-through`.
> 3. Run `~/.claude/skills/walk-me-through/install.sh`.
> 4. Show me its output.
> 5. Remind me to restart Claude Code.

### By hand, with the skills CLI

```
npx skills add skast96/walk-me-through-skill -g -a claude-code -y
~/.claude/skills/walk-me-through/install.sh
```

Update later on any machine with `npx skills update -g`.

### By hand, with git

```
git clone https://github.com/skast96/walk-me-through-skill.git ~/.claude/skills/walk-me-through
~/.claude/skills/walk-me-through/install.sh
```

Update later with `git pull` in that directory.

### What install.sh does

- Reads which speech engine you configured. See Speech engine below. Default is the `edge` engine.
- For edge-tts: checks that `uv` is available and installs `edge-tts` as a uv tool.
- For Kokoro: checks that `curl` is available and that the Kokoro server answers.
- Checks that `mpv` is available and names the package if not.
- Speaks one test sentence so you hear that audio works.

Restart Claude Code after installing. Skills are read at startup.

## Use

In a Claude Code session, in a project that has a plan:

```
/walk-me-through docs/superpowers/plans/2026-09-16-my-feature.md
```

Without a path the skill takes the newest file in `docs/superpowers/plans/`.

Claude speaks the plan in four to eight sections. After each one you get a prompt with these choices:

- Continue
- Repeat
- Go deeper
- A free text field for your comments

At the end Claude does three things:

- It summarizes your comments.
- It edits the plan file.
- It prints what changed.

The skill never starts on its own. You always invoke it by hand.

## Listen again

Every briefing is saved as an mp3 in the project, next to a transcript:

```
docs/walk-me/2026-09-16-my-feature/
  01-overview.mp3
  02-constraints.mp3
  03-csv-formatter.mp3
  ...
  transcript.md
```

Replay the whole walkthrough in order with any player, for example:

```
mpv docs/walk-me/2026-09-16-my-feature/
```

The skill adds `docs/walk-me/` to the project's `.gitignore`, so the audio stays local. The next walkthrough of the same plan replaces the folder.

## Speech engine

Two engines are supported. You pick one per machine. There is no fallback: if the chosen engine is not available, speaking fails with a message that names the problem and the walkthrough continues as text.

- `edge`: Microsoft's online voices through edge-tts. Default. Needs network.
- `kokoro`: a local Kokoro-FastAPI server, for example the FastKoko Docker container. Faster and offline.

Four environment variables, all optional.

| Variable | Default | Meaning |
|---|---|---|
| `WALK_ME_THROUGH_TTS` | `edge` | `edge` or `kokoro` |
| `WALK_ME_THROUGH_VOICE` | `en-US-AndrewMultilingualNeural` for edge, `af_heart` for kokoro | A voice name of the chosen engine |
| `WALK_ME_THROUGH_RATE` | `+0%` | Speech rate as a whole percent, for example `+15%`. Kokoro receives it as speed `1.15`. |
| `WALK_ME_THROUGH_KOKORO_URL` | `http://localhost:8880` | Base URL of the Kokoro server |

Set them in the `env` block of `~/.claude/settings.json`. Claude Code passes that block to every command it runs, on every project, so the skill sees it wherever it is invoked:

```json
{
  "env": {
    "WALK_ME_THROUGH_TTS": "kokoro",
    "WALK_ME_THROUGH_VOICE": "am_adam"
  }
}
```

Run `install.sh` again after changing the engine. It checks the new engine and speaks a test sentence.

List edge-tts voices with `edge-tts --list-voices`. List Kokoro voices with `curl http://localhost:8880/v1/audio/voices`. Kokoro also takes mixes such as `af_bella(2)+af_sky(1)`.

## Requirements

- Claude Code
- Node with npx for the skills CLI install path. The git path does not need it.
- `mpv` for playback
- For the edge engine: `uv` for installing edge-tts, and network access while speaking.
  edge-tts uses Microsoft's online voices. Without network the walkthrough falls back to text.
- For the kokoro engine: `curl`, and a running Kokoro-FastAPI server such as
  [FastKoko](https://github.com/remsky/Kokoro-FastAPI). The server is not started by this skill.

## Layout

```
SKILL.md      the skill: procedure and spoken-register rules
speak.sh      text on stdin to speech
install.sh    one-time setup
tests/        shell tests and a fixture plan
docs/         design spec and implementation plan
```
