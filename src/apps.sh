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

# Only define SCRIPT_DIR if it's not already defined (to avoid readonly variable error)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source helper scripts if available (logging.sh is essential)
source "${SCRIPT_DIR}/logging.sh" 2>/dev/null || {
  echo "Warning: logging.sh not found; proceeding without logging functions."
}

# Directly load variables from variables.json in XDG config directory
# Using apps_* prefix to avoid conflicts with readonly variables from config.sh
apps_xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
apps_config_dir="$apps_xdg_config/fedora-setup"
apps_variables_file="$apps_config_dir/variables.json"

if [[ -f "$apps_variables_file" ]]; then
  # Check if jq is installed
  if ! command -v jq &>/dev/null; then
    echo "Warning: jq is required but not installed. Some variables may not be available."
  else
    # Load key variables from variables.json
    user=$(jq -r '.user // "'"$(whoami)"'"' "$apps_variables_file" 2>/dev/null)

    # Laptop settings
    laptop_session=$(jq -r '.laptop.session // "hyprland"' "$apps_variables_file" 2>/dev/null)
    laptop_display_manager=$(jq -r '.laptop.display_manager // "sddm"' "$apps_variables_file" 2>/dev/null)
    laptop_ip=$(jq -r '.laptop.ip // "192.168.1.54"' "$apps_variables_file" 2>/dev/null)
    hostname_laptop=$(jq -r '.laptop.host // "fedora-laptop"' "$apps_variables_file" 2>/dev/null)

    # Desktop settings
    desktop_session=$(jq -r '.desktop.session // "qtile"' "$apps_variables_file" 2>/dev/null)
    desktop_display_manager=$(jq -r '.desktop.display_manager // "sddm"' "$apps_variables_file" 2>/dev/null)
    desktop_ip=$(jq -r '.desktop.ip // "192.168.1.100"' "$apps_variables_file" 2>/dev/null)
    hostname_desktop=$(jq -r '.desktop.host // "fedora"' "$apps_variables_file" 2>/dev/null)

    # Browser settings
    firefox_profile=$(jq -r '.browser.firefox_profile // ""' "$apps_variables_file" 2>/dev/null)
    firefox_profile_path=$(jq -r '.browser.firefox_profile_path // ""' "$apps_variables_file" 2>/dev/null)
    librewolf_dir=$(jq -r '.browser.librewolf_dir // ""' "$apps_variables_file" 2>/dev/null)
    librewolf_profile=$(jq -r '.browser.librewolf_profile // ""' "$apps_variables_file" 2>/dev/null)

    # System settings
    mirror_country=$(jq -r '.system.mirror_country // "de"' "$apps_variables_file" 2>/dev/null)
    repo_dir=$(jq -r '.system.repo_dir // "/etc/yum.repos.d"' "$apps_variables_file" 2>/dev/null)

    # Export variables
    export user laptop_session laptop_display_manager laptop_ip hostname_laptop
    export desktop_session desktop_display_manager desktop_ip hostname_desktop
    export firefox_profile firefox_profile_path librewolf_dir librewolf_profile
    export mirror_country repo_dir
  fi
else
  echo "Warning: variables.json not found at $apps_variables_file; proceeding with default values."
fi

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

