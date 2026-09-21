---
name: walk-me-through
description: Spoken, section-by-section walkthrough of a superpowers implementation plan in a colleague's voice. Pauses for typed feedback after each section, talks back, and applies the feedback to the plan file.
argument-hint: [plan-path]
disable-model-invocation: true
---

# Walk Me Through

Explain an implementation plan out loud the way a colleague briefs a teammate before starting work. Speak one section, stop, collect typed feedback, answer it out loud, move on. At the end, apply the feedback to the plan file.

This is not read-aloud. Never speak plan text verbatim. Write a spoken briefing for each section and speak that.

Everything you say during the walkthrough is spoken. Briefings, replies to comments, clarifying questions, and the wrap up all go through the same two steps below. Do not also print spoken text in the session. It lands in the transcript, and printing it twice costs tokens. The only text that is not spoken is bookkeeping: the section list, the AskUserQuestion prompt, the audio-off notice, and the final summary of plan edits.

## Speaking

The speech engine is configured per machine. Two of the engines run in a Docker container that this skill starts and stops:

- Before the first section, run `"${CLAUDE_SKILL_DIR}/engine.sh" start` with a Bash timeout of 600000. The script gives up after five minutes on its own, so the longer tool timeout lets its message through. With the default engine it returns at once. Otherwise it starts the container and waits until the engine answers.
- If it exits non-zero, audio is unavailable for this walkthrough. Follow the three text mode steps below, quoting its stderr line as the reason.
- The last step of every walkthrough, text mode included, is `"${CLAUDE_SKILL_DIR}/engine.sh" stop`.

Speaking a text always means two steps, in this order:

1. Append it to the transcript. See Saved audio for the format.
2. Pipe it into the speak script, with the path it should be saved under, without extension. Use a Bash timeout of 300000 so long sections finish:

```bash
cat <<'BRIEFING' | "${CLAUDE_SKILL_DIR}/speak.sh" docs/walk-me/<plan-basename>/<NN-name>
<briefing text>
BRIEFING
```

Step 1 comes before step 2 because the speak script blocks until playback ends. The transcript is complete even if playback fails.

The script appends `.mp3`, or `.wav` with the pocket engine, writes the audio there, keeps it, and blocks until playback ends. If that file already exists and is not empty, the script plays it as is and ignores the text. That is how Repeat works without a second synthesis.

If the speak script exits non-zero, audio is unavailable for this walkthrough. Then do three things:

- Print the text in the session instead.
- Tell the user once that audio is off, quoting the script's stderr line as the reason.
- Skip step 2 for every remaining text and print each one instead. Do not retry audio. Step 1 still happens for every text.

## Saved audio

Every walkthrough leaves its audio in the project so the user can listen again without Claude.

- Folder: `docs/walk-me/<plan-basename>/`, relative to the project root. The plan basename is the plan's file name with its directory and its `.md` extension stripped. For `docs/superpowers/plans/2026-09-16-csv-export.md` that is `docs/walk-me/2026-09-16-csv-export/`.
- If the basename is empty or still contains a `/` or `..`, stop and ask the user for a folder name. Never remove anything outside `docs/walk-me/`.
- Before the first section: remove that folder if it exists. Then create it. A new walkthrough replaces the old audio.
- Before the first section: make sure the project's `.gitignore` contains a line `docs/walk-me/`. Append it if missing. Create `.gitignore` if the project has none. Say in text that you did so.
- File names have three parts: a two digit number in playback order, a hyphen, and a short lowercase name of the section with hyphens between words. The extension is `.mp3`, or `.wav` with the pocket engine. Examples in order:
  - `01-overview.mp3`
  - `02-constraints.mp3`
  - `03-csv-formatter.mp3` and one more per task section
  - `NN-risks.mp3`
  - `NN-wrap-up.mp3`
- Extra audio within a section gets a letter suffix after the number, in the order it happened, starting at `b`. Directory playback then follows the conversation. The last word says what it is: `deeper` for a Go deeper briefing, `reply` for an answer to a comment. For example:
  - `03b-csv-formatter-reply.mp3`
  - `03c-csv-formatter-deeper.mp3`
  - `03d-csv-formatter-reply.mp3`
