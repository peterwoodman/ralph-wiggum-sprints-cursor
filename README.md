# Ralph Wiggum Sprints for Cursor: Autonomous Task Agents

Ralph runs the Cursor agent in a continuous loop with sprint-style task management. Progress persists in files and git, not in the LLM's context window.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/peterwoodman/ralph-wiggum-sprints-cursor/main/install.sh | bash
```

Start the loop:

```bash
./.cursor/ralph-scripts/ralph.sh
```

Ralph runs continuously, polling for work. Add tasks to `ralph-todo.json` and Ralph will pick them up automatically.

## Prerequisites

- Git repository
- jq (JSON processor): https://jqlang.github.io/jq/
- cursor-agent CLI: `curl https://cursor.com/install -fsS | bash`

## Documentation

See RALPH.md for full usage instructions, task format, and configuration.

## Credits

Based on https://github.com/agrimsingh/ralph-wiggum-cursor by Agrim Singh.

Original Ralph Wiggum technique by Geoffrey Huntley: https://ghuntley.com/ralph/

Inspiration: https://www.youtube.com/watch?v=_IK18goX4X8

## License

MIT
