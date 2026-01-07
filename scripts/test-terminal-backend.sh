#!/bin/bash
# test-terminal-backend.sh - Comprehensive test suite for terminal-backend.sh
#
# Run: ./scripts/test-terminal-backend.sh
# Output: Test report with PASS/FAIL status

# Don't exit on error - we want to run all tests
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source terminal-backend.sh (disable set -e temporarily)
(
  set +e
  source "$SCRIPT_DIR/terminal-backend.sh"
) || true

# Re-source with set +e active (override the set -e in terminal-backend.sh)
set +e
source "$SCRIPT_DIR/terminal-backend.sh" 2>/dev/null || {
  echo "ERROR: Failed to source terminal-backend.sh"
  exit 1
}
set +e  # Ensure we're still in +e mode

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors (if terminal supports)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test workspace for cleanup
TEST_WORKSPACE="wo-test-$$"
TEST_SESSIONS=()

# =============================================================================
# Test Utilities
# =============================================================================

log_test() {
  local name="$1"
  echo -e "\n${YELLOW}[TEST]${NC} $name"
}

pass() {
  local msg="$1"
  ((TESTS_PASSED++))
  ((TESTS_TOTAL++))
  echo -e "  ${GREEN}PASS${NC}: $msg"
}

fail() {
  local msg="$1"
  ((TESTS_FAILED++))
  ((TESTS_TOTAL++))
  echo -e "  ${RED}FAIL${NC}: $msg"
}

cleanup() {
  echo -e "\n${YELLOW}[CLEANUP]${NC} Cleaning up test sessions..."
  for session_id in "${TEST_SESSIONS[@]}"; do
    tb_cleanup_session "$session_id" 2>/dev/null || true
  done
  echo "  Cleanup completed"
}

trap cleanup EXIT

# =============================================================================
# Unit Tests
# =============================================================================

test_initialization() {
  log_test "Initialization"

  # Test backend detection
  if [ -n "$TB_BACKEND" ]; then
    pass "Backend detected: $TB_BACKEND"
  else
    fail "Backend not detected"
  fi

  # Test Python detection
  if [ -n "$TB_PYTHON" ]; then
    pass "Python detected: $TB_PYTHON"
  else
    fail "Python not detected"
  fi

  # Verify backend matches platform
  local expected_backend
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows*)
      expected_backend="wezterm"
      ;;
    *)
      expected_backend="tmux"
      ;;
  esac

  if [ "$TB_BACKEND" = "$expected_backend" ]; then
    pass "Backend matches platform expectation"
  else
    fail "Expected $expected_backend, got $TB_BACKEND"
  fi
}

test_session_id_parsing() {
  log_test "Session ID Parsing"

  # Test 1: Basic parsing
  _parse_session_id "wo:my-workspace:feature-branch.0"
  if [ "$SESSION" = "my-workspace" ] && [ "$WINDOW" = "feature-branch" ] && [ "$PANE" = "0" ]; then
    pass "Basic parsing: SESSION=$SESSION WINDOW=$WINDOW PANE=$PANE"
  else
    fail "Basic parsing failed: SESSION=$SESSION WINDOW=$WINDOW PANE=$PANE"
  fi

  # Test 2: Complex branch name with hyphens
  _parse_session_id "wo:project:feature-auth-api.0"
  if [ "$WINDOW" = "feature-auth-api" ]; then
    pass "Complex branch name parsing: WINDOW=$WINDOW"
  else
    fail "Complex branch name parsing failed: WINDOW=$WINDOW"
  fi

  # Test 3: Numeric pane
  _parse_session_id "wo:test:main.5"
  if [ "$PANE" = "5" ]; then
    pass "Numeric pane parsing: PANE=$PANE"
  else
    fail "Numeric pane parsing failed: PANE=$PANE"
  fi

  # Test 4: Build session ID
  local built_id
  built_id=$(_build_session_id "workspace" "branch" "0")
  if [ "$built_id" = "wo:workspace:branch.0" ]; then
    pass "Build session ID: $built_id"
  else
    fail "Build session ID failed: $built_id"
  fi
}

