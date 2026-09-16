# walk-me-through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A personal Claude Code skill that explains a superpowers plan out loud, section by section, waits for typed feedback after each section, and applies that feedback to the plan file.

**Architecture:** The git repository is the skill directory. A root `SKILL.md` holds the walkthrough procedure and the spoken-register rules. A small `speak.sh` turns stdin text into speech with edge-tts and plays it with mpv, blocking until done. An `install.sh` installs edge-tts and checks mpv. No hooks, no MCP server.

**Tech Stack:** bash, edge-tts (installed as a uv tool), mpv, Claude Code personal skills, the vercel-labs skills CLI for installation.

**Spec:** `docs/superpowers/specs/2026-09-16-walk-me-through-design.md`

## Global Constraints

- Repository root is the skill. `SKILL.md`, `speak.sh`, `install.sh`, `README.md` live at the root. Tests live in `tests/`.
- Skill name is `walk-me-through`. Frontmatter `name` must be exactly `walk-me-through`.
- Frontmatter fields allowed: `name`, `description`, `argument-hint`, `disable-model-invocation`. Nothing else.
- `speak.sh` configuration is limited to two environment variables: `WALK_ME_THROUGH_VOICE` (default `en-US-AndrewMultilingualNeural`) and `WALK_ME_THROUGH_RATE` (default `+0%`).
- All shell scripts start with `#!/usr/bin/env bash` and `set -u`. No `set -e`; every failure is handled explicitly with a message on stderr.
- Scripts resolve their own directory with `readlink -f "$0"` because the skills CLI installs a symlink.
- Temporary files use `mktemp` in `${TMPDIR:-/tmp}`, never the Claude scratchpad.
- Prose in README and SKILL.md: one idea per sentence, lists for enumerations, no em-dashes.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Tests are plain bash scripts that print `PASS:`, `FAIL:` or `SKIP:` lines and exit non-zero if any test failed.

---

### Task 1: speak.sh

**Files:**
- Create: `speak.sh`
- Test: `tests/test-speak.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `speak.sh`. Reads UTF-8 text on stdin. Exit 0 after playback finished. Exit 1 with one line on stderr if `edge-tts` or `mpv` is missing, stdin is empty, or synthesis fails. Env: `WALK_ME_THROUGH_VOICE`, `WALK_ME_THROUGH_RATE`. Task 2 and Task 3 call it as `"$dir/speak.sh"` and `${CLAUDE_SKILL_DIR}/speak.sh`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test-speak.sh`:

```bash
#!/usr/bin/env bash
# Tests for speak.sh. Run from anywhere: tests/test-speak.sh
# Each test builds a PATH that contains only the commands it wants visible.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
speak="$here/../speak.sh"
failed=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }
skip() { echo "SKIP: $1"; }

# make_bin DIR CMD... : symlink each CMD into DIR so PATH=DIR exposes only them
make_bin() {
  local dir=$1; shift
  local c
  for c in "$@"; do
    ln -sf "$(command -v "$c")" "$dir/$c" || return 1
  done
}
base=(bash cat mktemp rm readlink dirname)
have_edge=0; command -v edge-tts >/dev/null 2>&1 && have_edge=1
have_mpv=0;  command -v mpv      >/dev/null 2>&1 && have_mpv=1

# Test 1: edge-tts missing -> exit 1, reason on stderr
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
[ $have_mpv -eq 1 ] && make_bin "$bin" mpv
err=$(echo "hello" | PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"edge-tts not found"* ]]; then
  pass "missing edge-tts exits non-zero with reason"
else
  fail "missing edge-tts: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 2: mpv missing -> exit 1, reason on stderr
if [ $have_edge -eq 1 ]; then
  bin=$(mktemp -d)
  make_bin "$bin" "${base[@]}" edge-tts
  err=$(echo "hello" | PATH="$bin" bash "$speak" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && [[ "$err" == *"mpv not found"* ]]; then
    pass "missing mpv exits non-zero with reason"
  else
    fail "missing mpv: rc=$rc stderr=$err"
  fi
  rm -rf "$bin"
else
  skip "missing mpv test needs edge-tts installed"
fi

# Test 3: empty stdin -> exit 1
if [ $have_edge -eq 1 ] && [ $have_mpv -eq 1 ]; then
  err=$(printf '' | bash "$speak" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && [[ "$err" == *"no text"* ]]; then
    pass "empty stdin exits non-zero"
  else
    fail "empty stdin: rc=$rc stderr=$err"
  fi
else
  skip "empty stdin test needs edge-tts and mpv"
fi

# Test 4: success -> exit 0, temp files removed. Audible. Needs network.
if [ $have_edge -eq 1 ] && [ $have_mpv -eq 1 ]; then
  tmp=$(mktemp -d)
  echo "Speak script test." | TMPDIR="$tmp" bash "$speak"; rc=$?
  left=$(ls -A "$tmp" | wc -l)
  if [ $rc -eq 0 ] && [ "$left" -eq 0 ]; then
    pass "speaks and cleans up temp files"
  else
    fail "success path: rc=$rc leftover files=$left"
  fi
  rm -rf "$tmp"
else
  skip "success test needs edge-tts and mpv"
fi

exit $failed
```

