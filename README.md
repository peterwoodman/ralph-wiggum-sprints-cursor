# Ralph Wiggum Cursor Skill

A Cursor Skill implementing [Geoffrey Huntley's Ralph Wiggum technique](https://ghuntley.com/ralph/) for autonomous AI development with deliberate context management.

> "That's the beauty of Ralph - the technique is deterministically bad in an undeterministic world."

## What is Ralph?

Ralph is a technique for autonomous AI development. In its purest form, it's a loop:

```bash
while :; do cat PROMPT.md | npx --yes @sourcegraph/amp ; done
```

The same prompt is fed repeatedly to an AI agent. Progress persists in **files and git**, not in the LLM's context window. Each iteration starts fresh, reads the current state from files, and continues the work.

## Why This Implementation?

The existing [Claude Code Ralph plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) keeps the same context window running, just blocking exit. This misses the core insight:

> "When data is `malloc()`'ed into the LLM's context window, it cannot be `free()`'d unless you create a brand new context window."

This Cursor implementation faithfully adapts Ralph by:

1. **Tracking context allocations** - Monitoring what's loaded into context
2. **Detecting "redlining"** - Warning when context approaches limits
3. **Encouraging fresh starts** - Recognizing when context is polluted
4. **Persisting state in files** - Progress survives context resets
5. **Learning from failures** - Adding "signs" (guardrails) based on observed mistakes

## Installation

### Option 1: Clone and Initialize

```bash
# Clone the skill
gh repo clone agrimsingh/ralph-wiggum-cursor

# In your project directory, run the init script
/path/to/ralph-wiggum-cursor/scripts/init-ralph.sh
```

### Option 2: Manual Setup

1. Copy `hooks.json` to `.cursor/hooks.json` in your project
2. Copy the `scripts/` directory to `.cursor/ralph-scripts/`
3. Update paths in `hooks.json` to point to `.cursor/ralph-scripts/`
4. Create a `RALPH_TASK.md` file (use the template in `assets/`)

## Usage

### 1. Define Your Task

Create `RALPH_TASK.md` in your project root:

```markdown
---
task: Build a REST API for task management
completion_criteria:
  - All CRUD endpoints working
  - Tests passing with >80% coverage
  - API documentation complete
max_iterations: 50
---

## Requirements

Build a task management API with CRUD operations...

## Success Criteria

The task is complete when ALL of the following are true:
1. [ ] All endpoints implemented
2. [ ] Tests passing
3. [ ] Documentation complete
```

### 2. Start a Ralph Loop

Open a new Cursor conversation and say:

> "Start working on the Ralph task defined in RALPH_TASK.md"

### 3. Let Ralph Iterate

Ralph will:
- Read the task and current progress
- Work on the next incomplete item
- Update `.ralph/progress.md`
- Commit checkpoints
- Continue until completion or max iterations

### 4. Monitor Progress

Check `.ralph/progress.md` to see what's been accomplished across iterations.

## How It Works

### The malloc/free Metaphor

In traditional programming:
- `malloc()` allocates memory
- `free()` releases memory

In LLM context:
- Reading files, tool outputs = `malloc()`
- **There is no `free()`** - context cannot be released
- Only way to "free" is starting a new conversation

### State Files

Ralph tracks everything in `.ralph/`:

| File | Purpose |
|------|---------|
| `state.md` | Current iteration, status |
| `progress.md` | What's been accomplished |
| `guardrails.md` | "Signs" - lessons learned from failures |
| `context-log.md` | What's been loaded into context |
| `failures.md` | Failure patterns for gutter detection |

### Hooks

| Hook | Purpose |
|------|---------|
| `beforeSubmitPrompt` | Inject guardrails, track iteration |
| `beforeReadFile` | Track context allocations |
| `afterFileEdit` | Log progress, detect thrashing |
| `stop` | Evaluate completion, trigger next iteration |

### Guardrails ("Signs")

When Ralph makes a mistake, a "sign" is added:

```markdown
### Sign: Validate Before Trust
- **Trigger**: When receiving external input
- **Instruction**: Always validate and sanitize
- **Added after**: Iteration 3 - SQL injection found
```

Signs accumulate and are injected into future iterations.

### Gutter Detection

Ralph detects when it's stuck:
- Same file edited 5+ times without progress
- Same error repeated 3+ times
- Context approaching limits

When detected, Ralph suggests starting fresh.

## Completion Signals

Tell Ralph you're done or stuck:

- `RALPH_COMPLETE: All criteria satisfied` - Task finished
- `RALPH_GUTTER: Need fresh context` - Stuck, need fresh start

## Best Practices

### Do

- Define clear, verifiable completion criteria
- Let Ralph fail and learn (add signs)
- Trust the files, not the context
- Start fresh when stuck

### Don't

- Mix multiple unrelated tasks
- Push context to limits
- Ignore gutter warnings
- Intervene too quickly

## File Structure

```
ralph-wiggum-cursor/
├── SKILL.md                    # Main skill definition
├── hooks.json                  # Cursor hooks configuration
├── scripts/
│   ├── init-ralph.sh          # Initialize Ralph in a project
│   ├── before-prompt.sh       # Inject guardrails
│   ├── before-read.sh         # Track context allocations
│   ├── after-edit.sh          # Log progress
│   └── stop-hook.sh           # Manage iterations
├── references/
│   ├── CONTEXT_ENGINEERING.md # malloc/free deep dive
│   └── GUARDRAILS.md          # How to write signs
└── assets/
    ├── RALPH_TASK_TEMPLATE.md # Task file template
    └── RALPH_TASK_EXAMPLE.md  # Example task
```

## Learn More

- [Original Ralph technique](https://ghuntley.com/ralph/) - Geoffrey Huntley
- [Context engineering](https://ghuntley.com/gutter/) - Autoregressive failure
- [malloc/free metaphor](https://ghuntley.com/allocations/) - Context as memory
- [Deliberate practice](https://ghuntley.com/play/) - Tuning Ralph

## Credits

Based on Geoffrey Huntley's Ralph Wiggum technique. This implementation adapts the methodology for Cursor using Skills and Hooks.

## License

MIT
