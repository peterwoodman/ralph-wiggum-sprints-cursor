#!/bin/bash
# Ralph Wiggum: One-click installer
# Usage: curl -fsSL https://raw.githubusercontent.com/peterwoodman/ralph-wiggum-sprints-cursor/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/peterwoodman/ralph-wiggum-sprints-cursor/main"

echo "═══════════════════════════════════════════════════════════════════"
echo "🐛 Ralph Wiggum Installer"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "⚠️  Warning: Not in a git repository."
  echo "   Ralph requires git for state persistence."
  echo ""
  echo "   Run: git init"
  echo ""
fi

# Check for jq (required for JSON parsing)
if ! command -v jq &> /dev/null; then
  echo "❌ jq not found (required for JSON parsing)"
  echo ""
  echo "Install via:"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  brew install jq"
  elif [[ -f /etc/debian_version ]]; then
    echo "  apt install jq"
  elif [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
    echo "  dnf install jq"
  else
    echo "  See: https://jqlang.github.io/jq/download/"
  fi
  echo ""
  exit 1
fi
echo "✓ jq found"

# Check for cursor-agent CLI
if ! command -v cursor-agent &> /dev/null; then
  echo "⚠️  Warning: cursor-agent CLI not found."
  echo "   Install via: curl https://cursor.com/install -fsS | bash"
  echo ""
fi

WORKSPACE_ROOT="$(pwd)"

# =============================================================================
# CREATE DIRECTORIES
# =============================================================================

echo "📁 Creating directories..."
mkdir -p .cursor/ralph-scripts
mkdir -p .cursor/rules
mkdir -p .ralph

# =============================================================================
# DOWNLOAD SCRIPTS
# =============================================================================

echo "📥 Downloading Ralph scripts..."

SCRIPTS=(
  "ralph-common.sh"
  "ralph.sh"
  "ralph-once.sh"
  "stream-parser.sh"
)

for script in "${SCRIPTS[@]}"; do
  if curl -fsSL "$REPO_RAW/scripts/$script" -o ".cursor/ralph-scripts/$script" 2>/dev/null; then
    chmod +x ".cursor/ralph-scripts/$script"
  else
    echo "   ⚠️  Could not download $script (may not exist yet)"
  fi
done

echo "✓ Scripts installed to .cursor/ralph-scripts/"

# =============================================================================
# INSTALL CURSOR RULES
# =============================================================================

echo "📜 Installing Cursor rules..."

if [[ ! -f ".cursor/rules/ralph-tasks.mdc" ]]; then
# create the rule file
cat > .cursor/rules/ralph-tasks.mdc << 'EOF'
---
description: Rules for creating and managing Ralph sprint tasks
globs:
  - ralph-backlog.json
  - ralph-todo.json
  - ralph-complete.json
alwaysApply: false
---

# Ralph Task Management

When adding, editing, or managing tasks in Ralph task files:

1. **Read `.ralph/task-schema.json`** to understand the required task format
2. **Analyze the codebase** to understand the scope and implications of the task
3. **Ask clarifying questions** before creating tasks if the requirements are ambiguous
4. **Split tasks** with natural boundaries into multiple smaller tasks

## Task File Locations

- `ralph-backlog.json` - Future tasks (add new tasks here)
- `ralph-todo.json` - Current sprint (Ralph processes these)
- `ralph-complete.json` - Completed tasks (moved automatically)

EOF
  echo "✓ Created ralph-tasks.mdc in .cursor/rules/"
fi

# =============================================================================
# INITIALIZE .ralph/ STATE
# =============================================================================

echo "📁 Initializing .ralph/ state directory..."

# Initialize guardrails.md if it doesn't exist
if [[ ! -f ".ralph/guardrails.md" ]]; then
cat > .ralph/guardrails.md << 'EOF'
# Ralph Guardrails (Signs)

> Lessons learned from past failures. READ THESE BEFORE ACTING.

## Core Signs

### Sign: Read Before Writing
- **Trigger**: Before modifying any file
- **Instruction**: Always read the existing file first
- **Added after**: Core principle

### Sign: Test After Changes
- **Trigger**: After any code change
- **Instruction**: Run tests to verify nothing broke
- **Added after**: Core principle

### Sign: Commit Checkpoints
- **Trigger**: Before risky changes
- **Instruction**: Commit current working state first
- **Added after**: Core principle

---

## Learned Signs

(Signs added from observed failures will appear below)

EOF
fi

# Initialize progress.md if it doesn't exist
if [[ ! -f ".ralph/progress.md" ]]; then
cat > .ralph/progress.md << 'EOF'
# Progress Log

> Updated by the agent after significant work.

---

## Session History

EOF
fi

# Initialize errors.log if it doesn't exist
if [[ ! -f ".ralph/errors.log" ]]; then
cat > .ralph/errors.log << 'EOF'
# Error Log

> Failures detected by stream-parser. Use to update guardrails.

EOF
fi

# Initialize activity.log if it doesn't exist
if [[ ! -f ".ralph/activity.log" ]]; then
cat > .ralph/activity.log << 'EOF'
# Activity Log

> Real-time tool call logging from stream-parser.

EOF
fi

echo "0" > .ralph/.iteration

echo "✓ .ralph/ initialized"

# =============================================================================
# INITIALIZE SPRINT FILES (JSON task files)
# =============================================================================

echo "📋 Initializing sprint task files..."

# Create ralph-backlog.json if it doesn't exist
if [[ ! -f "ralph-backlog.json" ]]; then
cat > ralph-backlog.json << 'EOF'
[]
EOF
  echo "✓ Created ralph-backlog.json"
else
  echo "✓ ralph-backlog.json already exists (not overwritten)"
fi

# Create ralph-todo.json if it doesn't exist
if [[ ! -f "ralph-todo.json" ]]; then
  echo "[]" > ralph-todo.json
  echo "✓ Created ralph-todo.json"
else
  echo "✓ ralph-todo.json already exists (not overwritten)"
fi

# Create ralph-complete.json if it doesn't exist
if [[ ! -f "ralph-complete.json" ]]; then
  echo "[]" > ralph-complete.json
  echo "✓ Created ralph-complete.json"
else
  echo "✓ ralph-complete.json already exists (not overwritten)"
fi

# Download task-schema.json to .ralph/
if curl -fsSL "$REPO_RAW/tasks/task-schema.json" -o ".ralph/task-schema.json" 2>/dev/null; then
  echo "✓ Downloaded task-schema.json to .ralph/"
else
  # Fallback: create a basic schema if download fails
cat > .ralph/task-schema.json << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Ralph Task List",
  "description": "Schema for ralph task tracking files (ralph-todo.json, ralph-complete.json, ralph-backlog.json)",
  "type": "array",
  "items": {
    "type": "object",
    "required": ["category", "description", "status", "priority", "steps", "dependencies"],
    "properties": {
      "category": {
        "type": "string",
        "enum": ["backend", "frontend", "data"],
        "description": "The area of the codebase this task belongs to"
      },
      "description": {
        "type": "string",
        "description": "Brief description of the task"
      },
      "status": {
        "type": "string",
        "enum": ["pending", "in_progress", "completed", "blocked"],
        "description": "Current status of the task"
      },
      "priority": {
        "type": "string",
        "enum": ["high", "medium", "low"],
        "description": "Priority level of the task"
      },
      "steps": {
        "type": "array",
        "items": { "type": "string" },
        "description": "List of implementation steps for this task"
      },
      "dependencies": {
        "type": "array",
        "items": { "type": "string" },
        "description": "List of task descriptions that must be completed before this task"
      },
      "passes": {
        "type": ["integer", "null"],
        "minimum": 0,
        "description": "Number of implementation passes/iterations completed"
      }
    }
  }
}
EOF
  echo "✓ Created task-schema.json in .ralph/"