- [ ] **Step 2: Make it executable and run it to verify it fails**

Run: `chmod +x tests/test-speak.sh && tests/test-speak.sh`
Expected: `FAIL:` lines because `speak.sh` does not exist yet (bash reports "No such file"). Exit code 1.

- [ ] **Step 3: Write speak.sh**

Create `speak.sh`:

```bash
#!/usr/bin/env bash
# speak.sh: read text on stdin, synthesize it with edge-tts, play it with mpv.
# Blocks until playback ends. Exit 0 on success, 1 with a reason on stderr otherwise.
# Env: WALK_ME_THROUGH_VOICE (edge-tts voice name), WALK_ME_THROUGH_RATE (e.g. +10%).
set -u

voice="${WALK_ME_THROUGH_VOICE:-en-US-AndrewMultilingualNeural}"
rate="${WALK_ME_THROUGH_RATE:-+0%}"

for cmd in edge-tts mpv; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "speak.sh: $cmd not found. Run install.sh in the skill directory." >&2
    exit 1
  fi
done

text_file=$(mktemp) || { echo "speak.sh: mktemp failed" >&2; exit 1; }
audio_file="$text_file.mp3"
trap 'rm -f "$text_file" "$audio_file"' EXIT

cat > "$text_file"
if [ ! -s "$text_file" ]; then
  echo "speak.sh: no text on stdin" >&2
  exit 1
fi

if ! edge-tts --voice "$voice" --rate "$rate" --file "$text_file" --write-media "$audio_file" >/dev/null 2>&1; then
  echo "speak.sh: edge-tts failed. Check network access and the voice name '$voice'." >&2
  exit 1
fi

mpv --no-video --really-quiet "$audio_file" </dev/null
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x speak.sh && tests/test-speak.sh`
Expected: four `PASS:` lines (or `SKIP:` for tests 2 to 4 if edge-tts is not installed yet on this machine). Test 4 plays "Speak script test." out loud. Exit code 0.

If edge-tts is not installed yet, install it now so the full test runs: `uv tool install edge-tts`, then rerun.

- [ ] **Step 5: Commit**

```bash
git add speak.sh tests/test-speak.sh
git commit -m "Add speak.sh: stdin text to speech via edge-tts and mpv

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: install.sh and README

**Files:**
- Create: `install.sh`
- Create: `README.md`
- Test: `tests/test-install.sh`

**Interfaces:**
- Consumes: `speak.sh` from Task 1, called as `"$here/speak.sh"`.
- Produces: `install.sh`, idempotent, exit 0 when edge-tts and mpv are usable and a test sentence was spoken. Exit 1 with instructions on stderr when `uv` or `mpv` is missing. `README.md` with the agent install block as the first thing under the Install heading.

- [ ] **Step 1: Write the failing tests**

Create `tests/test-install.sh`:

```bash
#!/usr/bin/env bash
# Tests for install.sh failure branches. Never installs anything.
# Run from anywhere: tests/test-install.sh
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
install="$here/../install.sh"
failed=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }
skip() { echo "SKIP: $1"; }

