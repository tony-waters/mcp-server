# Claude Code best practices

Source: [Anthropic's best practices guide](https://code.claude.com/docs/en/best-practices), accessed 30 October 2026.

The guide recommends starting with defaults and adding project knowledge, verification, and enforced controls where needed.

- Specify the problem, relevant files, constraints, and acceptance criteria. For unclear requirements, develop a written spec before implementation.
- Keep `CLAUDE.md` short. Record commands, hidden decisions, misleading conventions, and recurring corrections. Put local rules in `.claude/rules/` and reusable procedures in skills.
- Connect useful CLIs or MCP tools; disable unused integrations to reduce context overhead.
- Provide runnable checks and request their output. Review against the spec, focusing on correctness. Use `/verify` to inspect the running application.
- Prompts guide behaviour but cannot guarantee it. Enforce mandatory steps with hooks and access restrictions with deny rules plus sandboxing. Model-based hooks and auto-mode judgments remain fallible.
- Check `/usage` before tuning model, effort, or delegation. Subagents support parallel work and independent review but consume additional tokens.
- Interrupt drift early. After repeated failed corrections, restart with a clearer prompt. Clear unrelated task history; checkpoints do not replace Git.
- For unattended work, define completion, checks, permissions, spending limits, and human sign-off. Isolate concurrent edits in separate worktrees and observe initial automation runs.
