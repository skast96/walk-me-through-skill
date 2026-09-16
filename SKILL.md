---
name: walk-me-through
description: Spoken, section-by-section walkthrough of a superpowers implementation plan in a colleague's voice. Pauses for typed feedback after each section and applies the feedback to the plan file.
argument-hint: [plan-path]
disable-model-invocation: true
---

# Walk Me Through

Explain an implementation plan out loud the way a colleague briefs a teammate before starting work. Speak one section, stop, collect typed feedback, move on. At the end, apply the feedback to the plan file.

This is not read-aloud. Never speak plan text verbatim. Write a spoken briefing for each section and speak that.

## Speaking

Speak a briefing by piping it into the speak script, with the file it should be saved as. Use a Bash timeout of 300000 so long sections finish:

```bash
cat <<'BRIEFING' | "${CLAUDE_SKILL_DIR}/speak.sh" docs/walk-me/<plan-basename>/<NN-name>.mp3
<briefing text>
BRIEFING
```

The script writes the mp3 to that path, keeps it, and blocks until playback ends. If the file already exists and is not empty, the script plays it as is and ignores the text. That is how Repeat works without a second synthesis.

If the script exits non-zero, audio is unavailable for this walkthrough. Then do three things:

- Print the briefing as text instead.
- Tell the user once that audio is off, quoting the script's stderr line as the reason.
- Continue in text mode for every remaining section. Do not retry audio. Keep writing the transcript.

## Saved audio

Every walkthrough leaves its audio in the project so the user can listen again without Claude.

- Folder: `docs/walk-me/<plan-basename>/`, relative to the project root. The plan basename is the plan's file name with its directory and its `.md` extension stripped. For `docs/superpowers/plans/2026-09-16-csv-export.md` that is `docs/walk-me/2026-09-16-csv-export/`.
- If the basename is empty or still contains a `/` or `..`, stop and ask the user for a folder name. Never remove anything outside `docs/walk-me/`.
- Before the first section: remove that folder if it exists. Then create it. A new walkthrough replaces the old audio.
- Before the first section: make sure the project's `.gitignore` contains a line `docs/walk-me/`. Append it if missing. Create `.gitignore` if the project has none. Say in text that you did so.
- File names have three parts: a two digit number in playback order, a hyphen, and a short lowercase name of the section with hyphens between words. Examples in order:
  - `01-overview.mp3`
  - `02-constraints.mp3`
  - `03-csv-formatter.mp3` and one more per task section
  - `NN-risks.mp3`
  - `NN-wrap-up.mp3`
- A Go deeper briefing sits next to its section with a `b` suffix: `03b-csv-formatter-deeper.mp3`.
- Transcript: `transcript.md` in the same folder. After each briefing append a heading with the mp3 file name and the briefing text below it. In text mode the transcript is still written, with the file names the audio would have had.
- At the end, tell the user the folder path in one line and that `mpv <folder>/` replays it in order.

## Procedure

### 1. Find the plan

- If `$ARGUMENTS` names a file, use it.
- If `$ARGUMENTS` names a file that does not exist, ask the user for a path and stop until you have one.
- Otherwise use the most recently modified file in `docs/superpowers/plans/`.
- If that directory does not exist or is empty, ask the user for a path and stop until you have one.
- Read the plan. If its header names a spec file, read the spec too.

### 2. Build the section list

Target four to eight sections, in this order:

1. **Overview.** Goal, the chosen architecture, and why it beat the alternatives. Take the alternatives from the spec if the plan does not name them.
2. **Constraints.** Only if the plan has a Global Constraints section with content.
3. **One section per task.** Merge tasks that cannot be reviewed apart, for example a type definition and its only consumer. Fold very small mechanical tasks (a rename, a config bump, a one line template change) into the neighbour they serve.
4. **Risks and open questions.** Always present, even if the plan lists none. Name what you are least sure about in this plan.

If the plan is not in writing-plans format (no Goal line, no `### Task N` headers), split on its top level headings instead, one section per heading plus the risks section, and say in text that the format is unfamiliar and the split is best effort.

Print the section list as a short numbered list before speaking, so the user knows the shape.

### 3. Walk through each section

For every section:

Only an explicit Continue moves to the next section. Never move on after a comment, a clarification, or a summary of the discussion. Ask again instead.

1. Write the briefing following the register rules below.
2. Speak it into its numbered file and append it to the transcript.
3. Ask with AskUserQuestion. Question: "Any thoughts on this part?" Options, in this order:
   - **Continue** - the user is finished with this section. Move to the next one.
   - **Repeat** - run the same speak command again. The file exists, so it is replayed. Then ask again.
   - **Go deeper** - write and speak a second briefing on the same section into its `b` file, up to 250 words, covering the individual steps, the interfaces, and what the tests check. Then ask again.
   - The built in Other field is where the user types comments.
4. When the user types a comment:
   - Record it together with the section and the task it belongs to.
   - If the comment could mean two different changes, ask one typed clarification. Do not speak the clarification.
   - If it contradicts an earlier comment, ask which one wins.
   - Confirm in one or two text sentences what you recorded.
   - Then ask the same question again. The user may have more to say about this section.

### 4. Wrap up

1. If there were no comments, speak one sentence saying so into the wrap up file, name the audio folder, and stop.
2. Otherwise write and speak a wrap up briefing into the wrap up file: every change the user asked for, one sentence each, in plan order. Under 150 words.
3. Edit the plan file:
   - Keep the writing-plans structure: task headers, Files, Interfaces, checkbox steps.
   - Change only the sections the user commented on.
   - A new task gets the same bite sized steps as its neighbours: failing test, run, implement, run, commit.
   - If a comment changes the design rather than the plan, apply the plan side and add a note in your text summary that the spec needs the same change. Never edit the spec.
4. Print a text summary of what changed, section by section, and name the audio folder.
5. If a change invalidates other tasks, for example a removed interface that three later tasks consume, say so in text and recommend rerunning writing-plans instead of patching.

## Register rules for briefings

- First person, present tense. "I want to", "my plan is", "I am not sure about".
- Each briefing covers, in this order: what this part does, why this way, the risky or uncertain bit, and a real question to the listener. End on the question.
- 60 to 150 words. A Go deeper briefing may reach 250.
- No file paths, function names, shell commands, or markdown. Describe them in words. Say "the speak script", not `speak.sh`. Say "the export handler", not `admin/export.go`.
- Refer to tasks by what they do, never by number.
- Write numbers and acronyms the way you would say them. "two million rows", "the H T T P endpoint" or better "the web endpoint".
- Rejected alternatives get one sentence on why they lost. This is where the listener's input matters most.
- No filler openers, no praise of the plan, no "great question".
- One idea per sentence. Short sentences read better aloud.

## Example briefing

For the overview of a plan that adds CSV export by streaming:

> I want to add a C S V export of the orders table to the admin dashboard. My plan splits it into three parts. A small formatting function that turns order rows into C S V text, a web endpoint that streams that text as a download, and a button on the dashboard. I chose streaming over building the whole file in memory because the table has two million rows and I do not want a request to hold all of that. The part I am least sure about is the batch size for streaming. I picked one thousand rows per batch without measuring. Does streaming match what you had in mind, or would you rather export in the background and email a link?