make_bin() {
  local dir=$1; shift
  local c
  for c in "$@"; do
    ln -sf "$(command -v "$c")" "$dir/$c" || return 1
  done
}
base=(bash cat echo mktemp rm readlink dirname)

# Test 1: uv missing -> exit 1, prints the uv install hint
bin=$(mktemp -d)
make_bin "$bin" "${base[@]}"
err=$(PATH="$bin" bash "$install" 2>&1 >/dev/null); rc=$?
if [ $rc -ne 0 ] && [[ "$err" == *"astral.sh/uv/install.sh"* ]]; then
  pass "missing uv exits non-zero with install hint"
else
  fail "missing uv: rc=$rc stderr=$err"
fi
rm -rf "$bin"

# Test 2: uv and edge-tts present, mpv missing -> exit 1, prints mpv hint.
# Guarded: if edge-tts is absent the script would run 'uv tool install'.
if command -v uv >/dev/null 2>&1 && command -v edge-tts >/dev/null 2>&1; then
  bin=$(mktemp -d)
  make_bin "$bin" "${base[@]}" uv edge-tts
  err=$(PATH="$bin" bash "$install" 2>&1 >/dev/null); rc=$?
  if [ $rc -ne 0 ] && [[ "$err" == *"mpv is missing"* ]]; then
    pass "missing mpv exits non-zero with package hint"
  else
    fail "missing mpv: rc=$rc stderr=$err"
  fi
  rm -rf "$bin"
else
  skip "missing mpv test needs uv and edge-tts installed"
fi

exit $failed
```

- [ ] **Step 2: Make it executable and run it to verify it fails**

Run: `chmod +x tests/test-install.sh && tests/test-install.sh`
Expected: `FAIL:` lines because `install.sh` does not exist. Exit code 1.

- [ ] **Step 3: Write install.sh**

Create `install.sh`:

```bash
#!/usr/bin/env bash
# install.sh: install what speak.sh needs and speak one test sentence.
# Safe to run more than once. Exit 0 on success, 1 with instructions otherwise.
set -u

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is missing. Install it, open a new shell, then rerun this script:" >&2
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi

if ! command -v edge-tts >/dev/null 2>&1; then
  echo "Installing edge-tts as a uv tool..."
  if ! uv tool install edge-tts; then
    echo "uv tool install edge-tts failed. See the output above." >&2
    exit 1
  fi
fi

if ! command -v edge-tts >/dev/null 2>&1; then
  echo "edge-tts is installed but not on PATH. Run 'uv tool update-shell', open a new shell, then rerun this script." >&2
  exit 1
fi

if ! command -v mpv >/dev/null 2>&1; then
  echo "mpv is missing. Install it with your package manager, then rerun this script:" >&2
  echo "  sudo pacman -S mpv      (Arch)" >&2
  echo "  sudo apt install mpv    (Debian, Ubuntu)" >&2
  echo "  brew install mpv        (macOS)" >&2
  exit 1
fi

echo "Speaking a test sentence..."
if ! echo "Walk me through is installed. Restart Claude Code, then run slash walk me through on a plan." | "$here/speak.sh"; then
  echo "The test sentence failed. Check network access and audio output, then rerun this script." >&2
  exit 1
fi

echo "Done. Restart Claude Code so the walk-me-through skill is picked up."
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x install.sh && tests/test-install.sh`
Expected: two `PASS:` lines. Exit code 0.

- [ ] **Step 5: Run install.sh for real on this machine**

Run: `./install.sh`
Expected: "Speaking a test sentence...", the sentence is audible, then "Done. Restart Claude Code ...". Exit code 0. Running it a second time gives the same result without reinstalling.

- [ ] **Step 6: Write README.md**

Create `README.md`:

````markdown
# walk-me-through

A Claude Code skill that explains a superpowers implementation plan out loud.
It speaks like a colleague briefing you, not like a screen reader.
It goes section by section. After each section it stops and waits for your
typed feedback. At the end it applies your feedback to the plan file.

## Install

### Let Claude do it

Paste this into Claude Code on the new machine:

> Install the Claude Code skill from https://github.com/skast96/walk-me-through-skill.
> Run `npx skills add skast96/walk-me-through-skill -g -a claude-code -y`.
> If that fails, git clone the repository to `~/.claude/skills/walk-me-through`.
> Then run `~/.claude/skills/walk-me-through/install.sh`, show me its output,
> and remind me to restart Claude Code.

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

Claude speaks the plan in four to eight sections. After each one you get a
prompt with Continue, Repeat, Go deeper, or a free text field for comments.
At the end Claude summarizes your comments, edits the plan file, and prints
what changed.

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
````

- [ ] **Step 7: Commit**

```bash
git add install.sh README.md tests/test-install.sh
git commit -m "Add install.sh and README with agent install block

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: SKILL.md and fixture plan

