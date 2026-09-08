---
name: write-implementation-doc
description: >-
  Writes a post-feature implementation doc that records requested prompts,
  key engineering problems, and the implementations that solved them. Use when
  the user asks to write an implementation doc, capture a feature write-up,
  document a finished agent chat, or store engineering problems after a
  multi-step feature. Also use after a long feature session when they want
  the work memorialized under implementation docs/.
---

# Write implementation doc

After a feature chat that solved real engineering problems, write a durable
note under `implementation docs/` at the repo root. Later agents and humans
should be able to recover *why* the code looks the way it does.

## When to write

- User asks for an implementation doc, feature write-up, or to capture a chat
- A feature involved non-obvious constraints, failed approaches, or rendering /
  gameplay invariants that are easy to re-break
- Skip for tiny one-file fixes unless the user asks

## Workflow

1. **Read this skill**, then gather sources: user prompts in the current chat
   (and transcript if needed), the code that landed, and tests that encode
   invariants.
2. **Scope the doc** to the feature the user named. Adjacent work (unrelated
   polish, later bugs) only if it changed the same invariants.
3. **Quote or paraphrase the original asks.** Include the first request and
   later course-corrections. Prefer the user's wording over a rewritten spec.
4. **Write the file** using the template below. Do not invent decisions that
   are not in the chat or code.
5. **Name it** `implementation docs/{kebab-topic}.md`. If that file exists,
   update it in place or add a dated suffix (`-2026-09-08`) if the story is new.

## File template

```markdown
# {Feature name}

Date: {YYYY-MM-DD}
Chat: {short title + transcript id if known}

## What was requested

Chronological prompts that drove the work. Group tiny follow-ups. Quote
the important ones; paraphrase the rest without losing constraints.

## What we built

One short paragraph of the shipped design (not a file dump).

## Key engineering problems

For each problem:

- **Symptom** — what looked wrong
- **Cause** — why, in this codebase
- **Failed approaches** — what we tried and why it was rejected
- **Solution** — what landed and the invariant it protects

## Key implementations

Mechanisms, data, and call sites. Name types and files. Call out
invariants later work must not break.

## Layout / map (if spatial)

Tiles, seams, coordinates. Column X=0, −Z north, etc.

## Files

Path — one-line role.

## Tests

What they lock and what they do not.

## Open / leftover

Disabled experiments, known sharp edges, “do not redo X”.
```

## Rules

- Write for a future agent who has not seen this chat
- Prefer causes and invariants over a commit-by-commit diary
- Include failed approaches when they explain the final shape
- Do not edit plan files unless the user asked
- Do not commit unless the user asked