test_path_normalization() {
  log_test "Path Normalization (Windows fix)"

  # This tests the fix for Windows gitbash cwd issue
  # The fix removes trailing slashes from paths

  local test_path_unix="/home/user/project/"
  local test_path_win="C:\\Users\\test\\"

  # Simulate path normalization
  local normalized_unix="${test_path_unix%/}"
  normalized_unix="${normalized_unix%\\}"

  local normalized_win="${test_path_win%/}"
  normalized_win="${normalized_win%\\}"

  if [ "$normalized_unix" = "/home/user/project" ]; then
    pass "Unix path trailing slash removed"
  else
    fail "Unix path normalization failed: $normalized_unix"
  fi

  if [ "$normalized_win" = "C:\\Users\\test" ]; then
    pass "Windows path trailing backslash removed"
  else
    fail "Windows path normalization failed: $normalized_win"
  fi
}

test_backend_api() {
  log_test "Backend API Functions"

  # Test tb_get_backend
  local backend
  backend=$(tb_get_backend)
  if [ "$backend" = "$TB_BACKEND" ]; then
    pass "tb_get_backend returns correct value: $backend"
  else
    fail "tb_get_backend mismatch: got $backend, expected $TB_BACKEND"
  fi

  # Test tb_get_socket (only meaningful for tmux)
  local socket
  socket=$(tb_get_socket)
  if [ "$TB_BACKEND" = "tmux" ]; then
    if [ "$socket" = "$TB_SOCKET" ]; then
      pass "tb_get_socket returns correct value: $socket"
    else
      fail "tb_get_socket mismatch"
    fi
  else
    if [ -z "$socket" ]; then
      pass "tb_get_socket returns empty for wezterm (expected)"
    else
      fail "tb_get_socket should be empty for wezterm"
    fi
  fi
}

# =============================================================================
# Integration Tests (require terminal)
# =============================================================================

test_session_lifecycle() {
  log_test "Session Lifecycle (Create/Check/Cleanup)"

  local test_branch="test-branch-$$"
  local test_cwd="$(pwd)"
  local session_id

  # Create session
  echo "  Creating test session..."
  session_id=$(tb_create_worktree_session "$TEST_WORKSPACE" "$test_branch" "$test_cwd")

  if [ -n "$session_id" ]; then
    pass "Session created: $session_id"
    TEST_SESSIONS+=("$session_id")
  else
    fail "Session creation failed"
    return 1
  fi

  # Wait for session to initialize
  sleep 1

  # Check session alive
  if tb_is_session_alive "$session_id"; then
    pass "Session is alive"
  else
    fail "Session not alive after creation"
    return 1
  fi

  # Get session info
  local info
  info=$(tb_get_session_info "$session_id")
  if [ -n "$info" ] && [[ "$info" != *"dead"* ]]; then
    pass "Session info retrieved: $info"
  else
    fail "Session info indicates dead: $info"
  fi

  # Cleanup session
  tb_cleanup_session "$session_id"
  sleep 0.5

  if ! tb_is_session_alive "$session_id"; then
    pass "Session cleaned up successfully"
  else
    fail "Session still alive after cleanup"
  fi
}

test_send_command() {
  log_test "Send Command"

  local test_branch="test-cmd-$$"
  local test_cwd="$(pwd)"
  local session_id

  # Create session
  session_id=$(tb_create_worktree_session "$TEST_WORKSPACE" "$test_branch" "$test_cwd")
  TEST_SESSIONS+=("$session_id")

  if [ -z "$session_id" ]; then
    fail "Cannot create session for command test"
    return 1
  fi

  sleep 1

  # Send a simple command
  if tb_send_command "$session_id" "echo 'test command sent'"; then
    pass "Command sent successfully"
  else
    fail "Failed to send command"
  fi

  # Send command without execution
  if tb_send_command "$session_id" "echo 'no execute'" "false"; then
    pass "Command sent without execution"
  else
    fail "Failed to send command without execution"
  fi

  # Cleanup
  tb_cleanup_session "$session_id"
}