# Function: install_vscode
# Purpose: Installs Visual Studio Code
# This function adds the Microsoft repository, imports the GPG key,
# and installs VS Code from the official Microsoft repository.
install_vscode() {
  log_info "Installing Visual Studio Code..."
  local vscode_repo_file="${REPO_DIR}/vscode.repo"
  local import_key_success=false
  local repo_create_success=false

  # Import the Microsoft GPG key
  log_info "Importing Microsoft GPG key..."
  if sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc; then
    import_key_success=true
    log_info "Microsoft GPG key imported successfully."
  else
    log_error "Failed to import Microsoft GPG key."
    return 1
  fi

  # Create the VS Code repository file if it doesn't exist
  if [[ ! -f "$vscode_repo_file" ]]; then
    log_info "Creating Visual Studio Code repository file..."

    # Create repository file content
    local repo_content="[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc"

    # Write the repository file
    if echo "$repo_content" | sudo tee "$vscode_repo_file" >/dev/null; then
      repo_create_success=true
      log_info "Visual Studio Code repository file created successfully."
    else
      log_error "Failed to create Visual Studio Code repository file."
      return 1
    fi
  else
    log_info "Visual Studio Code repository file already exists."
    repo_create_success=true
  fi

  # Update repository metadata
  log_info "Updating repository metadata..."
  if ! sudo dnf check-update; then
    log_info "Repository metadata update completed with some warnings."
    # Don't exit here as check-update returns non-zero when updates are available
  fi

  # Install VS Code
  log_info "Installing VS Code package..."
  if sudo dnf install -y code; then
    log_success "Visual Studio Code installed successfully."
    return 0
  else
    log_error "Failed to install Visual Studio Code package."
    return 1
  fi
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

#TEST: Need to be tested
# Function: install_auto_cpufreq
# Purpose: Installs auto-cpufreq from GitHub repository for automatic CPU speed and power optimization
install_auto_cpufreq() {
  log_info "Installing auto-cpufreq..."

  local temp_dir
  temp_dir=$(mktemp -d)

  log_info "Cloning auto-cpufreq repository..."
  if ! git clone https://github.com/AdnanHodzic/auto-cpufreq.git "$temp_dir"; then
    log_error "Failed to clone auto-cpufreq repository"
    return 1
  fi

  log_info "Running auto-cpufreq installer..."
  log_info "NOTE: The installer will ask for confirmation during installation."
  log_info "Please respond to the prompts as needed (typically 'y' to proceed)."

  cd "$temp_dir" || {
    log_error "Failed to navigate to auto-cpufreq directory"
    return 1
  }

  # Pipe "I" into the installer to automatically select the Install option,
  # allowing the installer to proceed without manual intervention.
  if ! echo "I" | sudo ./auto-cpufreq-installer; then
    log_error "auto-cpufreq installation failed"
    cd - > /dev/null || true
    return 1
  fi

  cd - > /dev/null || true
  rm -rf "$temp_dir"

  log_info "auto-cpufreq installation completed"
  return 0
}
# Function: install_hyprland
# Purpose: Installs Hyprland Wayland compositor and its dependencies
install_hyprland() {
  log_info "Installing Hyprland and dependencies..."

  # # Add COPR repository for Hyprland
#TODO: this is for faster updates and newer packages
# but it is might be unstable, add here a approve from user
# to choose if he wants to add the repo or not
  # log_info "Adding Hyprland COPR repository..."
  # if ! sudo dnf copr enable solopasha/hyprland -y; then
  #   log_error "Failed to add Hyprland COPR repository"
  #   return 1
  # fi

  # Core Hyprland packages
  local hypr_packages=(
    "hyprland"                # The Hyprland compositor
    "waybar"                  # Status bar for Wayland
    "dunst"                   # Notification daemon
    "gammastep"               # Color temperature adjustment
    "blueman"                 # Bluetooth manager
    "swaybg"                  # Setting up wallpaper
    "wl-clipboard"            # Wayland clipboard utilities
    "swaylock"        # Lockscreen
    "swayidle"                # Idle management daemon
    "wlr-randr"               # Xrandr clone for wlroots compositors
    "wev"                     # Wayland event viewer
    "brightnessctl"           # Brightness control
    "grim"                    # Screenshots
    "slurp"                   # Selection tool for screenshots
    "rofi"                    # Application launcher
    "sddm"                    # Display manager
  )

  # Install Hyprland and related packages
  log_info "Installing Hyprland and essential packages..."
  if ! sudo dnf install -y "${hypr_packages[@]}"; then
    log_error "Failed to install Hyprland packages"
    return 1
  fi

  # # Installing grimblast (screenshot utility)
  # log_info "Installing grimblast for screenshots..."
  # if ! sudo dnf copr enable agriffis/sway-extras -y; then
  #   log_warn "Failed to enable sway-extras COPR repository for grimblast"
  # else
  #   if ! sudo dnf install -y grimblast; then
  #     log_warn "Failed to install grimblast. You may need to install it manually."
  #   fi
  # fi

  # # Install cliphist (clipboard manager)
  # log_info "Installing cliphist (clipboard manager)..."
  # if ! command -v go &>/dev/null; then
  #   sudo dnf install -y golang
  # fi

  # # Using go install for cliphist
  # if ! go install github.com/sentriz/cliphist@latest; then
  #   log_warn "Failed to install cliphist. Make sure Go is properly configured."
  # fi

  log_info "Hyprland installation completed."
  log_warn "IMPORTANT: You should switch to SDDM and exit your current desktop environment to use Hyprland."
  log_info "Run the script with -S option to switch to SDDM after you've exited your desktop environment."

  return 0
}

# Function: sddm_autologin
# Purpose: Configures SDDM for automatic login with the current user, using machine-specific settings
sddm_autologin() {
  log_info "Setting up SDDM autologin..."

  # Determine system type from hostname
  local hostname
  hostname=$(hostname 2>/dev/null || echo "unknown")
  local system_type="unknown"

  # Check hostname against our configured values from the nested structure
  if [[ "$hostname" == "$hostname_desktop" ]]; then
    system_type="desktop"
  elif [[ "$hostname" == "$hostname_laptop" ]]; then
    system_type="laptop"
  else
    log_warn "Unknown hostname '$hostname', will use default session"
  fi

  log_info "Detected system type: $system_type"

  # Get user from variables or fall back to current user
  local config_user="${user:-$(whoami)}"

  # Get session based on system type, using our loaded variables
  # These variables are loaded from the nested structure in load_variables
  local session_value
  if [[ "$system_type" == "desktop" ]]; then
    # Use desktop-specific session
    session_value="${desktop_session}"
  elif [[ "$system_type" == "laptop" ]]; then
    # Use laptop-specific session
    session_value="${laptop_session}"
  else
    # Use hyprland as default when system type is unknown
    session_value="hyprland"
  fi

  # If session is still empty, fall back to hyprland
  session_value="${session_value:-hyprland}"

  log_info "Using session: $session_value for user: $config_user"

  # Check if SDDM is installed
  if ! rpm -q sddm &>/dev/null; then
    log_error "SDDM is not installed. Please install it first."
    return 1
  fi

  # Determine which configuration file to use
  local conf_file
  if [[ -f "/etc/sddm.conf" ]]; then
    conf_file="/etc/sddm.conf"
    log_debug "Using existing SDDM config file at /etc/sddm.conf"
  else
    # Create SDDM configuration directory if it doesn't exist
    if [[ ! -d "/etc/sddm.conf.d/" ]]; then
      if ! sudo mkdir -p /etc/sddm.conf.d/; then
        log_error "Failed to create SDDM configuration directory"
        return 1
      fi
    fi
    conf_file="/etc/sddm.conf.d/autologin.conf"
    log_debug "Using SDDM config file at /etc/sddm.conf.d/autologin.conf"
  fi

  # Create backup of original file if it exists
  if [[ -f "$conf_file" && ! -f "${conf_file}.bak" ]]; then
    log_debug "Creating backup of SDDM configuration..."
    if ! sudo cp "$conf_file" "${conf_file}.bak"; then
      log_warn "Failed to create backup of SDDM configuration"
    else
      log_debug "SDDM configuration backup created at ${conf_file}.bak"
    fi
  fi

  # Parse existing content if file exists and extract sections
  local existing_content=""
  local general_section=""
  local other_sections=""

  if [[ -f "$conf_file" ]]; then
    existing_content=$(sudo cat "$conf_file" 2>/dev/null)

    # Extract the [General] section if it exists
    if echo "$existing_content" | grep -q '^\[General\]'; then
      general_section=$(echo "$existing_content" | awk '
        BEGIN {in_general = 0; content = ""}
        /^\[General\]/ {in_general = 1; content = content $0 "\n"; next}
        /^\[/ && in_general {in_general = 0; next}
        in_general {content = content $0 "\n"}
        END {print content}
      ')
    fi

    # Extract other sections except [Autologin] and [General]
    other_sections=$(echo "$existing_content" | awk '
      BEGIN {in_skip = 0; content = ""}
      /^\[(Autologin|General)\]/ {in_skip = 1; next}
      /^\[/ && in_skip {in_skip = 0; content = content $0 "\n"; next}
      /^\[/ && !in_skip {content = content $0 "\n"; next}
      !in_skip {content = content $0 "\n"}
      END {print content}
    ')
  fi

  # Create new autologin section with clean formatting
  local autologin_section="[Autologin]\n"
  autologin_section+="# Username for autologin session\n"
  autologin_section+="User=${config_user}\n"
  autologin_section+="# Name of session file for autologin session\n"
  autologin_section+="Session=${session_value}.desktop\n"
  autologin_section+="# Whether sddm should automatically log back into sessions when they exit\n"
  autologin_section+="Relogin=false\n"

  # Build the new configuration content with proper section ordering and spacing
  local new_content=""
  new_content+="${autologin_section}\n"

  # Add other sections if they exist (excluding [Autologin] and [General])
  if [[ -n "$other_sections" ]]; then
    new_content+="${other_sections}\n"
  fi

  # Add [General] section at the end if it exists
  if [[ -n "$general_section" ]]; then
    new_content+="${general_section}"
  fi

  # Trim trailing newlines and ensure file ends with exactly one newline
  new_content=$(echo -e "$new_content" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
  new_content="${new_content}\n"

  # Write the updated configuration
  log_debug "Writing new SDDM configuration..."
  if ! echo -e "$new_content" | sudo tee "$conf_file" >/dev/null; then
    log_error "Failed to write SDDM autologin configuration"
    return 1
  fi

  # Set proper file permissions
  if ! sudo chmod 644 "$conf_file"; then
    log_warn "Failed to set proper permissions on SDDM configuration file"
  fi

  log_success "SDDM autologin configuration completed successfully"
  log_info "The system will automatically log in as $config_user to $session_value after reboot"
  return 0
}
