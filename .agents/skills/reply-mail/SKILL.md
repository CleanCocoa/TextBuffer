---
name: reply-mail
description: Reply to an agent-mail message with proper context quoting. Use when responding to a message you received — answers, follow-ups, acknowledgements.
allowed-tools: bash read
---

# Reply to Mail

Reply to a message you've received, maintaining thread context.

## Prerequisites

Resolve your persona first if you haven't already:

```bash
agent-mail persona current --json
```

Do **not** create a new persona unless the user explicitly asks for setup work.

If the current thread may have more context than the single message you were given, inspect it first:

```bash
agent-mail thread '<message-id>' --persona <you> --json
```

## Command

Short replies can be sent inline:

```bash
agent-mail reply \
  --persona <you> \
  --to '<message-id>' \
  --body "Your reply" \
  --json
```

For longer replies, prefer a file or stdin over complex shell quoting:

```bash
agent-mail reply \
  --persona <you> \
  --to '<message-id>' \
  --body-file /path/to/reply.txt \
  --json
```

The `--to` flag takes the Message-ID you're replying to (from `read`, `ls`, or `thread` output). Threading headers (`In-Reply-To`, `References`, `Re: subject`) are set automatically.

## Etiquette

### Quote enough context

In group threads, not everyone has read every message recently. Quote the key part you're responding to so readers can follow without re-reading the whole thread.

Format quotes with `>` prefixes:

```bash
agent-mail reply \
  --persona alice \
  --to '<msg-id@agent-mail>' \
  --body "> Do you need the token as a Bearer header or a cookie?

Bearer header. I'll expect it as Authorization: Bearer <token>.

I've updated the endpoint to validate it — see src/api/sessions.py:handle_auth()." \
  --json
```

### Keep replies focused

- Answer the question or address the request directly. Lead with the answer.
- If the original message had multiple points, address each briefly.
- Don't repeat information the sender already knows.
- Reference files, functions, or commits by name rather than pasting code. The reader can look it up.

### Signal status when relevant

Use `--status` to communicate state:

```bash
agent-mail reply \
  --persona alice \
  --to '<msg-id@agent-mail>' \
  --body "> Please review the auth module.

Reviewed. Two issues found — see inline comments in src/auth/middleware.py. The token expiry logic at line 42 doesn't handle refresh tokens." \
  --status "needs-changes" \
  --json
```

Common values include `done`, `blocked`, `needs-input`, and `needs-changes`.

### Acknowledge promptly, follow up with substance

If you need time to do work before replying fully, send a brief acknowledgement:

```bash
--body "> Review the auth module.

On it. Will reply with findings after I've read through the middleware."
```

Then reply again with the actual findings.

## After replying

Archive the original message only after the reply has been sent successfully and no further inbox action remains:

```bash
agent-mail move '<message-id>' --persona <you> --to archive
```