fi

# =============================================================================
# UPDATE .gitignore
# =============================================================================

if [[ -f ".gitignore" ]]; then
  if ! grep -q "ralph-config.json" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# Ralph config (may contain API key)" >> .gitignore
    echo ".cursor/ralph-config.json" >> .gitignore
  fi
else
  cat > .gitignore <<'EOF'
# Ralph config (may contain API key)
.cursor/ralph-config.json
EOF
fi
echo "✓ Updated .gitignore"

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "✅ Ralph installed!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Files created:"
echo ""
echo "  📁 .cursor/ralph-scripts/"
echo "     ├── ralph.sh              - Continuous loop (main entry)"
echo "     ├── ralph-once.sh         - Single iteration (testing)"
echo "     ├── ralph-common.sh       - Shared utilities"
echo "     └── stream-parser.sh      - Output parser"
echo ""
echo "  📁 .cursor/rules/"
echo "     └── ralph-tasks.mdc       - AI rules for task management"
echo ""
echo "  📁 .ralph/                   - State files (tracked in git)"
echo "     ├── guardrails.md         - Lessons learned (Signs)"
echo "     ├── progress.md           - Progress log"
echo "     ├── activity.log          - Tool call log"
echo "     ├── errors.log            - Failure log"
echo "     └── task-schema.json      - Task JSON schema"
echo ""
echo "  📄 Sprint Files              - Task tracking (tracked in git)"
echo "     ├── ralph-backlog.json    - Future tasks"
echo "     ├── ralph-todo.json       - Current sprint (Ralph processes)"
echo "     └── ralph-complete.json   - Completed tasks"
echo ""
echo "Next steps:"
echo "  1. Add tasks to ralph-backlog.json (or ask Cursor to help)"
echo "  2. Move tasks to ralph-todo.json when ready to work"
echo "  3. Run: ./.cursor/ralph-scripts/ralph.sh"
echo ""
echo "Quick commands:"
echo "  • ralph-once.sh              - Test with single iteration first"
echo "  • ralph.sh -n 50 -m sonnet   - Custom iterations and model"
echo "  • ralph.sh --branch feat -y  - Create branch, skip confirmation"
echo ""
echo "Monitor progress:"
echo "  tail -f .ralph/activity.log"
echo ""
echo "Learn more: https://ghuntley.com/ralph/"
echo "═══════════════════════════════════════════════════════════════════"