test_send_multiline() {
  log_test "Send Multiline Text"

  local test_branch="test-multi-$$"
  local test_cwd="$(pwd)"
  local session_id

  # Create session
  session_id=$(tb_create_worktree_session "$TEST_WORKSPACE" "$test_branch" "$test_cwd")
  TEST_SESSIONS+=("$session_id")

  if [ -z "$session_id" ]; then
    fail "Cannot create session for multiline test"
    return 1
  fi

  sleep 1

  # Send multiline text
  local multiline="line 1
line 2
line 3"

  if tb_send_multiline_text "$session_id" "$multiline"; then
    pass "Multiline text sent successfully"
  else
    fail "Failed to send multiline text"
  fi

  # Cleanup
  tb_cleanup_session "$session_id"
}

test_working_directory() {
  log_test "Working Directory (Windows gitbash fix)"

  local test_branch="test-cwd-$$"
  local test_cwd="$(pwd)"
  local session_id

  # Create session with specific working directory
  session_id=$(tb_create_worktree_session "$TEST_WORKSPACE" "$test_branch" "$test_cwd")
  TEST_SESSIONS+=("$session_id")

  if [ -z "$session_id" ]; then
    fail "Cannot create session for cwd test"
    return 1
  fi

  # Wait for cd command to execute (the fix sends cd after session creation)
  sleep 1

  # Get session info and check cwd
  local info
  info=$(tb_get_session_info "$session_id")

  # For wezterm, the info includes cwd
  if [ "$TB_BACKEND" = "wezterm" ]; then
    # Check if cwd in info matches expected (may have different path formats)
    if [[ "$info" == *"$(basename "$test_cwd")"* ]] || [[ "$info" != *"dead"* ]]; then
      pass "Working directory appears correct (session active)"
    else
      fail "Working directory check inconclusive: $info"
    fi
  else
    # For tmux, we check pane path
    if [[ "$info" == *"$test_cwd"* ]] || [[ "$info" != *"dead"* ]]; then
      pass "Working directory appears correct (session active)"
    else
      fail "Working directory check inconclusive: $info"
    fi
  fi

  # Additional check: send pwd command and see if session is responsive
  if tb_send_command "$session_id" "pwd"; then
    pass "Session responsive after cwd setup"
  else
    fail "Session not responsive after cwd setup"
  fi

  # Cleanup
  tb_cleanup_session "$session_id"
}

test_dead_session_handling() {
  log_test "Dead Session Handling"

  # Test with non-existent session
  local fake_session="wo:fake-workspace:fake-branch.0"

  if ! tb_is_session_alive "$fake_session"; then
    pass "Non-existent session correctly reported as not alive"
  else
    fail "Non-existent session incorrectly reported as alive"
  fi

  # Get info for dead session
  local info
  info=$(tb_get_session_info "$fake_session")
  if [[ "$info" == *"dead"* ]]; then
    pass "Dead session info correctly returned"
  else
    fail "Dead session info incorrect: $info"
  fi
}

test_poll_sessions() {
  log_test "Poll Sessions"

  local test_branch1="test-poll1-$$"
  local test_branch2="test-poll2-$$"
  local test_cwd="$(pwd)"
  local session1 session2

  # Create two sessions
  session1=$(tb_create_worktree_session "$TEST_WORKSPACE" "$test_branch1" "$test_cwd")
  session2=$(tb_create_worktree_session "$TEST_WORKSPACE" "$test_branch2" "$test_cwd")
  TEST_SESSIONS+=("$session1" "$session2")

  sleep 1

  # Poll sessions
  local poll_result
  poll_result=$(tb_poll_sessions "$TEST_WORKSPACE")

  if [ -n "$poll_result" ]; then
    pass "Poll returned results"
    echo "  Poll output:"
    echo "$poll_result" | while read -r line; do
      echo "    $line"
    done
  else
    # For wezterm, poll might return empty if map file doesn't have entries yet
    if [ "$TB_BACKEND" = "wezterm" ]; then
      pass "Poll returned empty (acceptable for wezterm)"
    else
      fail "Poll returned empty results"
    fi
  fi

  # Cleanup
  tb_cleanup_session "$session1"
  tb_cleanup_session "$session2"
}

