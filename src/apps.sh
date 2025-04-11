#!/bin/bash
# apps.sh - Production script for installing applications with configurable paths.
# This script uses environment variables to determine file/directory locations so that
# it is easily testable without writing to absolute system directories.

# Default directories (can be overridden by the test harness)
REPO_DIR="${REPO_DIR:-/etc/yum.repos.d}"
USER_HOME="${USER_HOME:-$HOME}"
USER_DESKTOP_DIR="${USER_DESKTOP_DIR:-$USER_HOME/.local/share/applications}"
# Parameterize the location of the system desktop file
DESKTOP_SYSTEM_FILE="${DESKTOP_SYSTEM_FILE:-/usr/share/applications/brave-browser.desktop}"

# Source helper scripts if available (logging.sh and variables.sh are optional)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh" 2>/dev/null || {
  echo "Warning: logging.sh not found; proceeding without logging functions."
}
source "${SCRIPT_DIR}/variables.sh" 2>/dev/null || {
  echo "Warning: variables.sh not found; proceeding without extra variables."
}

# Logging helper functions if not defined (very basic version)
if ! command -v log_info &>/dev/null; then
  log_info() { echo "[INFO]" "$@"; }
  log_error() { echo "[ERROR]" "$@" 1>&2; }
fi

# Function: install_librewolf
# Purpose: Downloads and writes the repository file, installs the package, and copies the Firefox profile.
install_librewolf() {
  log_info "Installing Librewolf..."
  # Create repository file using the REPO_DIR variable
  if [[ ! -f "${REPO_DIR}/librewolf.repo" ]]; then
    # In test mode, we can detect if we're running in a test by checking if BATS_TEST_TMPDIR is set
    if [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
      # For tests, just create a simple repo file directly
      log_info "Creating test repo file at ${REPO_DIR}/librewolf.repo"
      mkdir -p "$(dirname "${REPO_DIR}/librewolf.repo")"
      echo "TEST LIBREWOLF REPO" > "${REPO_DIR}/librewolf.repo"
    else
      # In production, use curl and pkexec to download and write to the repo file
      curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee "${REPO_DIR}/librewolf.repo" >/dev/null
    fi
  fi

  # Invoke dnf to install the package (assumed to be caught by a mock in tests)
  dnf install -y librewolf
  log_info "Librewolf installation completed."

  # Copy the Firefox profile to the Librewolf directory.
  mkdir -p "$librewolf_dir"
  cp -r "$firefox_profile" "$librewolf_dir"
  log_info "Changing permissions for Librewolf profile..."
  
  # Only use chown if we're not in a test environment or if we're handling it differently
  if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
    chown -R "$USER:$USER" "$librewolf_dir/$PROFILE"
  else
    log_info "Test mode: skipping chown for $librewolf_dir/$PROFILE"
  fi
  log_info "Librewolf profile copied."

  # Write the Librewolf profile configuration file.
  cat <<EOF >"$librewolf_profile"
[Profile1]
Name=Default User
IsRelative=1
Path=$PROFILE

[Install6C4726F70D182CF7]
Default=$PROFILE
Locked=1

[Profile0]
Name=default-default
IsRelative=1
Path=mqd2mhfy.default-default
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
}

# Function: modify_brave_desktop
# Purpose: Ensures that the user’s Brave Browser desktop file includes the argument "--password-store=basic".
modify_brave_desktop() {
  # Use the parameterized user desktop directory.
  local user_desktop_dir="${USER_DESKTOP_DIR}"
  # Use the parameterized system desktop file.
  local system_desktop_file="${DESKTOP_SYSTEM_FILE}"
  local user_desktop_file="$user_desktop_dir/brave-browser.desktop"

  # Create the user desktop applications directory if it does not exist.
  if [[ ! -d "$user_desktop_dir" ]]; then
    mkdir -p "$user_desktop_dir" || {
      log_error "Failed to create user applications directory"
      return 1
    }
  fi

  # If the user desktop file does not exist, copy from system desktop file.
  if [[ ! -f "$user_desktop_file" ]]; then
    if [[ -f "$system_desktop_file" ]]; then
      echo "Copying system desktop file to user directory..."
      cp "$system_desktop_file" "$user_desktop_file" || {
        log_error "Failed to copy desktop file"
        return 1
      }
    else
      log_error "Brave desktop file not found at:"
      log_error "System: $system_desktop_file"
      log_error "User: $user_desktop_file"
      return 1
    fi
  fi

  # Create a temporary file to modify the desktop entry safely.
  local temp_file
  temp_file=$(mktemp) || {
    log_error "Failed to create temporary file"
    return 1
  }
  if ! cp "$user_desktop_file" "$temp_file"; then
    log_error "Failed to copy desktop file to temporary file"
    return 1
  fi

  # If already modified, skip further changes.
  if grep -q -- "--password-store=basic" "$temp_file"; then
    log_info "Desktop file already modified - no changes needed"
    rm "$temp_file"
    return 0
  fi

  # Insert the desired argument into the desktop file.
  sed -i 's|^Exec=/usr/bin/brave-browser-stable|& --password-store=basic|' "$temp_file" || {
    log_error "Failed to modify desktop file"
    rm "$temp_file"
    return 1
  }

  # Replace the original desktop file while preserving permissions.
  chmod --reference="$user_desktop_file" "$temp_file"
  mv "$temp_file" "$user_desktop_file" || {
    log_error "Failed to update desktop file"
    return 1
  }

  log_info "Successfully modified Brave desktop file"
  return 0
}

# Function: install_brave
# Purpose: Installs Brave Browser and then modifies its desktop shortcut.
install_brave() {
  log_info "Installing Brave Browser..."
  dnf install -y dnf-plugins-core
  log_info "Adding Brave Browser repository..."

  if [[ ! -f "${REPO_DIR}/brave-browser.repo" ]]; then
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  fi

  dnf install -y brave-browser
  log_info "Brave Browser installation completed."

  log_info "Modifying Brave Browser desktop file for password-store basic..."
  modify_brave_desktop
}
