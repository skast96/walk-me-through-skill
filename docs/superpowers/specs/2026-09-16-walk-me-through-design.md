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

The skill name is the directory name, `walk-me-through`. The repository name
on GitHub is `walk-me-through-skill`. The clone command renames it.

## Component: speak.sh

Contract:

- Reads UTF-8 text from stdin.
- Renders it with `edge-tts` to an mp3 in a temporary file.
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

Pressing `q` in mpv stops playback of the current section. The script still
exits 0. The skill treats this as "skip the rest of this section".

Temporary files go to `${TMPDIR:-/tmp}` via `mktemp`. The skill does not
depend on the Claude Code scratchpad path.

## Component: SKILL.md

### Trigger

The description matches when:

- the user types `/walk-me-through <plan path>` or says "walk me through the
  plan", "explain the plan to me", "brief me on the plan"
- a plan was just saved by writing-plans. The skill instructs Claude to offer
  the walkthrough as a third option next to the two execution options.

If no plan path is given, the skill uses the most recently modified file in
`docs/superpowers/plans/`. If that directory does not exist, it asks for a
path.

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

### Applying feedback

Feedback is applied to the plan file only, never to the spec. Changes that
touch the design rather than the plan are reported back with a note that the
spec should be updated separately.

Each applied change keeps the plan's own structure: task headers, Files,
Interfaces, and numbered steps. New tasks get the same bite-sized steps as
existing ones.

## Installation on a new machine

```
git clone git@github.com:skast96/walk-me-through-skill.git ~/.claude/skills/walk-me-through
~/.claude/skills/walk-me-through/install.sh
```

`install.sh`:

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
| User presses `q` in mpv | Playback stops, exit 0. Skill asks the question as normal. |
| Plan not in writing-plans format | Skill still splits on top-level headings and says the format is unfamiliar. |
| No plan path and no plans directory | Skill asks for a path. |
| Feedback contradicts an earlier comment | Skill asks which one wins before applying. |

## Testing

`tests/test-speak.sh`:

- Given a short sentence, `speak.sh` exits 0 and the temporary file is gone
  afterwards. Playback is allowed to be audible.
- With `PATH` stripped of `edge-tts`, `speak.sh` exits non-zero and prints a
  reason on stderr.
- With `PATH` stripped of `mpv`, same.

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
- **Repository is the skill directory.** Enables clone-to-install on several
  machines without a plugin marketplace. A marketplace plugin can be added
  later if the skill is shared beyond one person.
