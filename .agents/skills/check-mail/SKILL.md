---
name: check-mail
description: Check your agent-mail inbox for new messages, read them, and archive handled ones. Use at the start of a work session or when expecting replies.
allowed-tools: bash read
---

# Check Mail

Check your inbox, read new messages, and archive ones you've handled.

## Prerequisites

Resolve your persona first:

```bash
agent-mail persona current --json
```

This reads `.agent-mail/identities.toml` in the project and returns your persona name.
Use that name wherever `<you>` appears below. Do **not** create a new persona unless the user explicitly asks for setup work.

## Workflow

### 1. Check for new messages

```bash
agent-mail count --persona <you> --new-only --json
```

If count is 0, you're caught up — stop here.

### 2. List new messages

```bash
agent-mail ls --persona <you> --new-only --json
```

### 3. Read each message

```bash
agent-mail read '<message-id>' --persona <you> --json
```

Reading marks the message as Seen.

### 4. Recover thread context when needed

If the message is part of an ongoing conversation, inspect the thread before replying or acting:

```bash
agent-mail thread '<message-id>' --persona <you> --json
```

Use this when the current message references prior work, follow-ups, or multiple participants.

### 5. Act on each message

After reading, decide:
- **Reply needed** → use the `reply-mail` skill
- **Just informational** → archive it
- **Needs work first** → do the work, then usually reply to the sender; use `report-progress` as additional stakeholder communication when appropriate

### 6. Archive handled messages

```bash
agent-mail move '<message-id>' --persona <you> --to archive
```

Archive messages once you've handled them. Keep your inbox as a todo list — only unhandled items stay.

## Tips

- Use `--json` for machine-readable output when parsing programmatically.
- Check mail at natural breakpoints: start of session, after completing a task, before reporting progress.
- Don't poll in a tight loop. Check when you have reason to expect a reply.
- If you only need to understand a message quickly, `read` is enough; if you need conversation history, use `thread`.
