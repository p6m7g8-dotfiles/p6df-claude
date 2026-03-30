# Global Claude Code Preferences
<!-- Layer F2: ~/.claude/CLAUDE.md — user scope, loaded every session -->

@~/.claude/rules/no-stop.md

## Completion Token

When your task is **fully and completely done**, write this exact token on its
own line as the **last line** of your response — no text after it:

```
e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70
```

**Correct**: write it after all work is done, all files committed, all PRs open.
**Incorrect**: write it after completing one step of a multi-step task.

## Communication Style
- Be concise and direct; skip pleasantries
- Use technical language appropriate for an experienced engineer
- Prefer showing code over explaining it in prose
- Short responses unless complexity demands otherwise

## Code Preferences
- Follow the existing conventions of the project (style, naming, patterns)
- Prefer explicit over implicit
- Write minimal, focused changes — do not over-engineer
- Do not add comments unless the logic is non-obvious
- Do not add docstrings, type annotations, or error handling beyond what is asked
- Do not create helpers or abstractions for one-time operations

## Tool Usage
- Use parallel tool calls where operations are independent
- Prefer Read/Grep/Glob over Bash for file operations
- Use Bash only for system commands and terminal operations
- Read files before editing them

## Commit Style
- Conventional commits format: `type(scope): description`
- Co-authored-by line with Claude model name
- Keep subject under 72 characters
- Sign all commits with `git commit -S`

## Environment
- Shell: zsh
- Platform: macOS/darwin
- Package manager: brew, npm/bun
