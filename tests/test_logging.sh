#!/usr/bin/env bats
# tests/test_logging.sh - Unit tests for logging.sh

setup() {
  # Get the absolute path to the repository root
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  # Create a temporary directory for test artifacts
  export BATS_TEST_TMPDIR=$(mktemp -d -p "${BATS_TMPDIR:-/tmp}" "logging_test.XXXXXX")
  export LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$LOG_DIR"

  # Source the logging module
  source "${REPO_ROOT}/src/logging.sh" || {
    echo "Failed to source logging.sh. This test needs the actual logging.sh file."
    return 1
  }
}

teardown() {
  if [[ -d "$BATS_TEST_TMPDIR" ]]; then
    rm -rf "$BATS_TEST_TMPDIR"
  fi
}

@test "init_logging creates log file and sets permissions" {
  init_logging

  # Verify log file was created
  [ -f "$LOG_FILE" ]
  
  # Check permissions (should be 644)
  local perms=$(stat -c "%a" "$LOG_FILE")
  [ "$perms" = "644" ]
  
  # Ensure it contains the initialization message
  grep -q "Logging initialized to" "$LOG_FILE"
}

@test "log functions write to log file with correct level" {
  init_logging
  
  # Test each log level
  log_debug "Debug test message"
  log_info "Info test message"
  log_warn "Warning test message"
  log_error "Error test message"
  
  # Verify all messages were written to log file
  grep -q "\[DEBUG\] Debug test message" "$LOG_FILE"
  grep -q "\[INFO\] Info test message" "$LOG_FILE"
  grep -q "\[WARN\] Warning test message" "$LOG_FILE"
  grep -q "\[ERROR\] Error test message" "$LOG_FILE"
}

@test "log_cmd executes commands and logs output" {
  init_logging
  
  # Create a test command that succeeds
  run log_cmd "echo 'Command executed successfully'"
  
  # Verify command executed and returned output
  [ "$status" -eq 0 ]
  [ "$output" = "Command executed successfully" ]
  
  # Verify command was logged
  grep -q "Executing command: echo 'Command executed successfully'" "$LOG_FILE"
  grep -q "Command succeeded: Command executed successfully" "$LOG_FILE"
  
  # Test a failing command
  run log_cmd "false"
  
  # Verify command failed
  [ "$status" -eq 1 ]
  
  # Verify failure was logged
  grep -q "Command failed with exit code 1" "$LOG_FILE"
}

@test "cleanup_old_logs removes older logs" {
  init_logging
  
  # Create some "old" log files with modified timestamps
  for i in {1..3}; do
    touch "$LOG_DIR/setup-old$i.log"
    # Set mtime to 10 days ago
    touch -d "10 days ago" "$LOG_DIR/setup-old$i.log"
  done
  
  # Set log directory path for the function
  LOG_DIR="$BATS_TEST_TMPDIR/logs"
  
  # Run cleanup with 7 days retention
  cleanup_old_logs 7
  
  # Verify old logs were removed
  [ ! -f "$LOG_DIR/setup-old1.log" ]
  [ ! -f "$LOG_DIR/setup-old2.log" ]
  [ ! -f "$LOG_DIR/setup-old3.log" ]
  
  # Current log file should still exist
  [ -f "$LOG_FILE" ]
}

@test "log_level controls console output" {
  # Test with different log levels
  
  # INFO level (default)
  LOG_LEVEL=$LOG_LEVEL_INFO
  init_logging
  
  # Capture debug message (shouldn't appear in console)
  run bash -c "source $REPO_ROOT/src/logging.sh && LOG_FILE='$LOG_FILE' log_debug 'Debug message'"
  [ -z "$output" ]
  
  # Capture info message (should appear)
  run bash -c "source $REPO_ROOT/src/logging.sh && LOG_FILE='$LOG_FILE' log_info 'Info message'"
  [ -n "$output" ]
  
  # DEBUG level (everything should appear)
  LOG_LEVEL=$LOG_LEVEL_DEBUG
  
  # Capture debug message (should now appear)
  run bash -c "source $REPO_ROOT/src/logging.sh && LOG_LEVEL=$LOG_LEVEL_DEBUG LOG_FILE='$LOG_FILE' log_debug 'Debug message'"
  [ -n "$output" ]
}
