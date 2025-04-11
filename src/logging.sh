#!/usr/bin/env bash

# Log levels - only define if not already defined
if [[ -z "${LOG_LEVEL_DEBUG+x}" ]]; then
  readonly LOG_LEVEL_DEBUG=0
  readonly LOG_LEVEL_INFO=1
  readonly LOG_LEVEL_WARN=2
  readonly LOG_LEVEL_ERROR=3
fi

# Default log level
LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Default log file location - always use repository logs directory
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
DEFAULT_LOG_DIR="$_SCRIPT_DIR/logs"
LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
LOG_FILE=""
MAX_LOG_SIZE=$((3 * 1024 * 1024))  # 3MB in bytes
MAX_BACKUPS=3

# Initialize logging
init_logging() {
  # Always use the logs directory in the project
  LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"

  # Ensure LOG_DIR exists with proper permissions
  if [[ ! -d "$LOG_DIR" ]]; then
    echo "Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR" 2>/dev/null
    # Check if directory was created successfully
    if [[ ! -d "$LOG_DIR" ]]; then
      echo "ERROR: Failed to create log directory: $LOG_DIR" >&2
      # Fall back to using /tmp as a last resort
      LOG_DIR="/tmp"
      echo "WARNING: Falling back to temporary directory for logs: $LOG_DIR" >&2
    fi
  fi

  # Make sure LOG_FILE is now consistently set
  LOG_FILE="${LOG_DIR}/fedora-setup.log"
  
  # Check if we need to rotate the log file
  if [[ -f "$LOG_FILE" ]]; then
    local _file_size
    _file_size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    
    if (( _file_size > MAX_LOG_SIZE )); then
      rotate_logs
    fi
  fi

  # Create log file or ensure it's writable
  if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: Failed to create log file: $LOG_FILE" >&2
    # Try creating a uniquely named file in the log directory as fallback
    local _timestamp
    _timestamp=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="${LOG_DIR}/fedora-setup_${_timestamp}.log"
    if ! touch "$LOG_FILE" 2>/dev/null; then
      echo "ERROR: Still failed to create log file at $LOG_FILE" >&2
      # Last resort: use stderr only, disable file logging
      LOG_FILE=""
      return 1
    fi
    echo "WARNING: Created alternative log file: $LOG_FILE" >&2
  fi
  
  # Set proper permissions (readable by all, writable by owner)
  if [[ -n "$LOG_FILE" ]]; then
    chmod 644 "$LOG_FILE" 2>/dev/null || {
      echo "WARNING: Failed to set permissions on log file" >&2
    }
  fi

  # Initialize logging before first use
  if [[ -n "$LOG_FILE" ]]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO] Logging initialized to $LOG_FILE" >> "$LOG_FILE"
    echo "Logging to: $LOG_FILE"
  else
    echo "WARNING: File logging disabled due to permission issues"
  fi
  return 0
}

