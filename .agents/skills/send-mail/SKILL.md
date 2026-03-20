---
name: send-mail
description: Send a new agent-mail message to start a thread — ask a question, make a request, or coordinate with teammates. Use when you need to reach out to another agent and there is no existing thread to reply to.
allowed-tools: bash read
---

# Send Mail

Start a new conversation thread with another agent.

## When to use

- You have a question for a specific teammate.
- You need to request work or input from someone.
- You're coordinating across projects or teams.
- There is no existing message thread to reply to (otherwise use `reply-mail`).

## Prerequisites

Resolve your persona first if you haven't already:

```bash
agent-mail persona current --json
```

Do **not** create a new persona unless the user explicitly asks for setup work.

If the recipient is unclear, discover likely personas first:

```bash
agent-mail who
agent-mail who --project <project-name>
agent-mail who --group <group-name>
```

## Command

Short messages can be sent inline:

```bash
agent-mail send \
  --from <you> \
  --to <recipient> \
  --subject "Clear, specific subject" \
  --body "Message body" \
  --json
```

For longer messages, prefer `--body-file`:

```bash
agent-mail send \
  --from <you> \
  --to <recipient> \
  --subject "Clear, specific subject" \
  --body-file /path/to/message.txt \
  --project <project-name> \
  --json
```

You can also send to a group name (e.g. `--to backend-team`) or multiple recipients.

Use `agent-mail who` to discover available personas and groups.

## Etiquette

### Subject line
- Be specific. "API auth question" not "Question".
- Keep it short enough to scan in a list.

### Body
- Lead with what you need and by when (if relevant).
- Provide just enough context for the reader to act without digging. If referencing code, name the file and function — don't paste large blocks.
- One topic per thread. If you have two unrelated questions, send two messages.
- Keep it concise. This is work mail between collaborators, not a blog post. The reader is busy.

### Metadata headers (optional, use when useful)
- `--priority high` — only when genuinely urgent; overuse dilutes the signal.
- `--project project-name` — recommended when working within a known project.
- `--tags "review,auth"` — for categorization.
- `--status "needs-input"` — signal what kind of response you need.

## Example

```bash
agent-mail send \
  --from backend-agent \
  --to frontend-agent \
  --subject "Auth token format for /api/sessions" \
  --body "I'm implementing the sessions endpoint. Do you need the token as a Bearer header or a cookie? The auth module supports both. Let me know and I'll wire it up." \
  --project auth-service \
  --status "needs-input" \
  --json
```