**Files:**
- Create: `SKILL.md`
- Create: `tests/fixture-plan.md`

**Interfaces:**
- Consumes: `speak.sh` from Task 1 via `${CLAUDE_SKILL_DIR}/speak.sh`. Claude Code substitutes `${CLAUDE_SKILL_DIR}` in skill markdown with the directory that holds `SKILL.md`.
- Produces: the `/walk-me-through` command.

- [ ] **Step 1: Write the fixture plan**

Create `tests/fixture-plan.md`. It is a plan in writing-plans format with an overview, constraints, three tasks, and no risk section, so the walkthrough must add the risks section itself.

````markdown
# CSV Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CSV export of the orders table to the admin dashboard.

**Architecture:** A pure formatting function turns order rows into CSV text. A new HTTP endpoint streams that text with a download header. A button in the dashboard calls the endpoint. Streaming was chosen over building the file in memory because the orders table has two million rows.

**Tech Stack:** Go 1.24, net/http, existing `orders` package, existing dashboard template.

**Spec:** none, this is a fixture.

## Global Constraints

- No new third party dependencies.
- CSV must open in Excel without a wizard, so use a UTF-8 byte order mark.
- Endpoint requires the existing admin session cookie.

---

### Task 1: CSV formatter

**Files:**
- Create: `orders/csv.go`
- Test: `orders/csv_test.go`

**Interfaces:**
- Produces: `func WriteCSV(w io.Writer, rows []Order) error`

- [ ] **Step 1: Write the failing test** for a two row input and one row with a comma in the customer name.
- [ ] **Step 2: Run the test** and see it fail.
- [ ] **Step 3: Implement WriteCSV** with encoding/csv and the byte order mark.
- [ ] **Step 4: Run the test** and see it pass.
- [ ] **Step 5: Commit.**

### Task 2: Export endpoint

**Files:**
- Create: `admin/export.go`
- Modify: `admin/routes.go`
- Test: `admin/export_test.go`

**Interfaces:**
- Consumes: `orders.WriteCSV`
- Produces: `GET /admin/orders.csv`

- [ ] **Step 1: Write the failing test** with httptest, asserting status 200, content type text/csv, and a Content-Disposition attachment header.
- [ ] **Step 2: Run the test** and see it fail.
- [ ] **Step 3: Implement the handler.** Iterate orders in batches of one thousand and write each batch through WriteCSV so memory stays flat.
- [ ] **Step 4: Run the test** and see it pass.
- [ ] **Step 5: Commit.**

### Task 3: Dashboard button

**Files:**
- Modify: `templates/admin/orders.html`

- [ ] **Step 1: Add a link** styled as a button pointing at `/admin/orders.csv`.
- [ ] **Step 2: Load the page** and click the button. A file downloads.
- [ ] **Step 3: Commit.**
````

- [ ] **Step 2: Write SKILL.md**

Create `SKILL.md`:

````markdown
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

Speak a briefing by piping it into the speak script. Use a Bash timeout of 300000 so long sections finish:

```bash
cat <<'BRIEFING' | ${CLAUDE_SKILL_DIR}/speak.sh
<briefing text>
BRIEFING
```

