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
- For edge: checks that `uv` is available and installs `edge-tts` as a uv tool.
- For kokoro: checks Docker and pulls the Kokoro-FastAPI CPU image.
- For pocket: checks Docker and builds a small pocket-tts image from the `docker/pocket` folder.
- Checks that `mpv` is available and names the package if not.
- Starts the engine, speaks one test sentence so you hear that audio works, and stops the engine again.

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

Every briefing is saved as an audio file in the project, next to a transcript. The extension is `.mp3`, or `.wav` with the pocket engine:

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

Three engines are supported. You pick one per machine. There is no fallback: if the chosen engine does not work, speaking fails with a message that names the problem and the walkthrough continues as text.

| Engine | What it is | Runs where |
|---|---|---|
| `edge` | Microsoft's online voices through edge-tts. Default. Needs network. | On the host, as a uv tool |
| `kokoro` | [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI), CPU image | Docker container on port 8880 |
| `pocket` | [pocket-tts](https://github.com/kyutai-labs/pocket-tts) by Kyutai, CPU | Docker container on port 8000 |

The skill manages the container itself. It starts the container before the first section, waits until the engine answers, and stops it at the end of the walkthrough. A container that is already running is reused. If a walkthrough is interrupted, the container stays up until the next walkthrough or until you run the stop command by hand:

```
~/.claude/skills/walk-me-through/engine.sh stop
```

The pocket model lives in the Docker volume `walk-me-through-pocket-cache`, so it is downloaded once. Remove it with `docker volume rm walk-me-through-pocket-cache` if you want the disk space back.

Three environment variables, all optional.

| Variable | Default | Meaning |
|---|---|---|
| `WALK_ME_THROUGH_TTS` | `edge` | `edge`, `kokoro` or `pocket` |
| `WALK_ME_THROUGH_VOICE` | `en-US-AndrewMultilingualNeural` for edge, `af_heart` for kokoro, the built-in voice for pocket | A voice name of the chosen engine |
| `WALK_ME_THROUGH_RATE` | `+0%` | Speech rate as a whole percent, for example `+15%`. Kokoro receives it as speed `1.15`. Pocket ignores it. |

Set them in the `env` block of `~/.claude/settings.json`. Claude Code passes that block to every command it runs, on every project, so the skill sees it wherever it is invoked:

```json
{
  "env": {
    "WALK_ME_THROUGH_TTS": "pocket",
    "WALK_ME_THROUGH_VOICE": "marius"
  }
}
```

Run `install.sh` again after changing the engine. It fetches what the new engine needs and speaks a test sentence.

Voices:

- edge: `edge-tts --list-voices`
- kokoro: `curl http://localhost:8880/v1/audio/voices` while the container runs. Mixes such as `af_bella(2)+af_sky(1)` work.
- pocket: the built-in names from the [pocket-tts README](https://github.com/kyutai-labs/pocket-tts#the-generate-command), for example `alba`, `marius`, `george`. Leave the variable unset for the model's own default voice.

## Requirements

- Claude Code
- Node with npx for the skills CLI install path. The git path does not need it.
- `mpv` for playback
- For the edge engine: `uv` for installing edge-tts, and network access while speaking.
  edge-tts uses Microsoft's online voices. Without network the walkthrough falls back to text.
- For the kokoro and pocket engines: Docker, usable by your user, and `curl`.
  The Kokoro image is about three gigabytes. The pocket image is under two gigabytes plus its model.

## Layout

```
SKILL.md      the skill: procedure and spoken-register rules
speak.sh      text on stdin to speech
engine.sh     starts and stops the engine's container
install.sh    one-time setup
docker/       Dockerfile for the pocket engine
tests/        shell tests and a fixture plan
docs/         design spec and implementation plan
```
