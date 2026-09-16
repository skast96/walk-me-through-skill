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
git clone git@github.com:skast96/walk-me-through-skill.git ~/.claude/skills/walk-me-through
~/.claude/skills/walk-me-through/install.sh
```

Update later with `git pull` in that directory.

### What install.sh does

- Checks that `uv` is available and tells you how to get it if not.
- Installs `edge-tts` as a uv tool.
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

## Voice

Two environment variables, both optional. Set them in your shell profile.

| Variable | Default | Meaning |
|---|---|---|
| `WALK_ME_THROUGH_VOICE` | `en-US-AndrewMultilingualNeural` | An edge-tts voice name |
| `WALK_ME_THROUGH_RATE` | `+0%` | Speech rate, for example `+15%` |

List voices with `edge-tts --list-voices`.

## Requirements

- Claude Code
- `uv` for installing edge-tts
- `mpv` for playback
- Network access while speaking. edge-tts uses Microsoft's online voices.
  Without network the walkthrough falls back to text.

## Layout

```
SKILL.md      the skill: procedure and spoken-register rules
speak.sh      text on stdin to speech
install.sh    one-time setup
tests/        shell tests and a fixture plan
docs/         design spec and implementation plan
```
