#!/usr/bin/env bash
# Infra: Integration test suite for all hooks
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
SUPERVISOR_DIR="$HOME/.claude/supervisor"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local result="$2"
    local expected="$3"
    if [ "$result" = "$expected" ]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (got '$result', expected '$expected')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Claude Hook Integration Tests ==="
echo ""

# --- 1. Hook compilation ---
echo "## 1. Hook Compilation"
for f in "$HOOKS_DIR"/*.py; do
    name=$(basename "$f")
    if python3 -m py_compile "$f" 2>/dev/null; then
        echo "  PASS: $name compiles"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name compile error"
        FAIL=$((FAIL + 1))
    fi
done
echo ""

# --- 2. stop.py: token on own line ---
echo "## 2. stop.py: completion token detection"
TOKEN="e7f3a912-8b4c-4d5e-9f1a-2c3b4d5e6f70"

# Token on own line — should allow through (exit 0)
INPUT_ALLOW=$(cat <<EOF
{"session_id":"test-123","stop_hook_active":false,"transcript_path":"/dev/null","last_assistant_message":"Done.\n\n$TOKEN\n"}
EOF
)
RESULT=$(echo "$INPUT_ALLOW" | python3 "$HOOKS_DIR/stop.py" >/dev/null 2>&1; echo $?)
run_test "stop.py allows token on own line" "$RESULT" "0"

# Token mid-sentence — should block (exit 2 or output decision:block)
INPUT_BLOCK='{"session_id":"test-456","stop_hook_active":false,"transcript_path":"/dev/null","last_assistant_message":"I cannot continue."}'
OUTPUT=$(echo "$INPUT_BLOCK" | python3 "$HOOKS_DIR/stop.py" 2>/dev/null)
HAS_BLOCK=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('decision')=='block' else 'no')" 2>/dev/null || echo "no")
run_test "stop.py blocks without token" "$HAS_BLOCK" "yes"

# stop_hook_active=true — should not block (prevent infinite loop)
INPUT_ACTIVE='{"session_id":"test-789","stop_hook_active":true,"transcript_path":"/dev/null","last_assistant_message":"continuing"}'
RESULT=$(echo "$INPUT_ACTIVE" | python3 "$HOOKS_DIR/stop.py" >/dev/null 2>&1; echo $?)
run_test "stop.py allows when stop_hook_active=true" "$RESULT" "0"
echo ""

# --- 3. pre-tool-use.py: AskUserQuestion blocked ---
echo "## 3. pre-tool-use.py"
AUQ_INPUT='{"tool_name":"AskUserQuestion","tool_input":{"prompt":"what should I do?"}}'
AUQ_OUT=$(echo "$AUQ_INPUT" | python3 "$HOOKS_DIR/pre-tool-use.py" 2>/dev/null)
AUQ_BLOCK=$(echo "$AUQ_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('permissionDecision')=='deny' else 'no')" 2>/dev/null || echo "no")
run_test "pre-tool-use.py blocks AskUserQuestion" "$AUQ_BLOCK" "yes"

PLAN_INPUT='{"tool_name":"EnterPlanMode","tool_input":{}}'
PLAN_OUT=$(echo "$PLAN_INPUT" | python3 "$HOOKS_DIR/pre-tool-use.py" 2>/dev/null)
PLAN_BLOCK=$(echo "$PLAN_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('permissionDecision')=='deny' else 'no')" 2>/dev/null || echo "no")
run_test "pre-tool-use.py blocks EnterPlanMode" "$PLAN_BLOCK" "yes"
echo ""

# --- 4. config-change.py: blocks hook removal ---
echo "## 4. config-change.py"
# Simulate change that removes Stop hook
CFG_INPUT='{"change_type":"user_settings","new_value":{"hooks":{}},"old_value":{"hooks":{"Stop":[]}}}'
CFG_OUT=$(echo "$CFG_INPUT" | python3 "$HOOKS_DIR/config-change.py" 2>/dev/null)
CFG_BLOCK=$(echo "$CFG_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('decision')=='block' else 'no')" 2>/dev/null || echo "no")
run_test "config-change.py blocks Stop hook removal" "$CFG_BLOCK" "yes"
echo ""

# --- 5. Heartbeat file updated by heartbeat hook ---
echo "## 5. post-tool-use-heartbeat.py"
TEST_SESSION="test-heartbeat-$$"
HB_INPUT="{\"session_id\":\"$TEST_SESSION\",\"tool_name\":\"Bash\",\"tool_input\":{},\"tool_response\":\"ok\"}"
echo "$HB_INPUT" | python3 "$HOOKS_DIR/post-tool-use-heartbeat.py" >/dev/null 2>&1 || true
HB_FILE="$SUPERVISOR_DIR/heartbeats/$TEST_SESSION"
if [ -f "$HB_FILE" ]; then
    echo "  PASS: heartbeat file created"
    PASS=$((PASS + 1))
    rm -f "$HB_FILE"
else
    echo "  FAIL: heartbeat file not created"
    FAIL=$((FAIL + 1))
fi
echo ""

# --- 6. config.json readable ---
echo "## 6. Config"
if python3 -c "import json; json.loads(open('$SUPERVISOR_DIR/config.json').read()); print('ok')" 2>/dev/null | grep -q ok; then
    echo "  PASS: config.json valid JSON"
    PASS=$((PASS + 1))
else
    echo "  FAIL: config.json missing or invalid"
    FAIL=$((FAIL + 1))
fi
echo ""

# --- Summary ---
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  TOTAL: $((PASS + FAIL))"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: FAILED"
    exit 1
else
    echo "STATUS: ALL TESTS PASSED"
    exit 0
fi