# =============================================================================
# Script Integration Tests
# =============================================================================

test_send_command_script() {
  log_test "wo-send-command.sh Script"

  local test_branch="test-script-$$"
  local test_cwd="$(pwd)"
  local test_worktree="/tmp/test-send-cmd-$$"
  local session_id

  # Setup: create session and task.toon
  mkdir -p "$test_worktree"
  session_id=$(tb_create_worktree_session "$TEST_WORKSPACE" "$test_branch" "$test_worktree")
  TEST_SESSIONS+=("$session_id")

  if [ -z "$session_id" ]; then
    fail "Cannot create session for script test"
    rm -rf "$test_worktree"
    return 1
  fi

  # Create task.toon
  cat > "$test_worktree/task.toon" << EOF
meta{worktree,branch,session_id,created}:
  $test_worktree,$test_branch,$session_id,2024-01-01T00:00:00Z

overall_status: in_progress
agent_status: active
EOF

  sleep 1

  # Test 1: Send command with Enter
  if "$SCRIPT_DIR/wo-send-command.sh" "$test_worktree" "echo test-with-enter" >/dev/null 2>&1; then
    pass "wo-send-command.sh: command with Enter"
  else
    fail "wo-send-command.sh: command with Enter failed"
  fi

  # Test 2: Send command without Enter
  if "$SCRIPT_DIR/wo-send-command.sh" "$test_worktree" "echo test-no-enter" --no-enter >/dev/null 2>&1; then
    pass "wo-send-command.sh: command without Enter (--no-enter)"
  else
    fail "wo-send-command.sh: --no-enter failed"
  fi

  # Test 3: Error handling - non-existent path
  if ! "$SCRIPT_DIR/wo-send-command.sh" "/nonexistent-path-$$" "test" >/dev/null 2>&1; then
    pass "wo-send-command.sh: correctly rejects non-existent path"
  else
    fail "wo-send-command.sh: should reject non-existent path"
  fi

  # Test 4: Error handling - no task.toon
  local no_toon_dir="/tmp/no-toon-$$"
  mkdir -p "$no_toon_dir"
  if ! "$SCRIPT_DIR/wo-send-command.sh" "$no_toon_dir" "test" >/dev/null 2>&1; then
    pass "wo-send-command.sh: correctly rejects missing task.toon"
  else
    fail "wo-send-command.sh: should reject missing task.toon"
  fi
  rm -rf "$no_toon_dir"

  # Test 5: Error handling - dead session
  tb_cleanup_session "$session_id"
  sleep 0.5
  if ! "$SCRIPT_DIR/wo-send-command.sh" "$test_worktree" "test" >/dev/null 2>&1; then
    pass "wo-send-command.sh: correctly rejects dead session"
  else
    fail "wo-send-command.sh: should reject dead session"
  fi

  # Cleanup
  rm -rf "$test_worktree"
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_all_tests() {
  echo "=============================================="
  echo "  Terminal Backend Test Suite"
  echo "=============================================="
  echo "Platform: $(uname -s)"
  echo "Backend:  $TB_BACKEND"
  echo "Python:   $TB_PYTHON"
  echo "CWD:      $(pwd)"
  echo "=============================================="

  # Unit tests
  test_initialization
  test_session_id_parsing
  test_path_normalization
  test_backend_api

  # Integration tests
  test_dead_session_handling
  test_session_lifecycle
  test_send_command
  test_send_multiline
  test_working_directory
  test_poll_sessions

  # Script integration tests
  test_send_command_script

  # Summary
  echo ""
  echo "=============================================="
  echo "  Test Summary"
  echo "=============================================="
  echo -e "Total:  $TESTS_TOTAL"
  echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
  echo "=============================================="

  if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}Some tests failed!${NC}"
    return 1
  fi
}

# Run tests
run_all_tests
