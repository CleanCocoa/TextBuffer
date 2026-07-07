---
name: answer-mail
description: Stand up an auto-answerer for a persona with `agent-mail loop`, so questions sent to it are answered automatically by a handler command. Use when asked to make a persona answer its own mail unattended.
allowed-tools: bash read
---

# Answer Mail

Turn a persona into an auto-answerer. `agent-mail loop` polls the inbox and, for
each new message, runs a handler command, sends its output back as the reply, and
archives the message — no human in the loop.

## When to use

- You want a persona (a librarian, triage bot, "ready agent") to answer its own
  mail unattended.
- For a *single* check-and-reply pass by hand, use the `check-mail` + `reply-mail`
  skills instead. `loop` is for the standing, automated case.

## The handler contract

The handler is any program. For each message it receives:

- **stdin**: the question — the subject, a blank line, then the body.
- **env**: `AGENT_MAIL_MID`, `AGENT_MAIL_FROM`, `AGENT_MAIL_SUBJECT`,
  `AGENT_MAIL_PERSONA`.

Its **stdout** becomes the reply body. **Exit 0 with non-empty output** ⇒ the reply
is marked `status=done`; anything else (nonzero exit, or no output) ⇒ `status=error`.
Write progress/diagnostics to **stderr** — it streams to the terminal for watching
and is never part of the reply.

A trivial echo handler, to prove the wiring:

```bash
agent-mail loop --persona <you> --once -- cat
```

## Run it

```bash
# Drain the current backlog once, then exit (good for cron):
agent-mail loop --persona <you> --once -- ./my-answerer

# Run continuously (Ctrl-C / SIGTERM stops it after the current message):
agent-mail loop --persona <you> -- ./my-answerer
```

Resolve `<you>` with `agent-mail persona current --json`, or rely on project config
and omit `--persona`.

## Useful flags

- `--poll SECONDS` — inbox poll interval (default 15).
- `--timeout SECONDS` — per-message ceiling; `0` = no limit. A ~10min ceiling suits
  long agent runs, or use none and watch the session to tell "stuck" from "working".
- `--on-error keep|archive` — default `archive`. `keep` leaves a failed message in
  the inbox (marked Seen, so it isn't retried every poll) for a human to look at.
- `--quiet` — don't tee the handler's stderr to the terminal.
- `--json` — emit one JSON record per processed message on stdout.

## Notes

- Serial by design: one message at a time.
- The reply is always sent before the message is archived, so a crash never
  silently drops a question.
- A handler command that can't be launched fails fast at startup without touching
  the inbox — fix the command and re-run.
- For a ready-made `claude` answerer (with resumable transcripts) plus tmux and
  launchd/systemd units, see `contrib/loop/` in the agent-mail repo.