# Rotate logs when they exceed the size limit
rotate_logs() {
  # Check if LOG_FILE is valid before attempting rotation
  if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "WARNING: Cannot rotate non-existent log file" >&2
    return 1
  fi

  # Remove the oldest backup if we have reached MAX_BACKUPS
  if [[ -f "${LOG_FILE}.bak${MAX_BACKUPS}" ]]; then
    rm -f "${LOG_FILE}.bak${MAX_BACKUPS}" 2>/dev/null
  fi
  
  # Shift all existing backups
  for (( i=MAX_BACKUPS-1; i>=1; i-- )); do
    local _prev=$i
    local _next=$((i+1))
    
    if [[ -f "${LOG_FILE}.bak${_prev}" ]]; then
      mv "${LOG_FILE}.bak${_prev}" "${LOG_FILE}.bak${_next}" 2>/dev/null
    fi
  done
  
  # Move the current log to backup.1
  if [[ -f "$LOG_FILE" ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.bak1" 2>/dev/null
  fi
  
  # Create a new log file
  if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: Failed to create new log file after rotation" >&2
    return 1
  fi
  
  chmod 644 "$LOG_FILE" 2>/dev/null || {
    echo "WARNING: Failed to set permissions on rotated log file" >&2
  }
  
  # Log that rotation has occurred
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] [INFO] Log file rotated due to size > ${MAX_LOG_SIZE} bytes" >> "$LOG_FILE"
}

# Internal logging function
_log() {
  local _level="$1"
  local _msg="$2"
  local _timestamp
  _timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  # Make sure LOG_FILE is set
  if [[ -z "$LOG_FILE" ]]; then
    # If LOG_FILE is not set, initialize logging
    init_logging || {
      # If initialization fails, we'll only log to console
      case "$_level" in
      "DEBUG") [[ $LOG_LEVEL -le $LOG_LEVEL_DEBUG ]] && echo -e "\033[36m[DEBUG]\033[0m $_msg" ;;
      "INFO") [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]] && echo -e "\033[32m[INFO]\033[0m $_msg" ;;
      "WARN") [[ $LOG_LEVEL -le $LOG_LEVEL_WARN ]] && echo -e "\033[33m[WARN]\033[0m $_msg" ;;
      "ERROR") [[ $LOG_LEVEL -le $LOG_LEVEL_ERROR ]] && echo -e "\033[31m[ERROR]\033[0m $_msg" >&2 ;;
      esac
      return 0
    }
  fi

  # Check if we have a valid log file to write to
  if [[ -n "$LOG_FILE" ]]; then
    # Log to file - silently ignore errors
    echo "[$_timestamp] [$_level] $_msg" >> "$LOG_FILE" 2>/dev/null
  fi

  # Log to console with color based on level
  case "$_level" in
  "DEBUG") [[ $LOG_LEVEL -le $LOG_LEVEL_DEBUG ]] && echo -e "\033[36m[DEBUG]\033[0m $_msg" ;;
  "INFO") [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]] && echo -e "\033[32m[INFO]\033[0m $_msg" ;;
  "WARN") [[ $LOG_LEVEL -le $LOG_LEVEL_WARN ]] && echo -e "\033[33m[WARN]\033[0m $_msg" ;;
  "ERROR") [[ $LOG_LEVEL -le $LOG_LEVEL_ERROR ]] && echo -e "\033[31m[ERROR]\033[0m $_msg" >&2 ;;
  esac
}

# Public logging functions
log_debug() { 
  _log "DEBUG" "$1" || echo "[DEBUG] $1"
}

log_info() { 
  _log "INFO" "$1" || echo "[INFO] $1"
}

log_warn() { 
  _log "WARN" "$1" || echo "[WARN] $1" 
}

log_error() { 
  _log "ERROR" "$1" || echo "[ERROR] $1" >&2
}

# Add a success log level function
log_success() {
  _log "INFO" "$1" || echo "[SUCCESS] $1"
  echo -e "\033[32m[SUCCESS]\033[0m $1"
}

# Log command execution
log_cmd() {
  local _cmd="$1"
  log_debug "Executing command: $_cmd"

  # Execute command and capture output
  local _output
  if _output=$($_cmd 2>&1); then
    log_debug "Command succeeded: $_output"
    echo "$_output"
    return 0
  else
    local _ret=$?
    log_error "Command failed with exit code $_ret: $_output"
    return $_ret
  fi
}

# Cleanup old logs - keep this for backward compatibility
cleanup_old_logs() {
  local _days="${1:-7}" # Default to 7 days
  local _old_logs

  log_debug "Cleaning up logs older than $_days days"

  # Make sure LOG_DIR exists before attempting to find files in it
  if [[ ! -d "$LOG_DIR" ]]; then
    log_warn "Log directory $LOG_DIR does not exist, cannot clean up logs"
    return 1
  fi

  # Find and remove old log files
  _old_logs=$(find "$LOG_DIR" -name "*.bak*" -mtime "+$_days" 2>/dev/null)
  if [[ -n "$_old_logs" ]]; then
    echo "$_old_logs" | while read -r log; do
      rm "$log" 2>/dev/null && log_debug "Removed old log: $log"
    done
  fi
}
