# walk-me-through: Spoken Plan Walkthrough Skill

**Date:** 2026-09-16
**Status:** approved design, awaiting implementation plan

## Purpose

`walk-me-through` is a personal Claude Code skill. It explains a superpowers
implementation plan out loud, the way a colleague would brief you before
starting work. It goes section by section. After each section it stops and
waits for typed feedback. At the end it applies the feedback to the plan file.

It is not a read-aloud tool. The plan text is never spoken verbatim. Claude
writes a short spoken briefing per section and speaks that.

## Non-goals

- No spoken input. Feedback is typed. Voice input may come later by swapping
  the speak step for a conversational MCP server such as voicemode.
- No hooks in `settings.json`. The skill drives every step itself.
- No patching of the superpowers plugin. The writing-plans skill stays as is.
- No automatic invocation. Claude does not offer or start the walkthrough.
  The user runs `/walk-me-through` by hand.
- No support for plans outside the writing-plans format. Other markdown is
  best effort only.

## Repository layout

The git repository is the skill directory. Installing on a new machine is a
clone into the personal skills directory.

```
~/.claude/skills/walk-me-through/
  SKILL.md              the skill: trigger, flow, briefing rules
  speak.sh              text on stdin -> edge-tts -> mpv
  install.sh            installs edge-tts via uv, checks mpv and audio
  README.md             what it is, install, usage, voice override
  docs/superpowers/specs/   this document
  docs/superpowers/plans/   implementation plan
  tests/
    fixture-plan.md     a small plan in writing-plans format
    test-speak.sh       tests for speak.sh
```

The skill name is `walk-me-through`. The repository name on GitHub is
`walk-me-through-skill`. Both install paths in the Installation section put
it under `~/.claude/skills/walk-me-through/`.

## Component: speak.sh

Contract:

- Reads UTF-8 text from stdin.
- Takes one optional argument, the output mp3 path.
- Without the argument, renders with `edge-tts` to an mp3 in a temporary file.
- With the argument, renders to that path, creating parent directories, and
  keeps the file. If the file already exists and is not empty, plays it as is
  and ignores stdin. A failed synthesis removes the partial file.
- Plays the mp3 with `mpv --no-video --really-quiet`.
- Blocks until playback ends. This is what makes the skill wait.
- Exits 0 on success. Exits non-zero if `edge-tts` is missing, the network
  call fails, or `mpv` is missing. It prints one short reason to stderr.
- Deletes the temporary file afterwards.

Configuration:

- `WALK_ME_THROUGH_VOICE` selects the edge-tts voice. Default is
  `en-US-AndrewMultilingualNeural`.
- `WALK_ME_THROUGH_RATE` passes through to edge-tts `--rate`. Default `+0%`.
- Nothing else is configurable.

There is no way to skip a section while it plays. The skill runs the script
through Claude's Bash tool, which has no terminal attached, so mpv keyboard
input does not work. Sections are kept short instead. mpv gets
`</dev/null` so it never waits on input.

Temporary files go to `${TMPDIR:-/tmp}` via `mktemp`. The skill does not
depend on the Claude Code scratchpad path.

## Component: SKILL.md

Frontmatter: `name: walk-me-through`, a `description`,
`argument-hint: [plan-path]`, and `disable-model-invocation: true`. No other
fields. The `name` must equal the directory name so the skills CLI and a
manual clone produce the same command, `/walk-me-through`. The
`disable-model-invocation` flag means Claude never starts the walkthrough on
its own. The user always invokes it by hand.

### Trigger

Manual only. The user types `/walk-me-through <plan path>`. The plan path is
optional. Without it, the skill uses the most recently modified file in
`docs/superpowers/plans/`. If that directory does not exist or is empty, it
asks for a path. A path that names a missing file also leads to that
question.

There is no automatic offer after writing-plans and no matching on phrases.

### Flow

1. Read the plan. If the header names a spec, read the spec too.
2. Build the section list. Target four to eight sections:
   - Overview: goal, the chosen architecture, and why it beat the
     alternatives.
   - Global constraints, if the plan has any.
   - One section per task. Tasks that are tightly coupled (one cannot be
     reviewed without the other) are merged into one section. Very small
     mechanical tasks (rename, config bump) are folded into a neighbour.
   - Risks and open questions. This section always exists, even if the plan
     lists none. Claude names what it is least sure about.