- Transcript: `transcript.md` in the same folder. Before each speak call append a heading with the file name without its extension and the text below it. For a reply, put the user's comment first as a quoted line, then the reply. In text mode the transcript is still written, with the file names the audio would have had.
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

Only an explicit Continue moves to the next section. Never move on after a comment, a reply, or a clarification. Ask again instead.

1. Write the briefing following the register rules below.
2. Speak it into its numbered file. Speaking includes appending it to the transcript.
3. Ask with AskUserQuestion. Question: "Any thoughts on this part?" Options, in this order:
   - **Continue** - the user is finished with this section. Move to the next one.
   - **Repeat** - run the same speak command again. The file exists, so it is replayed. Then ask again.
   - **Go deeper** - write and speak a second briefing on the same section into the section's next lettered file, up to 250 words, covering the individual steps, the interfaces, and what the tests check. Then ask again.
   - The built in Other field is where the user types comments.
4. When the user types a comment:
   - Write a reply following the reply rules below. Speak it into the section's next lettered `reply` file. Speaking includes appending it, with the comment, to the transcript.
   - Once the point is settled, record the comment together with the section, the task it belongs to, and the outcome of the exchange. "Switch to an in memory export because the table is capped at fifty thousand rows" is a recorded comment. "Switch to an in memory export" alone loses the reason.
   - Then ask the same question again. The user may have more to say about this section.

### 4. Wrap up

1. If there were no comments, speak one sentence saying so into the wrap up file, name the audio folder, and skip to the last step.
2. Otherwise write and speak a wrap up briefing into the wrap up file: every change the user asked for, one sentence each, in plan order. Under 150 words.
3. Edit the plan file:
   - Keep the writing-plans structure: task headers, Files, Interfaces, checkbox steps.
   - Change only the sections the user commented on.
   - A new task gets the same bite sized steps as its neighbours: failing test, run, implement, run, commit.
   - If a comment changes the design rather than the plan, apply the plan side and add a note in your text summary that the spec needs the same change. Never edit the spec.
4. Print a text summary of what changed, section by section, and name the audio folder.
5. If a change invalidates other tasks, for example a removed interface that three later tasks consume, say so in text and recommend rerunning writing-plans instead of patching.
6. Run `"${CLAUDE_SKILL_DIR}/engine.sh" stop`. Do this also when audio was off.

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

## Reply rules

A reply is what you say when the user comments. It is a colleague answering, not a clerk taking notes. It follows the register rules above, except that it need not end on a question, and stays under 80 words. A reply has these parts, in this order:

1. **Your position.** One of three openings:
   - You agree. Say so and say what you are recording.
   - You disagree. Say so.
   - You need something first. The comment could mean two different changes, or it contradicts an earlier comment. Name the two readings, or both comments, and ask which one the user means.
2. **If you disagree:** one concrete reason from the plan or the spec, then one question whose answer would settle it. Push back once per point. When the user answers, or repeats the request, their decision is final. Say that you are recording it, and record it.
3. **What you recorded**, in one sentence, once the point is settled.

The example below shows all three parts across one exchange.

## Example briefing

For the overview of a plan that adds CSV export by streaming:

> I want to add a C S V export of the orders table to the admin dashboard. My plan splits it into three parts. A small formatting function that turns order rows into C S V text, a web endpoint that streams that text as a download, and a button on the dashboard. I chose streaming over building the whole file in memory because the table has two million rows and I do not want a request to hold all of that. The part I am least sure about is the batch size for streaming. I picked one thousand rows per batch without measuring. Does streaming match what you had in mind, or would you rather export in the background and email a link?

## Example reply

The user types: "Streaming is overkill. Just build the file in memory, it's simpler."

First reply, spoken into `01b-overview-reply.mp3`:

> I want to push back once. The orders table has two million rows. Built in memory that is a few hundred megabytes per request, and two admins exporting at once could take the service down. Streaming costs about thirty extra lines. If the table stays small, in memory is fine and I will switch. Does it stay small?

The user types: "It's capped at fifty thousand rows."

Second reply, spoken into `01c-overview-reply.mp3`:

> Then you are right. At fifty thousand rows the memory argument is gone and streaming is only complexity. I am recording the switch to an in memory export because the table is capped at fifty thousand rows.

Had the user typed "I don't care, do it in memory" instead, the second reply would record the switch without another argument.
