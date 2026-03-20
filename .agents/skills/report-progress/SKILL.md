---
name: report-progress
description: Send a concise progress update via agent-mail. Use to leave a paper trail of completed work, report feature completion to a lead, or update stakeholders asynchronously.
allowed-tools: bash read
---

# Report Progress

Send a concise status update to a lead, orchestrator, or stakeholder.

## When to use

- You finished a task or feature and your lead should know.
- You hit a blocker and need to flag it.
- A milestone was reached and stakeholders need a paper trail.
- You want to leave an async record of what happened during a work session.

## Preferred flow: reply to an existing task thread

If the work came from an existing message, prefer replying to that thread so the context stays attached:

```bash
agent-mail thread '<task-message-id>' --persona <you> --json
```

Then reply:

```bash
agent-mail reply \
  --persona <you> \
  --to '<task-message-id>' \
  --body-file /path/to/update.txt \
  --status "done" \
  --json
```

Use `--body` instead of `--body-file` for short one-line or two-line updates.

## Start a new thread when needed

If there is no existing task thread, send a fresh update:

```bash
agent-mail send \
  --from <you> \
  --to <lead-or-stakeholder> \
  --subject "Completed: <brief description>" \
  --body-file /path/to/update.txt \
  --status "done" \
  --project <project-name> \
  --json
```

If the project is known, include `--project` so recipients can filter and prioritize it.

## Writing the update

### Structure

1. **What** — one line stating what was done.
2. **Where** — files, commits, or endpoints changed (names only, not full diffs).
3. **What's next** (if applicable) — the immediate next step or who's unblocked.
4. **Blockers** (if any) — what you're stuck on and what you need.

### Keep it short

The reader can inspect the actual changes in git or on the filesystem. Your job is to tell them *what happened* and *what it means*, not to replay every step. Two to five lines is typical.

### Status values

Use statuses intentionally:
- `done` — work is complete
- `blocked` — progress is halted pending input or dependency
- `needs-input` — you need a decision, answer, or missing information
- `needs-changes` — review or follow-up found issues that must be addressed

### Example: feature complete

```bash
agent-mail send \
  --from backend-agent \
  --to project-lead \
  --subject "Completed: session auth endpoint" \
  --body "Implemented POST /api/sessions with Bearer token auth.
Files: src/api/sessions.py, src/auth/middleware.py, tests/test_sessions.py
All tests passing. Frontend-agent is unblocked to integrate." \
  --status "done" \
  --project auth-service \
  --json
```

### Example: blocker

```bash
agent-mail send \
  --from backend-agent \
  --to project-lead \
  --subject "Blocked: rate limiter needs Redis config" \
  --body "Rate limiting implementation is ready but needs a Redis connection string.
Who owns infra config? I need REDIS_URL set in the environment." \
  --status "blocked" \
  --priority high \
  --project auth-service \
  --json
```

### Example: reply to a task assignment

```bash
agent-mail reply \
  --persona backend-agent \
  --to '<task-msg-id@agent-mail>' \
  --body "> Implement session auth endpoint.

Done. POST /api/sessions returns a Bearer token, validated in middleware.
Files changed: src/api/sessions.py, src/auth/middleware.py
Tests added in tests/test_sessions.py — all green." \
  --status "done" \
  --json
```

## Communication flow

Task teams work in their own projects/worktrees and communicate directly with each other. The team lead or orchestrator then summarizes upward to CTO/CEO via agent-mail. Not every agent mails every other agent — keep communication channels focused and hierarchical.

```text
developer agents <-> team lead (direct, within project)
team lead -> CTO/CEO (progress summaries, cross-project)
```