3. For each section:
   - Write the spoken briefing following the register rules below.
   - Pipe it to `speak.sh`.
   - If `speak.sh` fails, print the briefing as text and continue. Say once,
     in text, that audio is off for this walkthrough.
   - Ask the user with `AskUserQuestion`. Options: Continue, Repeat, Go
     deeper. The built-in Other field is where comments are typed.
   - "Go deeper" speaks a second briefing about the same section with more
     detail on the steps and interfaces, then asks again.
   - A typed comment is recorded together with the section it belongs to.
     If the comment is ambiguous, ask one typed clarification before moving
     on. Then continue to the next section.
4. Wrap-up:
   - Speak a short summary of every change the user asked for. If there were
     none, say so and stop.
   - Edit the plan file to apply the changes. Match the writing-plans format.
     Do not rewrite sections the user did not comment on.
   - Print a text summary of what changed in the plan, section by section.
   - If a change is large enough to invalidate other tasks, say so and
     recommend re-running writing-plans instead of patching.

### Register rules for the spoken briefing

- First person, present tense. "I want to", "my plan is", "I am not sure".
- Every section covers: what, why, the risky or uncertain part, and ends with
  a real question to the listener.
- 60 to 150 words per section. A "Go deeper" briefing may go to 250.
- No file paths, code, shell commands, or markdown syntax. Describe them in
  words. "the speak script" instead of `speak.sh`.
- Refer to tasks by what they do, never by number.
- Spell out numbers and acronyms the way you would say them.
- Rejected alternatives get one sentence on why they were rejected. This is
  where the listener's input is most valuable.
- No filler openers and no praise of the plan.

### Saved audio

Every briefing is kept as an mp3 in the project so the user can replay the
walkthrough with any player and without Claude.

- Folder: `docs/walk-me/<plan-basename>/` relative to the project root.
- Before the first section the skill removes an existing folder for that plan
  and creates it fresh. A new walkthrough replaces the old audio.
- Before the first section the skill ensures the project's `.gitignore` has
  the line `docs/walk-me/`, creating the file if needed, and says so in text.
- File names: two digit playback order, hyphen, short lowercase hyphenated
  section name. `01-overview.mp3`, `02-constraints.mp3`, then one per task
  section, then `NN-risks.mp3` and `NN-wrap-up.mp3`. A Go deeper briefing is
  `NNb-<name>-deeper.mp3`.
- Repeat runs the same speak command. The file exists, so speak.sh replays it
  without synthesis.
- `transcript.md` in the folder holds every briefing under a heading with its
  file name. It is written in text mode too.
- At the end the skill names the folder and the replay command
  `mpv <folder>/`.

### Applying feedback

Feedback is applied to the plan file only, never to the spec. Changes that
touch the design rather than the plan are reported back with a note that the
spec should be updated separately.

Each applied change keeps the plan's own structure: task headers, Files,
Interfaces, and numbered steps. New tasks get the same bite-sized steps as
existing ones.

## Installation on a new machine

Two supported paths. Both end with the skill at
`~/.claude/skills/walk-me-through/` and both need `install.sh` once.

### Path 1: skills CLI (primary)

