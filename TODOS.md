# TODOS

Tracked follow-ups from the weekend-1 plan slice. Source: design doc
`~/.gstack/projects/projects/nicknad-unknown-design-20260418-151228.md`.

## Weekend-1 remainder (must ship by Monday)

### Step 10 — Convert NSAlert failure path to in-popover fallback + Retry
**What:** Replace the plain `NSAlert` shown on generation failure with an in-popover
fallback state: principle text visible, fallback prompt ("No question could be
generated right now. Write anything that comes to mind about this principle."),
Retry button that re-runs the scheduler, answer TextView still usable.

**Why:** The `NSAlert` flow forces click → dismiss → click again, which is a bad
first impression when the first click of the app fails. Design doc §174-177
specifies this UX explicitly.

**Pros:** Tool stays usable offline; single click still produces a writing surface
regardless of llm status. Closer to the "always usable even offline, just less
magical" promise (design doc §179).

**Cons:** Adds a 5th state to `MorningPopoverController` (loading / question /
empty / error / fallback). Couples UI polish with scheduler ship.

**Context:** `DailyQuestionScheduler` already emits a `.failed(error)` result that
the `error` popover state currently binds to an `NSAlert`. Swap that binding for
the fallback view. Design doc §174-177 has the copy. The scheduler's
no-advance-on-`lastAskedAt` rule (§177) already handles the DB side correctly.

**Depends on / blocked by:** weekend-1 scheduler + popover slice shipped first.

### Step 12 — UNUserNotificationCenter: 7am daily + catch-up on launch + menubar badge
**What:** Request notification permission on first launch. Schedule a daily
repeating `UNCalendarNotificationTrigger` at 7am local. On every app launch,
if today has no `question` entry AND current time ≥07:00, post an immediate
catch-up notification. Show a badge/dot on the menubar icon whenever today
has no answered question and current time ≥07:00 — independent of notification
permission state.

**Why:** Without a notification or badge, the user has to remember to click the
icon. The design doc explicitly flags "I rarely open it — feels like homework"
as the failure mode for apps that require remembering. An ambient badge is the
minimum viable reminder.

**Pros:** Closes the ambient-surface promise of the design. Badge works even when
notifications are denied.

**Cons:** ~1 hour of work across permission flow, trigger registration, launch
catch-up logic, and badge state management. Adds first-launch friction
(permission prompt).

**Context:** Three known limitations documented in design doc §235-238:
- Mac asleep at 7am → catch-up on next launch handles it
- App quit entirely → notifications don't fire at all (LoginItem registration is
  weekend 2 work)
- Permission denied → badge still works

**Depends on / blocked by:** weekend-1 scheduler slice shipped first (so the
catch-up path has something to call into).

### Step 13 — DMG release + README with install flow
**What:** Write a `create-dmg.sh` script that builds a signed-by-ad-hoc DMG from
the `build/Core Principles.app` output. Write a README with install instructions:
`xattr -d com.apple.quarantine "/Applications/Core Principles.app"`,
`brew install llm`, `llm keys set anthropic`. Push DMG to GitHub Releases.

**Why:** The design doc's core success criterion is "Ship a working DMG by end
of weekend. Monday morning = first real use." Without a DMG you only have
`swift run` and manual `build.sh` — that's not shippable.

**Pros:** Crosses the finish line of weekend 1. First real dogfooding starts
Monday.

**Cons:** ~45 min. Must happen before the weekend ends.

**Context:** `mac-month-progress-menubar` already has a working DMG pipeline —
reuse that pattern. Repo is unsigned (same as the month-progress app); README
must include the `xattr` bypass step. Bundle executable is "Core Principles"
(with space); `build.sh` already handles the SwiftPM target-name mismatch per
the logged learning.

**Depends on / blocked by:** weekend-1 scheduler slice shipped first (otherwise
the DMG ships a dead app).

## v1.5 and later (from design doc)

- LoginItem registration via `SMAppService` (auto-start on login) — weekend 2
- Move prompt template to `~/.principles/prompts/morning.tmpl` (external, editable)
- Q&A history view (chronological, per principle)
- In-app "add insight" button + migration 002 (new/mature states + 'insight' kind)
- State-machine scheduler (new → active → mature graduation, replaces pure rotation)
- Manual "ask me this today" override in principles window
- Store question `type` (reflection/concept/retrospective/commitment) as a structured
  column when migration 002 ships — currently v1 embeds last 2 question bodies in
  the prompt and relies on the LLM to self-avoid. Revisit if question variety drifts.
- Settings pane: notification time, target language
- Voice input for the answer field
- Prompt caching via direct Anthropic SDK (if cost becomes noticeable)
