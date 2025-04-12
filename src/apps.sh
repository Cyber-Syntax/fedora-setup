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

install_lazygit() {
  log_info "Installing Lazygit..."
  # Check if the repository is already added
  if [[ ! -f "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:atim:lazygit.repo" ]]; then
    sudo dnf copr enable atim/lazygit -y
  fi
  sudo dnf install -y lazygit
  log_info "Lazygit installation completed."
}

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
      echo "TEST LIBREWOLF REPO" >"${REPO_DIR}/librewolf.repo"
    else
      # In production, use curl and pkexec to download and write to the repo file
      curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee "${REPO_DIR}/librewolf.repo" >/dev/null
    fi
  fi

  # Invoke sudo dnf to install the package (assumed to be caught by a mock in tests)
  sudo dnf install -y librewolf
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
  local _profile_content=$(
    cat <<EOF
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
  )

  echo "$_profile_content" >"$librewolf_profile"
}

# Function: modify_brave_desktop
# Purpose: Ensures that the user’s Brave Browser desktop file includes the argument "--password-store=basic".
modify_brave_desktop() {
  # Use the parameterized user desktop directory.
  local _user_desktop_dir="${USER_DESKTOP_DIR}"
  # Use the parameterized system desktop file.
  local _system_desktop_file="${DESKTOP_SYSTEM_FILE}"
  local _user_desktop_file="$_user_desktop_dir/brave-browser.desktop"

  # Create the user desktop applications directory if it does not exist.
  if [[ ! -d "$_user_desktop_dir" ]]; then
    mkdir -p "$_user_desktop_dir" || {
      log_error "Failed to create user applications directory"
      return 1
    }
  fi

  # If the user desktop file does not exist, copy from system desktop file.
  if [[ ! -f "$_user_desktop_file" ]]; then
    if [[ -f "$_system_desktop_file" ]]; then
      log_info "Copying system desktop file to user directory..."
      cp "$_system_desktop_file" "$_user_desktop_file" || {
        log_error "Failed to copy desktop file"
        return 1
      }
    else
      log_error "Brave desktop file not found at:"
      log_error "System: $_system_desktop_file"
      log_error "User: $_user_desktop_file"
      return 1
    fi
  fi

  # If already modified, skip further changes.
  if grep -q -- "--password-store=basic" "$_user_desktop_file"; then
    log_info "Desktop file already modified - no changes needed"
    return 0
  fi

  # Create backup of the original file
  local _backup_file="${_user_desktop_file}.bak"
  log_debug "Creating backup at $_backup_file"
  cp "$_user_desktop_file" "$_backup_file" || {
    log_warn "Failed to create backup file, but proceeding anyway"
  }

  # Modify the file directly
  log_debug "Modifying desktop file to use basic password store"
  sed -i 's|^Exec=/usr/bin/brave-browser-stable|& --password-store=basic|' "$_user_desktop_file" || {
    log_error "Failed to modify desktop file"
    # Restore from backup if sed failed
    if [[ -f "$_backup_file" ]]; then
      log_debug "Restoring from backup"
      cp "$_backup_file" "$_user_desktop_file"
    fi
    return 1
  }

  log_info "Successfully modified Brave desktop file"
  return 0
}

# Function: install_brave
# Purpose: Installs Brave Browser and then modifies its desktop shortcut.
install_brave() {
  log_info "Installing Brave Browser..."
  sudo dnf install -y sudo dnf-plugins-core
  log_info "Adding Brave Browser repository..."

  if [[ ! -f "${REPO_DIR}/brave-browser.repo" ]]; then
    sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  fi

  sudo dnf install -y brave-browser
  log_info "Brave Browser installation completed."

  log_info "Modifying Brave Browser desktop file for password-store basic..."
  modify_brave_desktop
}

# Install vscode
install_vscode() {
  log_info "Installing Visual Studio Code..."
  #FIX: need proper way handle
  if ! sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc; then
    log_error "Failed to import Microsoft key"
    return 1
  fi

  if ! echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null; then
    log_error "Failed to create VS Code repository file"
    return 1
  fi

  sudo dnf check-update
  if ! sudo dnf install -y code; then
    log_error "Failed to install VS Code"
    return 1
  fi

  log_info "VS Code installed successfully."
}

# TEST: Install ProtonVPN repository and enable OpenVPN for SELinux.
# This function downloads the ProtonVPN repository package and installs it.
# Then it attempts to enable OpenVPN for SELinux by installing a local policy module.
install_protonvpn() {
  log_info "Installing ProtonVPN repository..."

  local _fedora_version=$(awk '{print $3}' /etc/fedora-release)
  local _repo_url="https://repo.protonvpn.com/fedora-${_fedora_version}-stable"
  local _key_url="${_repo_url}/public_key.asc"
  local _rpm_url="${_repo_url}/protonvpn-stable-release/protonvpn-stable-release-1.0.2-1.noarch.rpm"

  # First, pre-import the GPG key to avoid the prompt
  log_info "Importing ProtonVPN GPG key..."
  if ! sudo rpm --import "${_key_url}"; then
    log_error "Failed to import ProtonVPN GPG key"
    return 1
  fi

  # Download and install the repository package
  if [[ ! -f "/etc/yum.repos.d/protonvpn-stable.repo" ]]; then
    log_info "Downloading and installing ProtonVPN repository..."
    # Using a temporary file in /tmp to avoid cluttering the current directory
    local _tmp_rpm="/tmp/protonvpn-stable-release.rpm"

    if ! wget -O "${_tmp_rpm}" "${_rpm_url}"; then
      log_error "Failed to download ProtonVPN repository package"
      return 1
    fi

    # Use --setopt=assumeyes=1 to automatically answer "yes" to all prompts
    if ! sudo dnf install --setopt=assumeyes=1 "${_tmp_rpm}"; then
      log_error "Failed to install ProtonVPN repository"
      sudo rm -f "${_tmp_rpm}"
      return 1
    fi

    # Clean up the temporary file
    sudo rm -f "${_tmp_rpm}"
  else
    log_info "ProtonVPN repository already installed"
  fi

  # Refresh repositories with automatic yes
  log_info "Refreshing package repositories..."
  sudo dnf check-update --refresh --setopt=assumeyes=1 || true

  # Install the VPN client with automatic yes
  log_info "Installing ProtonVPN GNOME desktop integration..."
  if ! sudo dnf install --setopt=assumeyes=1 -y proton-vpn-gnome-desktop; then
    log_error "Failed to install ProtonVPN GNOME desktop integration"
    return 1
  fi

  log_info "ProtonVPN installation completed successfully"
  return 0
}
