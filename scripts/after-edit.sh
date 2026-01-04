#!/bin/bash
# Ralph Wiggum: After File Edit Hook
# - Appends to edits.log (raw history)
# - Appends checkpoints to progress.md (recovery points)
# - Updates context-log.md (malloc tracking)
# - Detects thrashing patterns

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

# Extract file info
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.file_path // ""')
WORKSPACE_ROOT=$(echo "$HOOK_INPUT" | jq -r '.workspace_roots[0] // "."')

# Cursor sends edits as an array with old_string/new_string
OLD_TOTAL=$(echo "$HOOK_INPUT" | jq -r '[.edits[].old_string // ""] | map(length) | add // 0')
NEW_TOTAL=$(echo "$HOOK_INPUT" | jq -r '[.edits[].new_string // ""] | map(length) | add // 0')

RALPH_DIR="$WORKSPACE_ROOT/.ralph"
EDITS_LOG="$RALPH_DIR/edits.log"
PROGRESS_FILE="$RALPH_DIR/progress.md"
CONTEXT_LOG="$RALPH_DIR/context-log.md"
FAILURES_FILE="$RALPH_DIR/failures.md"
STATE_FILE="$RALPH_DIR/state.md"

# If Ralph isn't active, pass through
if [[ ! -d "$RALPH_DIR" ]]; then
  echo '{}'
  exit 0
fi

# Get current iteration
CURRENT_ITERATION=$(grep '^iteration:' "$STATE_FILE" 2>/dev/null | sed 's/iteration: *//' || echo "0")

# Calculate change
CHANGE_SIZE=$((NEW_TOTAL - OLD_TOTAL))

if [[ $CHANGE_SIZE -lt 0 ]]; then
  CHANGE_SIZE=$((-CHANGE_SIZE))
  CHANGE_TYPE="removed"
elif [[ $CHANGE_SIZE -eq 0 ]] && [[ $NEW_TOTAL -gt 0 ]]; then
  CHANGE_SIZE=$NEW_TOTAL
  CHANGE_TYPE="modified"
elif [[ $CHANGE_SIZE -gt 0 ]]; then
  CHANGE_TYPE="added"
else
  CHANGE_TYPE="no-op"
  echo '{}'
  exit 0
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TIME_SHORT=$(date -u +%H:%M:%S)
FILENAME=$(basename "$FILE_PATH")

# =============================================================================
# 1. APPEND TO EDITS.LOG (raw edit history)
# =============================================================================

if [[ ! -f "$EDITS_LOG" ]]; then
  cat > "$EDITS_LOG" <<EOF
# Edit Log (Hook-Managed)
# This file is append-only. Do not edit manually.
# Format: TIMESTAMP | FILE | CHANGE_TYPE | CHARS | ITERATION

EOF
fi

echo "$TIMESTAMP | $FILENAME | $CHANGE_TYPE | $CHANGE_SIZE chars | iter $CURRENT_ITERATION" >> "$EDITS_LOG"

# =============================================================================
# 2. APPEND CHECKPOINT TO PROGRESS.MD (incremental, for recovery)
# =============================================================================

# Skip logging edits to .ralph/ files to avoid noise
if [[ "$FILE_PATH" != *".ralph/"* ]]; then
  # Append a checkpoint entry
  cat >> "$PROGRESS_FILE" <<EOF

**[$TIME_SHORT]** Edited \`$FILENAME\` ($CHANGE_SIZE chars $CHANGE_TYPE)
EOF
fi

# =============================================================================
# 3. UPDATE CONTEXT-LOG.MD (edits consume context)
# =============================================================================

if [[ -f "$CONTEXT_LOG" ]]; then
  EDIT_TOKENS=$(( (OLD_TOTAL + NEW_TOTAL) / 4 ))
  if [[ $EDIT_TOKENS -lt 10 ]]; then
    EDIT_TOKENS=10
  fi
  
  CURRENT_ALLOCATED=$(grep 'Allocated:' "$CONTEXT_LOG" | grep -o '[0-9]*' | head -1 || echo "0")
  if [[ -z "$CURRENT_ALLOCATED" ]]; then
    CURRENT_ALLOCATED=0
  fi
  NEW_ALLOCATED=$((CURRENT_ALLOCATED + EDIT_TOKENS))
  
  sedi "s/Allocated: [0-9]* tokens/Allocated: $NEW_ALLOCATED tokens/" "$CONTEXT_LOG"
  
  THRESHOLD=80000
  WARN_THRESHOLD=$((THRESHOLD * 80 / 100))
  CRITICAL_THRESHOLD=$((THRESHOLD * 95 / 100))
  
  if [[ "$NEW_ALLOCATED" -gt "$CRITICAL_THRESHOLD" ]]; then
    sedi "s/Status: .*/Status: 🔴 Critical - Start fresh!/" "$CONTEXT_LOG"
  elif [[ "$NEW_ALLOCATED" -gt "$WARN_THRESHOLD" ]]; then
    sedi "s/Status: .*/Status: 🟡 Warning - Approaching limit/" "$CONTEXT_LOG"
  fi
  
  TEMP_FILE=$(mktemp)
  awk -v file="[EDIT] $FILENAME" -v tokens="$EDIT_TOKENS" -v ts="$TIMESTAMP" '
    /^## Estimated Context Usage/ {
      print "| " file " | " tokens " | " ts " |"
      print ""
    }
    { print }
  ' "$CONTEXT_LOG" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CONTEXT_LOG"
fi

# =============================================================================
# 4. CHECK FOR THRASHING PATTERNS
# =============================================================================

EDIT_COUNT=$(grep -c "| $FILENAME |" "$EDITS_LOG" 2>/dev/null || echo "0")

if [[ "$EDIT_COUNT" -gt 5 ]]; then
  cat >> "$FAILURES_FILE" <<EOF

## Potential Thrashing Detected
- File: $FILE_PATH
- Edits in session: $EDIT_COUNT
- Iteration: $CURRENT_ITERATION
- Time: $TIMESTAMP

EOF

  REPEATED_FAILURES=$(grep -c "Potential Thrashing" "$FAILURES_FILE" 2>/dev/null || echo "0")
  sedi "s/Repeated failures: [0-9]*/Repeated failures: $REPEATED_FAILURES/" "$FAILURES_FILE"
  
  if [[ "$REPEATED_FAILURES" -gt 2 ]]; then
    sedi "s/Gutter risk: .*/Gutter risk: HIGH/" "$FAILURES_FILE"
  fi
fi

echo '{}'
exit 0
