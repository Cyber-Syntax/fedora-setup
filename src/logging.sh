#!/usr/bin/env bash

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Default log level
LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Default log file location
LOG_DIR="${LOG_DIR:-/var/log}"
LOG_FILE=""

# Initialize logging
init_logging() {
  # Check if LOG_DIR is set and not empty
  if [[ -z "${LOG_DIR}" ]]; then
    LOG_DIR="/var/log" # Set default if not defined
  fi

  local timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")
  LOG_FILE="${LOG_DIR}/setup-${timestamp}.log"

  # Create log directory if it doesn't exist
  mkdir -p "$LOG_DIR" || return 1

  # Create log file and set permissions
  touch "$LOG_FILE" || return 1
  chmod 644 "$LOG_FILE" || return 1

  # Initialize logging before first use
  _log "INFO" "Logging initialized to $LOG_FILE"

  return 0
}

# Internal logging function
_log() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Log to file
  echo "[$timestamp] [$level] $msg" >>"$LOG_FILE"

  # Log to console with color based on level
  case "$level" in
  "DEBUG") [[ $LOG_LEVEL -le $LOG_LEVEL_DEBUG ]] && echo -e "\033[36m[DEBUG]\033[0m $msg" ;;
  "INFO") [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]] && echo -e "\033[32m[INFO]\033[0m $msg" ;;
  "WARN") [[ $LOG_LEVEL -le $LOG_LEVEL_WARN ]] && echo -e "\033[33m[WARN]\033[0m $msg" ;;
  "ERROR") [[ $LOG_LEVEL -le $LOG_LEVEL_ERROR ]] && echo -e "\033[31m[ERROR]\033[0m $msg" >&2 ;;
  esac
}

# Public logging functions
log_debug() { _log "DEBUG" "$1"; }
log_info() { _log "INFO" "$1"; }
log_warn() { _log "WARN" "$1"; }
log_error() { _log "ERROR" "$1"; }

# Log command execution
log_cmd() {
  local cmd="$1"
  log_debug "Executing command: $cmd"

  # Execute command and capture output
  local output
  if output=$($cmd 2>&1); then
    log_debug "Command succeeded: $output"
    echo "$output"
    return 0
  else
    local ret=$?
    log_error "Command failed with exit code $ret: $output"
    return $ret
  fi
}

# Cleanup old logs
cleanup_old_logs() {
  local days="${1:-7}" # Default to 7 days
  local old_logs

  log_debug "Cleaning up logs older than $days days"

  # Find and remove old log files
  old_logs=$(find "$LOG_DIR" -name "setup-*.log" -mtime "+$days" 2>/dev/null)
  if [[ -n "$old_logs" ]]; then
    echo "$old_logs" | while read -r log; do
      rm "$log" && log_debug "Removed old log: $log"
    done
  fi
}
