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

# Default log file location - determine based on script and permissions
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
DEFAULT_LOG_DIR="$_SCRIPT_DIR/logs"
LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
LOG_FILE=""
MAX_LOG_SIZE=$((3 * 1024 * 1024))  # 3MB in bytes
MAX_BACKUPS=3

# Initialize logging
init_logging() {
  # If we're root, we can use /var/log
  if [[ $EUID -eq 0 ]]; then
    # Root can write to /var/log
    LOG_DIR="${LOG_DIR:-/var/log/fedora-setup}"
  else
    # Non-root should use the logs directory in the project
    LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
  fi

  # Make sure LOG_FILE is now consistently set
  LOG_FILE="${LOG_DIR}/fedora-setup.log"
  
  # Create log directory with proper permissions
  mkdir -p "$LOG_DIR" 2>/dev/null || {
    # If mkdir failed, we might need sudo
    if [[ $EUID -ne 0 ]]; then
      echo "Creating log directory with sudo..."
      sudo mkdir -p "$LOG_DIR" || {
        echo "Failed to create log directory: $LOG_DIR" >&2
        return 1
      }
      sudo chown "$(id -u):$(id -g)" "$LOG_DIR" || {
        echo "Failed to set ownership on log directory" >&2
        return 1
      }
    else
      echo "Failed to create log directory: $LOG_DIR" >&2
      return 1
    fi
  }

  # Check if we need to rotate the log file
  if [[ -f "$LOG_FILE" ]]; then
    local file_size
    file_size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    
    if (( file_size > MAX_LOG_SIZE )); then
      rotate_logs
    fi
  fi

  # Create log file or ensure it's writable
  touch "$LOG_FILE" 2>/dev/null || {
    # If touch failed, we might need sudo
    if [[ $EUID -ne 0 ]]; then
      echo "Creating log file with sudo..."
      sudo touch "$LOG_FILE" || {
        echo "Failed to create log file: $LOG_FILE" >&2
        return 1
      }
      sudo chown "$(id -u):$(id -g)" "$LOG_FILE" || {
        echo "Failed to set ownership on log file" >&2
        return 1
      }
    else
      echo "Failed to create log file: $LOG_FILE" >&2
      return 1
    fi
  }
  
  # Set proper permissions (readable by all, writable by owner)
  chmod 644 "$LOG_FILE" 2>/dev/null || {
    if [[ $EUID -ne 0 ]]; then
      sudo chmod 644 "$LOG_FILE" || {
        echo "Failed to set permissions on log file" >&2
        return 1
      }
    else
      echo "Failed to set permissions on log file" >&2
      return 1
    fi
  }

  # Initialize logging before first use
  _log "INFO" "Logging initialized to $LOG_FILE"
  echo "Logging to: $LOG_FILE"
  return 0
}

# Rotate logs when they exceed the size limit
rotate_logs() {
  # Remove the oldest backup if we have reached MAX_BACKUPS
  if [[ -f "${LOG_FILE}.bak${MAX_BACKUPS}" ]]; then
    rm -f "${LOG_FILE}.bak${MAX_BACKUPS}"
  fi
  
  # Shift all existing backups
  for (( i=MAX_BACKUPS-1; i>=1; i-- )); do
    local prev=$i
    local next=$((i+1))
    
    if [[ -f "${LOG_FILE}.bak${prev}" ]]; then
      mv "${LOG_FILE}.bak${prev}" "${LOG_FILE}.bak${next}"
    fi
  done
  
  # Move the current log to backup.1
  if [[ -f "$LOG_FILE" ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.bak1"
  fi
  
  # Create a new log file
  touch "$LOG_FILE" || return 1
  chmod 644 "$LOG_FILE" || return 1
  
  # Log that rotation has occurred
  _log "INFO" "Log file rotated due to size > ${MAX_LOG_SIZE} bytes"
}

# Internal logging function
_log() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  # Make sure LOG_FILE is set
  if [[ -z "$LOG_FILE" ]]; then
    # If LOG_FILE is not set, initialize logging
    init_logging || {
      echo "ERROR: Failed to initialize logging" >&2
      return 1
    }
  fi

  # Check if log file exists and is writable
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "ERROR: Log file $LOG_FILE does not exist, trying to create it" >&2
    touch "$LOG_FILE" 2>/dev/null || {
      if [[ $EUID -ne 0 ]]; then
        sudo touch "$LOG_FILE" && sudo chmod 644 "$LOG_FILE" && sudo chown "$(id -u):$(id -g)" "$LOG_FILE" || {
          echo "ERROR: Could not create log file even with sudo" >&2
          return 1
        }
      else
        touch "$LOG_FILE" && chmod 644 "$LOG_FILE" || {
          echo "ERROR: Could not create log file as root" >&2
          return 1
        }
      fi
    }
  elif [[ ! -w "$LOG_FILE" ]]; then
    echo "ERROR: Log file $LOG_FILE is not writable, fixing permissions" >&2
    if [[ $EUID -ne 0 ]]; then
      sudo chmod 644 "$LOG_FILE" && sudo chown "$(id -u):$(id -g)" "$LOG_FILE" || {
        echo "ERROR: Could not fix log file permissions even with sudo" >&2
        return 1
      }
    else 
      chmod 644 "$LOG_FILE" || {
        echo "ERROR: Could not fix log file permissions as root" >&2
        return 1
      }
    fi
  fi

  # Log to file
  echo "[$timestamp] [$level] $msg" >>"$LOG_FILE"
  # If there's an error writing to log, we don't want it to fail silently
  if [[ $? -ne 0 ]]; then
    echo "Error writing to log file $LOG_FILE" >&2
  fi

  # Log to console with color based on level
  case "$level" in
  "DEBUG") [[ $LOG_LEVEL -le $LOG_LEVEL_DEBUG ]] && echo -e "\033[36m[DEBUG]\033[0m $msg" ;;
  "INFO") [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]] && echo -e "\033[32m[INFO]\033[0m $msg" ;;
  "WARN") [[ $LOG_LEVEL -le $LOG_LEVEL_WARN ]] && echo -e "\033[33m[WARN]\033[0m $msg" ;;
  "ERROR") [[ $LOG_LEVEL -le $LOG_LEVEL_ERROR ]] && echo -e "\033[31m[ERROR]\033[0m $msg" >&2 ;;
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

# Cleanup old logs - keep this for backward compatibility
cleanup_old_logs() {
  local days="${1:-7}" # Default to 7 days
  local old_logs

  log_debug "Cleaning up logs older than $days days"

  # Find and remove old log files
  old_logs=$(find "$LOG_DIR" -name "*.bak*" -mtime "+$days" 2>/dev/null)
  if [[ -n "$old_logs" ]]; then
    echo "$old_logs" | while read -r log; do
      rm "$log" && log_debug "Removed old log: $log"
    done
  fi
}
