# Ralph Wiggum: Autonomous Development Loop

> "That's the beauty of Ralph - the technique is deterministically bad in an undeterministic world."

Ralph runs the Cursor agent in a continuous loop, processing tasks from a sprint-style workflow with progress tracking.

---

## Prerequisites

```bash
# 1. jq (JSON processor)
brew install jq        # macOS
apt install jq         # Linux
choco install jq       # Windows

# 2. cursor-agent CLI, and
curl https://cursor.com/install -fsS | bash

# 3. Git repository (required for state persistence)
git status
```

---

## File Structure

```
project/
├── ralph-backlog.json     # Future tasks (agent adds here)
├── ralph-todo.json        # Current sprint (Ralph processes)
├── ralph-complete.json    # Done (moved automatically)
└── .ralph/
    ├── task-schema.json   # Task JSON schema
    ├── guardrails.md      # Lessons learned (Signs)
    ├── progress.md        # Agent progress notes
    ├── activity.log       # Real-time operations
    └── errors.log         # Failure history
```

---

## Creating Tasks

### Using an Agent

Ask the Cursor agent to create tasks for you. The agent should:

1. Read `.ralph/task-schema.json` for the task format
2. Analyze the codebase to understand scope and implications
3. Ask clarifying questions before creating tasks
4. Split tasks with natural boundaries into multiple tasks
5. Add tasks to `ralph-backlog.json` (in the `tasks` array)

**Example prompt:**

```
Add a task to the backlog following the backlog instructions: Implement user authentication.
```

### Task Format

```json
{
  "category": "backend|frontend|data",
  "description": "Brief task description",
  "status": "pending",
  "priority": "high|medium|low",
  "steps": ["Step 1", "Step 2"],
  "dependencies": [],
  "notes": ["Context for the agent"]
}
```

### Moving to Sprint

Move tasks from `ralph-backlog.json` to `ralph-todo.json` when ready to work:

```bash
# Manual: edit the files directly
# Or use jq to move specific tasks
```

Or Ask the Agent:

```
Move the first three tasks from the backlog to ToDo
---

## Running Ralph

### Test First

```bash
# Single iteration
./.cursor/ralph-scripts/ralph-once.sh
./.cursor/ralph-scripts/ralph-once.sh -m sonnet-4.5-thinking
```

### Continuous Loop

```bash
# Start autonomous loop
./.cursor/ralph-scripts/ralph.sh

# With options
./.cursor/ralph-scripts/ralph.sh -n 50 -p 5 -m gpt-5.2-high
./.cursor/ralph-scripts/ralph.sh --branch feature/api --pr -y
```

| Flag              | Description             | Default           |
| ----------------- | ----------------------- | ----------------- |
| `-n N`          | Max iterations per task | 20                |
| `-p N`          | Max passes before stall | 3                 |
| `-m MODEL`      | AI model                | opus-4.5-thinking |
| `--branch NAME` | Create feature branch   | -                 |
| `--pr`          | Open PR when done       | false             |
| `-y`            | Skip confirmation       | false             |

**Stop:** `Ctrl+C`

---

## Task Lifecycle

```
pending → in_progress → completed → (moved to ralph-complete.json)
                ↓
            stalled (passes >= 3)
```

1. Agent selects a workable task and marks it `in_progress`
2. Agent increments `passes` and works through steps
3. On completion, agent marks `completed` and signals `<ralph>COMPLETE</ralph>`
4. Orchestrator commits changes and moves task to complete file
5. Tasks failing 3+ times are skipped (stalled) for human review

---

## Monitoring

```bash
# Watch real-time activity
tail -f .ralph/activity.log

# Check progress
cat .ralph/progress.md

# Check errors
cat .ralph/errors.log
```

**Token usage** is logged to activity.log for monitoring context consumption.

---

## Configuration

```bash
export RALPH_MODEL="sonnet-4.5-thinking"  # AI model
export MAX_PASSES=5                        # Stall threshold
export POLL_INTERVAL=15                    # Seconds between checks
```

---

## Troubleshooting

| Problem             | Solution                                                   |
| ------------------- | ---------------------------------------------------------- |
| Task keeps stalling | Check `.ralph/errors.log`, add guardrail, simplify steps |
| Invalid JSON        | Run `jq empty ralph-todo.json` to validate               |
| Agent stuck         | It will signal GUTTER; check errors and add a Sign         |

### Guardrails (Signs)

Add to `.ralph/guardrails.md` when patterns cause repeated failures:

```markdown
### Sign: [Name]
- **Trigger**: When this occurs
- **Instruction**: What to do instead
- **Added after**: What happened
```

### Reset Stalled Task

```bash
jq '(.tasks[] | select(.description == "Task name")).passes = 0' ralph-todo.json > tmp && mv tmp ralph-todo.json
```

---

## Signals

| Signal                      | Meaning                   | Orchestrator Action              |
| --------------------------- | ------------------------- | -------------------------------- |
| `<ralph>COMPLETE</ralph>` | Task done                 | Commit, move task, fresh context |
| `<ralph>GUTTER</ralph>`   | Stuck                     | Log, increment passes, next task |
| `<ralph>STALLED</ralph>`  | All tasks over pass limit | Poll for human review            |
| `<ralph>EMPTY</ralph>`    | No tasks                  | Poll for new tasks               |
