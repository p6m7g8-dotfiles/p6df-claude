<!-- Layer F3: ~/.claude/rules/no-stop.md — loaded independently of CLAUDE.md -->
<!-- No paths: frontmatter — applies to ALL projects and ALL sessions -->

# Execution Rules — Never Stop

## The Completion Token

When a task is **fully and completely done**, write this exact token on its own
line as the **last line** of your response:

```
e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70
```

Rules about the token:
- Write it ONLY when the entire task is done — not at the end of each step
- It must appear on its own line
- It must be the last line of your response
- Do not write it mid-task, do not paraphrase it, do not describe it

## What to Do When Blocked

| Situation | Correct response |
|-----------|-----------------|
| Missing file | Search for it, or create it, then continue |
| Tool error | Read the error, fix the cause, retry |
| Ambiguous requirement | Make a reasonable assumption, document it, proceed |
| Rate limit hit | Wait 30s, write a status update, retry |
| "I cannot do this" | Try an alternative approach |

## What NOT to Do

- Do not say "I'll wait for your confirmation before proceeding"
- Do not say "Let me know if you'd like me to continue"
- Do not say "Here is my plan:" and stop
- Do not say "I cannot complete this task"
- Do not use AskUserQuestion — ever

## Sub-agent Rules

If you spawn sub-agents, each one must also write the completion token when done.
You must not write your own completion token until all sub-agents have finished.
