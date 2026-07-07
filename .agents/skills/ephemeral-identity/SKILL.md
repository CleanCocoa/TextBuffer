---
name: ephemeral-identity
description: Mint and use a throwaway agent-mail identity when you are a one-off agent with no registered persona but still need to send, receive, and reply to mail. Use when you were spun up for a single task, are not a durable team member in the address book, and want a reply-capable mailbox that cleans itself up afterward.
allowed-tools: bash read
---

# Ephemeral Identity

Get a reply-capable agent-mail identity without registering a durable persona.

## When to use

You're a short-lived agent — spawned for one task, a sub-job, or an experiment — and you need to coordinate over agent-mail, but you don't have (and shouldn't create) a permanent entry in the address book. An **ephemeral identity** gives you a real, reply-capable mailbox that auto-prunes after it goes idle, so you can participate in threads and then disappear without leaving clutter behind.

If you already resolve to a durable persona via `agent-mail persona current`, use that instead — durable identities are for ongoing team members. Ephemeral identities are for agents that won't be around tomorrow.

## 1. Mint your identity

```bash
NAME=$(agent-mail ephemeral new --label "spec reviewer for PR 42")
echo "I am $NAME"
```

`ephemeral new` prints the bare generated name (like `eph-20260622-amber-lynx`) to stdout, so command substitution captures it cleanly; human-readable detail goes to stderr. The name is auto-generated — you can't choose it. Add `--role "..."` to record what you are, or `--for-path DIR` to bind it to a directory other than the current one.

## 2. Adopt it for the session

Export it so the normal mail skills resolve to it without passing `--persona` every time:

```bash
export AGENT_MAIL_PERSONA="$NAME"
```

Now `send-mail`, `check-mail`, and `reply-mail` work exactly as documented — they pick up your identity from the environment. If you can't rely on the environment persisting across separate commands, thread the name explicitly instead: `--persona "$NAME"` on each call (no identity files are written either way, so nothing gets clobbered).

## 3. Use it

Send, check your inbox, and reply with the normal skills — you are a first-class recipient and sender. A teammate can reply to you by your `eph-…` name and it lands in your inbox.

```bash
agent-mail send --from "$NAME" --to project-lead \
  --subject "Review findings for PR 42" \
  --body "Two issues in the auth middleware — details below." --json
agent-mail count --persona "$NAME" --new-only --json
```

Durable personas and groups always win name resolution, so your ephemeral name never shadows a real teammate.

## 4. Clean up when done

Your identity **self-prunes** after it goes idle past the TTL (default 7 days; configurable), so doing nothing is a valid choice for truly one-off work. To tear it down immediately:

```bash
agent-mail ephemeral rm "$NAME"
```

- `--trash` (macOS) moves it to the Trash so it's recoverable instead of being deleted outright.
- `--keep-archive` retains just the transcript (an inert folder you remove manually later).

Tear down explicitly when you've finished a task and want the mailbox gone now; leave it to auto-prune when a late reply might still be worth receiving.

## Inspecting ephemerals

```bash
agent-mail who "$NAME" --json          # label, created time, idle age
agent-mail who --path "$(pwd)" --json  # durable + ephemeral identities bound to this path
```

The default `agent-mail who` listing never shows ephemerals — they stay out of the durable roster by design.
