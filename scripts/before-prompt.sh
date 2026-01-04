#!/bin/bash
# Ralph Wiggum: Before Prompt Hook
# - Updates iteration count in state.md
# - Adds iteration marker to progress.md
# - Injects guardrails into agent context

set -euo pipefail

# Cross-platform sed -i
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract workspace root
WORKSPACE_ROOT=$(echo "$HOOK_INPUT" | jq -r '.workspace_roots[0] // .cwd // "."')

if [[ "$WORKSPACE_ROOT" == "." ]] || [[ -z "$WORKSPACE_ROOT" ]]; then
  if [[ -f "./RALPH_TASK.md" ]]; then
    WORKSPACE_ROOT="."
  else
    echo '{"continue": true}'
    exit 0
  fi
fi

RALPH_DIR="$WORKSPACE_ROOT/.ralph"
TASK_FILE="$WORKSPACE_ROOT/RALPH_TASK.md"

# Check if Ralph is active
if [[ ! -f "$TASK_FILE" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Initialize Ralph state directory if needed
if [[ ! -d "$RALPH_DIR" ]]; then
  mkdir -p "$RALPH_DIR"
  
  cat > "$RALPH_DIR/state.md" <<EOF
---
iteration: 0
status: initialized
started_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---

# Ralph State

Iteration 0 - Initialized, waiting for first prompt.
EOF

  cat > "$RALPH_DIR/guardrails.md" <<EOF
# Ralph Guardrails (Signs)

These are lessons learned from previous iterations. Follow these to avoid known pitfalls.

## Core Signs

### Sign: Read Before Writing
- **Always** read existing files before modifying them

### Sign: Test After Changes
- Run tests after every significant change

### Sign: Commit Checkpoints
- Commit working states before attempting risky changes

### Sign: One Thing at a Time
- Focus on one criterion at a time

---

## Learned Signs

(Signs added from observed failures will appear below)

EOF

  cat > "$RALPH_DIR/context-log.md" <<EOF
# Context Allocation Log (Hook-Managed)

> ⚠️ This file is managed by hooks. Do not edit manually.

## Current Session

| File | Size (est tokens) | Timestamp |
|------|-------------------|-----------|

## Estimated Context Usage

- Allocated: 0 tokens
- Threshold: 80000 tokens (warn at 80%)
- Status: 🟢 Healthy

EOF

  cat > "$RALPH_DIR/edits.log" <<EOF
# Edit Log (Hook-Managed)
# This file is append-only. Do not edit manually.
# Format: TIMESTAMP | FILE | CHANGE_TYPE | CHARS | ITERATION

EOF

  cat > "$RALPH_DIR/failures.md" <<EOF
# Failure Log (Hook-Managed)

## Pattern Detection

- Repeated failures: 0
- Gutter risk: Low

## Recent Failures

(Failures will be logged here by hooks)

EOF

  cat > "$RALPH_DIR/progress.md" <<EOF
# Progress Log

> This file tracks incremental progress. Hooks append checkpoints automatically.
> You can also add your own notes and summaries.

---

## Iteration History

EOF
fi

# Read current state
STATE_FILE="$RALPH_DIR/state.md"
PROGRESS_FILE="$RALPH_DIR/progress.md"
GUARDRAILS_FILE="$RALPH_DIR/guardrails.md"
CONTEXT_LOG="$RALPH_DIR/context-log.md"

# Extract current iteration
CURRENT_ITERATION=$(grep '^iteration:' "$STATE_FILE" 2>/dev/null | sed 's/iteration: *//' || echo "0")
NEXT_ITERATION=$((CURRENT_ITERATION + 1))
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Update state.md - rewrite the whole file to avoid sed issues
cat > "$STATE_FILE" <<EOF
---
iteration: $NEXT_ITERATION
status: active
started_at: $TIMESTAMP
---

# Ralph State

Iteration $NEXT_ITERATION - Active
EOF

# Add iteration marker to progress.md
cat >> "$PROGRESS_FILE" <<EOF

---

### 🔄 Iteration $NEXT_ITERATION Started
**Time:** $TIMESTAMP

EOF

# Check context health
ESTIMATED_TOKENS=$(grep 'Allocated:' "$CONTEXT_LOG" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
if [[ -z "$ESTIMATED_TOKENS" ]]; then
  ESTIMATED_TOKENS=0
fi
THRESHOLD=80000
WARN_THRESHOLD=$((THRESHOLD * 80 / 100))

CONTEXT_WARNING=""
if [[ "$ESTIMATED_TOKENS" -gt "$WARN_THRESHOLD" ]]; then
  CONTEXT_WARNING="⚠️ CONTEXT WARNING: Approaching limit ($ESTIMATED_TOKENS tokens). Consider starting fresh."
fi

# Read learned guardrails
GUARDRAILS=""
if [[ -f "$GUARDRAILS_FILE" ]]; then
  GUARDRAILS=$(sed -n '/## Learned Signs/,$ p' "$GUARDRAILS_FILE" | tail -n +3)
fi

# Build agent message
AGENT_MSG="🔄 **Ralph Iteration $NEXT_ITERATION**

$CONTEXT_WARNING

## Your Task
Read RALPH_TASK.md for the full task description and completion criteria.

## Key Files
- \`.ralph/progress.md\` - Incremental progress (hooks append checkpoints)
- \`.ralph/guardrails.md\` - Signs to follow
- \`.ralph/edits.log\` - Raw edit history

## Ralph Protocol
1. Read progress.md to see what's been done
2. Check guardrails.md for signs to follow
3. Work on the NEXT incomplete criterion from RALPH_TASK.md
4. Update progress.md with notes as you work
5. Commit your changes with descriptive messages
6. When ALL criteria are met, say: \"RALPH_COMPLETE: All criteria satisfied\"
7. If stuck on same issue 3+ times, say: \"RALPH_GUTTER: Need fresh context\"

## Current Guardrails
$GUARDRAILS

Remember: Progress is tracked in FILES, not in context. Hooks automatically log your edits."

jq -n \
  --arg msg "$AGENT_MSG" \
  '{
    "continue": true,
    "agentMessage": $msg
  }'

exit 0