The script blocks until playback ends. If it exits non-zero, audio is unavailable for this walkthrough. Print the briefing as text instead, tell the user once that audio is off and why (use the script's stderr line), and continue in text mode for every remaining section. Do not retry audio.

## Procedure

### 1. Find the plan

- If `$ARGUMENTS` names a file, use it.
- Otherwise use the most recently modified file in `docs/superpowers/plans/`.
- If that directory does not exist, ask the user for a path and stop until you have one.
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

1. Write the briefing following the register rules below.
2. Speak it.
3. Ask with AskUserQuestion. Question: "Any thoughts on this part?" Options, in this order:
   - **Continue** — next section.
   - **Repeat** — speak the same briefing again.
   - **Go deeper** — write and speak a second briefing on the same section, up to 250 words, covering the individual steps, the interfaces, and what the tests check. Then ask again.
   - The built in Other field is where the user types comments.
4. When the user types a comment:
   - Record it together with the section and the task it belongs to.
   - If the comment could mean two different changes, ask one typed clarification before moving on. Do not speak the clarification.
   - If it contradicts an earlier comment, ask which one wins.
   - Then continue to the next section.

### 4. Wrap up

1. If there were no comments, speak one sentence saying so and stop.
2. Otherwise write and speak a wrap up briefing: every change the user asked for, one sentence each, in plan order. Under 150 words.
3. Edit the plan file:
   - Keep the writing-plans structure: task headers, Files, Interfaces, checkbox steps.
   - Change only the sections the user commented on.
   - A new task gets the same bite sized steps as its neighbours: failing test, run, implement, run, commit.
   - If a comment changes the design rather than the plan, apply the plan side and add a note in your text summary that the spec needs the same change. Never edit the spec.
4. Print a text summary of what changed, section by section.
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
````

- [ ] **Step 3: Restart Claude Code and verify the skill is listed**

Start a new Claude Code session in `~/.claude/skills/walk-me-through`. Run `/skills`.
Expected: `walk-me-through` appears with the description from the frontmatter.

- [ ] **Step 4: Manual dry run against the fixture, audio on**

In that session run:

```
/walk-me-through tests/fixture-plan.md
```

Check every item. Note any failure and fix `SKILL.md` before continuing.

- [ ] The printed section list has four or five entries: overview, constraints, the formatter and endpoint (merged or separate), the dashboard button folded into the endpoint or the overview, and risks. Six is acceptable if nothing was merged.
- [ ] Every spoken briefing ends with a question.
- [ ] No briefing contains a file path, a function name, or a slash command.
- [ ] Choosing Repeat speaks the same text again.
- [ ] Choosing Go deeper on the endpoint section mentions the batch size and the three header assertions in the test.
- [ ] Type this comment on the endpoint section: "Use a batch size of five thousand, not one thousand." Continue to the end.
- [ ] The wrap up names the batch size change. `tests/fixture-plan.md` now says five thousand in Task 2 step 3 and nothing else changed. Verify with `git diff tests/fixture-plan.md`.
- [ ] Restore the fixture: `git checkout tests/fixture-plan.md`.

- [ ] **Step 5: Manual dry run, audio off**

Rename the speak script temporarily so it cannot be found:

```bash
mv speak.sh speak.sh.off
```

In a fresh Claude Code session run `/walk-me-through tests/fixture-plan.md` and select Continue for every section.

- [ ] Claude says once that audio is off, quoting the script's stderr reason.
- [ ] Every briefing appears as text.
- [ ] The walkthrough reaches the wrap up and ends with "no comments".

Restore the script:

```bash
mv speak.sh.off speak.sh
```

- [ ] **Step 6: Commit and push**

```bash
git add SKILL.md tests/fixture-plan.md
git commit -m "Add walk-me-through SKILL.md and fixture plan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push
```

- [ ] **Step 7: Verify the skills CLI install path on this machine**

This checks Path 1 from the spec without disturbing the working clone.

```bash
mv ~/.claude/skills/walk-me-through ~/.claude/skills/walk-me-through.dev
npx skills add skast96/walk-me-through-skill -g -a claude-code -y
ls -la ~/.claude/skills/walk-me-through
~/.claude/skills/walk-me-through/install.sh
```

Expected: the directory or symlink exists and contains `SKILL.md` and `speak.sh`, and `install.sh` speaks its test sentence. Then remove the CLI install and put the clone back:

```bash
npx skills remove --global walk-me-through -y || rm -rf ~/.claude/skills/walk-me-through
mv ~/.claude/skills/walk-me-through.dev ~/.claude/skills/walk-me-through
```

If `npx skills add` names the directory differently from `walk-me-through`, fix the README install text to match what it actually produced and commit that fix.