The [skills CLI](https://github.com/vercel-labs/skills) is the current
cross-agent standard for installing a skill from a git repository. It
discovers the root `SKILL.md`, installs a canonical copy, and symlinks it into
`~/.claude/skills/<name>/`. The `<name>` comes from the frontmatter `name`
field, so that field must be `walk-me-through` to match the manual clone path.

```
npx skills add skast96/walk-me-through-skill -g -a claude-code -y
~/.claude/skills/walk-me-through/install.sh
```

Updates on every machine: `npx skills update -g`.

### Path 2: git clone (fallback)

For machines without Node, or when the CLI is not wanted:

```
git clone git@github.com:skast96/walk-me-through-skill.git ~/.claude/skills/walk-me-through
~/.claude/skills/walk-me-through/install.sh
```

Updates: `git pull` in that directory.

### Agent install block in the README

The README carries a short block the user pastes into Claude Code on a new
machine. Claude then performs the install itself. Wording along these lines:

> Install the Claude Code skill from
> https://github.com/skast96/walk-me-through-skill. Run
> `npx skills add skast96/walk-me-through-skill -g -a claude-code -y`. If that
> fails, git clone the repo to `~/.claude/skills/walk-me-through`. Then run
> `~/.claude/skills/walk-me-through/install.sh`, show me its output, and
> remind me to restart Claude Code.

This block is the first thing under the README's install heading. The two
manual paths follow it for people who prefer to run the commands themselves.

### install.sh

- Resolves its own directory through the symlink, since Path 1 installs a
  symlink. Uses `readlink -f` on `$0`.
- Checks for `uv`. Prints the uv install one-liner and exits if missing.
- Runs `uv tool install edge-tts` if the `edge-tts` command is missing.
- Checks for `mpv`. Prints the distro package hint and exits if missing.
- Speaks one test sentence so the user hears it works.
- Reminds the user to restart Claude Code so the new skill is picked up.

## Error handling

| Situation | Behaviour |
|---|---|
| `edge-tts` not installed | `speak.sh` exits 1. Skill falls back to text. |
| No network | `speak.sh` exits 1 after edge-tts fails. Skill falls back to text. |
| `mpv` missing | `speak.sh` exits 1. Skill falls back to text. |
| Plan not in writing-plans format | Skill still splits on top-level headings and says the format is unfamiliar. |
| No plan path and no plans directory | Skill asks for a path. |
| Plan path given but the file does not exist | Skill asks for a path. |
| Plans directory exists but is empty | Skill asks for a path. |
| Audio folder cannot be created | `speak.sh` exits 1. Skill falls back to text. Transcript is still attempted. |
| Feedback contradicts an earlier comment | Skill asks which one wins before applying. |

## Testing

`tests/test-speak.sh`:

- Given a short sentence, `speak.sh` exits 0 and the temporary file is gone
  afterwards. Playback is allowed to be audible.
- With `PATH` stripped of `edge-tts`, `speak.sh` exits non-zero and prints a
  reason on stderr.
- With `PATH` stripped of `mpv`, same.
- With an output path in a fresh directory, the mp3 exists afterwards and the
  temporary directory is empty.
- With an output path that already exists and `PATH` stripped of `edge-tts`,
  the file is played and the exit code is 0.

Skill dry run against `tests/fixture-plan.md`:

- The fixture is a plan with an overview, constraints, three tasks, and no
  risk section.
- Expected: six sections, or fewer if tasks were merged. Overview,
  constraints, one per task, plus the always-present risks section.
- Each spoken briefing ends with a question mark.
- A typed comment on task two results in an edit inside task two only.
- With `speak.sh` made to fail, the walkthrough completes in text mode and
  says so once.

The skill dry run is a manual test performed by running the skill in a
Claude Code session and checking the outcomes above. Skill behaviour cannot
be unit tested from a shell.

## Decisions and rejected alternatives

- **Skill drives everything, not hooks.** A Stop hook speaks whatever the
  last message was. It cannot pause per section or collect feedback per
  section. Rejected.
- **Existing read-aloud tools rejected.** claude-speak, claude-vox and
  similar speak Claude's output. None of them produce a briefing or a
  per-section pause. They solve a different problem.
- **voicemode MCP rejected for now.** It offers speak-then-listen, which fits
  the flow, but requires Kokoro, Whisper and an audio input stack on every
  machine. Typed feedback is enough for the first version. The speak step is
  one command so swapping later is cheap.
- **edge-tts over piper and espeak-ng.** Natural voice, no key, one-line
  install. Cost: needs network while speaking. Acceptable because the
  fallback is text.
- **Feedback edits the plan directly.** A separate notes file would need a
  second pass to apply. Editing directly keeps the plan the single source of
  truth for executors.
- **Audio is saved per section and ignored by git.** A folder of numbered
  mp3s replays in any player with real keyboard controls, which is the cheap
  answer to in-session playback controls. Ignored by git because the files
  are regenerable from the plan and cost about fifty kilobytes per section.
- **Repository is the skill directory, root `SKILL.md`.** This is the layout
  the skills CLI discovers, and it also works with a plain git clone. No
  plugin marketplace is needed for one person on several machines. A
  marketplace plugin can be added later if the skill is shared more widely.
- **skills CLI as primary install.** It is the current cross-agent standard
  (agentskills.io) and gives one-command updates on every machine. Git clone
  stays documented as the no-Node fallback.
