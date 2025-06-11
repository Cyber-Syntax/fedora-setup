#!/bin/bash

# Source the logging module
source src/logging.sh

# Tweaks DNF configuration to improve performance.
speed_up_dnf() {
  log_info "Configuring DNF for improved performance..."
  # Define the configuration file path
  local _dnf_conf="/etc/dnf/dnf.conf"

  # Backup current dnf.conf if no backup exists.
  if [[ ! -f "${_dnf_conf}.bak" ]]; then
    if ! sudo cp "$_dnf_conf" "${_dnf_conf}.bak"; then
      log_error "Failed to create backup of $_dnf_conf"
      return 1
    fi
  fi
  # 250K = 0.25MB/s
  #NOTE: minrate is cause issue on mirrors.
  #TODO: make .conf file and copy
  local settings=(
    "max_parallel_downloads=20"
    "pkg_gpgcheck=True"
    "skip_if_unavailable=True"
    "timeout=15"
    "retries=5"
  )

  for setting in "${settings[@]}"; do
    if ! grep -q "^$setting" "$_dnf_conf"; then
      log_debug "Adding setting: $setting"
      if ! echo "$setting" | sudo tee -a "$_dnf_conf" >/dev/null; then
        log_error "Failed to add setting: $setting"
        return 1
      fi
    fi
  done

  log_info "DNF configuration updated successfully."
}

# This functions configures boot (GRUB), sysctl for TCP/BBR, and sudoers.
grub_timeout() {
  log_info "Setting up boot configuration..."

  local boot_file="/etc/default/grub"
  # 1. Boot configuration - Safer GRUB_TIMEOUT modification
  # Backup original file
  if [[ ! -f "$boot_file.bak" ]]; then
    sudo cp -p "$boot_file" "$boot_file.bak"
  fi

  # Update existing GRUB_TIMEOUT or add new entry
  if grep -q '^GRUB_TIMEOUT=' "$boot_file"; then
    # Replace any existing timeout value
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$boot_file"
  else
    # Add new timeout setting after GRUB_CMDLINE_LINUX or at end of file
    if grep -q '^GRUB_CMDLINE_LINUX=' "$boot_file"; then
      sudo sed -i '/^GRUB_CMDLINE_LINUX=/a GRUB_TIMEOUT=0' "$boot_file"
    else
      # Using sudo tee to properly handle redirection with elevated privileges
      echo 'GRUB_TIMEOUT=0' | sudo tee -a "$boot_file" >/dev/null
    fi
  fi

  # Verify the change
  if ! grep -q '^GRUB_TIMEOUT=0' "$boot_file"; then
    log_error "Failed to set GRUB_TIMEOUT"
    return 1
  fi
  #NOTE: Current new nvidia-open need below line on GRUB_CMDLINE_LINUX to be able to load nvidia
  #pcie_port_pm=off

  log_info "Regenerating GRUB configuration..."
  sudo grub2-mkconfig -o /boot/grub2/grub.cfg
}

sudoers_setup() {
  # 4. Sudoers snippet (common for both systems).
  local sudoers_file="/etc/sudoers.d/custom-conf"

  log_info "Creating/updating sudoers snippet ($sudoers_file)..."

  # dir_sudoers="/etc/sudoers.d/custom-conf"
  # sudoers_file="./configs/custom-conf"

  # Using sudo tee to write to sudoers file with proper permissions
  cat <<EOF | sudo tee "$sudoers_file" >/dev/null
## Allow borgbackup script to run without password
$USER ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh

## Increase timeout on terminal password prompt
Defaults timestamp_type=global
Defaults env_reset,timestamp_timeout=20
EOF

  # Set proper permissions for sudoers file
  if ! sudo chmod 0440 "$sudoers_file"; then
    log_error "Failed to set proper permissions on sudoers file"
    return 1
  fi

  log_info "Sudoers configuration updated successfully."
}

tcp_bbr_setup() {
  # Copy TCP BBR configuration file
  echo "Setting up TCP BBR configuration..."

  local dir_tcp_bbr="/etc/sysctl.d/99-tcp-bbr.conf"
  local tcp_bbr_file="./configs/99-tcp-bbr.conf"

  if ! sudo cp "$tcp_bbr_file" "$dir_tcp_bbr"; then
    log_error "Failed to copy TCP BBR configuration file"
    return 1
  fi

  echo "Reloading sysctl settings..."
  sudo sysctl --system

}

switch_ufw_setup() {
  log_info "Switching to UFW from firewalld..."

  # Execute commands directly instead of using log_cmd
  if ! sudo systemctl disable --now firewalld; then
    log_error "Failed to disable firewalld"
    return 1
  fi

  if ! sudo systemctl enable --now ufw; then
    log_error "Failed to enable UFW"
    return 1
  fi

  log_info "UFW installation completed."
  log_info "Updating UFW rules..."

  # Set default policies
  if ! sudo ufw default deny incoming; then
    log_error "Failed to set default incoming policy"
    return 1
  fi

  if ! sudo ufw default allow outgoing; then
    log_error "Failed to set default outgoing policy"
    return 1
  fi

  # Allow internal network and SSH
  if ! sudo ufw allow from 192.168.1.0/16; then
    log_error "Failed to allow internal network"
    return 1
  fi

  if ! sudo ufw allow ssh; then
    log_error "Failed to allow SSH"
    return 1
  fi

  log_info "Opening ports for Syncthing..."

  if ! sudo ufw allow 22000; then
    log_warn "Failed to open Syncthing TCP port"
    return 1
  fi

  if ! sudo ufw allow 21027/udp; then
    log_warn "Failed to open Syncthing discovery port"
    return 1
  fi

  log_info "Syncthing ports opened. Check UFW status with 'ufw status verbose'"
}

# Swaps ffmpeg-free with ffmpeg if ffmpeg-free is installed.
ffmpeg_swap() {
  log_info "Checking for ffmpeg-free package..."
  if sudo dnf list installed ffmpeg-free &>/dev/null; then
    log_info "Swapping ffmpeg-free with ffmpeg..."

    # Execute command directly instead of using log_cmd
    if ! sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y; then
      log_error "Failed to swap ffmpeg packages"
      return 1
    fi
    log_info "ffmpeg swap completed successfully."
  else
    log_info "ffmpeg-free is not installed; skipping swap."
  fi
}

# Enables RPM Fusion free and nonfree repositories.
enable_rpm_fusion() {
  log_info "Enabling RPM Fusion repositories..."
  local fedora_version
  fedora_version=$(rpm -E %fedora)

  log_debug "Detected Fedora version: $fedora_version"

  local free_repo_count
  local nonfree_repo_count
  free_repo_count=$(sudo dnf repolist | awk '$1=="rpmfusion-free" {print $1}' | wc -l)
  nonfree_repo_count=$(sudo dnf repolist | awk '$1=="rpmfusion-nonfree" {print $1}' | wc -l)

  # Check if both "rpmfusion-free" and "rpmfusion-nonfree" are already enabled.
  if [[ $free_repo_count -gt 0 && $nonfree_repo_count -gt 0 ]]; then
    log_info "RPM Fusion free and nonfree repositories are already enabled. Skipping installation."
    return 0
  fi

  # Otherwise, install the repositories.
  log_info "Installing RPM Fusion repositories..."

  # Execute command directly instead of using log_cmd
  if ! sudo dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm; then
    log_error "Failed to install RPM Fusion repositories"
    return 1
  fi

  log_info "Upgrading system packages..."

  # Execute commands directly instead of using log_cmd
  if ! sudo dnf upgrade --refresh -y; then
    log_warn "System upgrade failed"
  fi

  if ! sudo dnf group upgrade -y core; then
    log_warn "Core group upgrade failed"
  fi

  log_info "Installing additional RPM Fusion components..."

  # Execute command directly instead of using log_cmd
  if ! sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted sudo dnf-plugins-core; then
    log_error "Failed to install RPM Fusion tainted repositories"
    return 1
  fi

  log_info "RPM Fusion repositories enabled successfully."
}

# Switch display manager to lightdm
switch_lightdm() {
  log_info "Switching display manager to LightDM..."

  # Execute commands directly instead of using log_cmd
  if ! sudo dnf install -y lightdm; then
    log_error "Failed to install LightDM"
    return 1
  fi

  if ! sudo systemctl disable gdm; then
    log_warn "Failed to disable GDM, it might not be installed"
  fi

  if ! sudo systemctl enable lightdm; then
    log_error "Failed to enable LightDM"
    return 1
  fi

  log_info "Display manager switched to LightDM."
}

# Configuration file modification function for lightdm autologin
# This function modifies the lightdm configuration file to enable autologin
lightdm_autologin() {
  local conf_file="/etc/lightdm/lightdm.conf"
  local user_name="${user:-$(whoami)}"
  local hostname

  hostname=$(hostname 2>/dev/null || echo "unknown")
  local session_value

  # Determine which session to use based on system type
  if [[ "$hostname" == "$hostname_desktop" ]]; then
    session_value="${desktop_session:-qtile}"
  elif [[ "$hostname" == "$hostname_laptop" ]]; then
    session_value="${laptop_session:-hyprland}"
  else
    session_value="qtile" # Default if hostname doesn't match known types
  fi

  log_info "Setting up LightDM autologin for user $user_name with session $session_value"

  # Check if lightdm.conf exists
  if [[ ! -f "$conf_file" ]]; then
    log_error "LightDM configuration file not found: $conf_file"
    return 1
  fi

  # Create a backup of the original config
  if [[ ! -f "${conf_file}.bak" ]]; then
    sudo cp "$conf_file" "${conf_file}.bak"
  fi

  # Read the content of the file
  local content
  content=$(sudo cat "$conf_file")

  # Check if the file contains the [Seat:*] section
  if echo "$content" | grep -q '\[Seat:\*\]'; then
    # Modify the existing configuration
    log_info "Modifying existing LightDM configuration..."
    local new_content
    new_content=$(echo "$content" | awk -v user="$user_name" -v session="$session_value" '
      BEGIN { in_seat = 0; autologin_user_modified = 0; autologin_session_modified = 0; }
      /^\[Seat:\*\]/ { in_seat = 1; print; next; }
      /^\[/ { in_seat = 0; print; next; }
      in_seat && /^#?autologin-user=/ {
        print "autologin-user=" user;
        autologin_user_modified = 1;
        next;
      }
      in_seat && /^#?autologin-session=/ {
        print "autologin-session='" session "'";
        autologin_session_modified = 1;
        next;
      }
      { print }
      END {
        if (in_seat) {
          if (!autologin_user_modified) print "autologin-user=" user;
          if (!autologin_session_modified) print "autologin-session='" session "'";
        }
      }
    ')

    # Write the new content to the file
    echo "$new_content" | sudo tee "$conf_file" >/dev/null
  else
    # Add the [Seat:*] section with autologin enabled
    log_info "Adding new LightDM autologin configuration..."
    local new_content="${content}\n\n[Seat:*]\n"
    new_content="${new_content}autologin-user=$user_name\n"
    new_content="${new_content}autologin-session=$session_value\n"

    # Write the new content to the file
    echo -e "$new_content" | sudo tee "$conf_file" >/dev/null
  fi
  # pam setup for auto unlock gnome keyring
  #TODO: handle this later
  #NOTE: this isn't work with autologin because its need password on from display manager
  #   # Gnome keyring auto unlock
  # auth       optional     pam_gnome_keyring.so
  # session    optional     pam_gnome_keyring.so auto_start
  #

  log_success "LightDM autologin configuration completed"
  return 0
}

#TEST: Group for passwordless login
#Seems like this isn't called or work?
nopasswdlogin_group() {
  echo "Creating group for passwordless login..."
  sudo groupadd -r autologin 2>/dev/null || echo "Group 'autologin' already exists."
  sudo gpasswd -a "$USER" nopasswdlogin
  sudo gpasswd -a "$USER" autologin
  echo "Group created for passwordless login."
  sudo usermod -aG autologin "$USER"
}

setup_files() {
  #TODO: need to setup those function in options, temp for now
  grub_timeout
  lightdm_autologin
  tcp_bbr_setup
  sudoers_setup
}

# neovim clearing
backup_old_neovim_setup() {
  echo "Backup neoVim configuration..."
  mv ~/.local/share/nvim{,.bak}
  mv ~/.local/state/nvim{,.bak}
  mv ~/.cache/nvim{,.bak}
}

# oh-my-zsh setup
oh_my_zsh_setup() {
  echo "Installing oh-my-zsh..."
  sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  #TODO: plugins installation: currently manual, need automation with package managers like dnf probably
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
  git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
}

#TEST: When you use same home partition when you switch distro, selinux context is not correct
#TODO: add option
selinux_context() {
  log_info "Restoring SELinux context for home directory..."

  # Execute command directly instead of using log_cmd
  if ! restorecon -R /home/; then
    log_error "Failed to restore SELinux context for /home/"
    return 1
  fi

  log_info "SELinux context restored successfully."
}

syncthing_setup() {
  log_info "Setting up Syncthing..."

  # For user-specific services, don't use sudo
  if ! systemctl --user enable --now syncthing; then
    log_error "Failed to enable Syncthing service"
    return 1
  fi

  log_info "Syncthing enabled successfully."
}

#TESTING:
virt_manager_setup() {
  log_info "Setting up virtualization..."

  # Check for UFW dependency
  if ! command -v ufw &>/dev/null; then
    log_info "UFW not installed but required for proper network configuration. Installing it first..."
    if ! sudo dnf install -y ufw; then
      log_error "Failed to install UFW, virtualization network rules won't be configured"
      # Continue with basic setup since libvirt can work without UFW rules
    fi
  fi

  # Install required packages
  log_info "Installing virtualization packages..."
  if ! sudo dnf install -y @virtualization; then
    log_error "Failed to install virtualization group"
    return 1
  fi

  if ! sudo dnf group install -y --with-optional virtualization; then
    log_warn "Failed to install optional virtualization packages"
    # Continue anyway with the base packages
  fi

  # Create the libvirt group if it doesn't exist
  if ! getent group libvirt >/dev/null; then
    sudo groupadd -r libvirt
  fi

  # Add user to libvirt group
  sudo usermod -aG libvirt "$USER"

  # Enable and start libvirt service
  if ! sudo systemctl enable --now libvirtd; then
    log_error "Failed to enable and start libvirt service"
    return 1
  fi

  # Libvirtd
  local libvirt_file="./configs/libvirt/network.conf"
  local dir_libvirt="/etc/libvirt/network.conf"

  # Fix network nat issue, switch iptables
  if ! sudo cp "$libvirt_file" "$dir_libvirt"; then
    log_error "Failed to copy libvirt network configuration"
  else
    log_info "Libvirt network configuration updated successfully"
  fi

  # enable network ufw
  if ! sudo ufw allow in on virbr0; then
    log_warn "Failed to allow incoming traffic on virbr0"
  fi
  if ! sudo ufw allow out on virbr0; then
    log_warn "Failed to allow outgoing traffic on virbr0"
  fi

  log_info "Virtualization setup completed. You may need to log out and log back in for group membership changes to take effect."
}

# Helper function to convert application names to proper desktop file names
# and verify if they exist on the system
#TEST: Need to be improved
app_name_to_desktop_file() {
  local app_name="$1"
  local desktop_file=""

  # If app_name already ends with .desktop, use it as is
  if [[ "$app_name" == *.desktop ]]; then
    desktop_file="$app_name"
  else
    # Common application name mappings
    #TODO: need better way to handle this
    case "$app_name" in
    "brave")
      desktop_file="brave-browser.desktop"
      ;;
    "chrome" | "google-chrome" | "googlechrome")
      desktop_file="google-chrome.desktop"
      ;;
    "firefox-esr")
      desktop_file="firefox-esr.desktop"
      ;;
    "vscode" | "code")
      desktop_file="code.desktop"
      ;;
    "librewolf")
      desktop_file="librewolf.desktop"
      ;;
    "chromium")
      desktop_file="chromium-browser.desktop"
      ;;
    "obsidian")
      desktop_file="obsidian.desktop"
      ;;
    *)
      # For standard applications, just append .desktop
      desktop_file="${app_name}.desktop"
      ;;
    esac
  fi

  # Check if the desktop file exists in standard locations
  local found=false
  local search_paths=(
    "/usr/share/applications"
    "/usr/local/share/applications"
    "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  )

  for path in "${search_paths[@]}"; do
    if [[ -f "$path/$desktop_file" ]]; then
      found=true
      break
    fi
  done

  if ! $found; then
    log_warn "Desktop file '$desktop_file' not found. The application may not be installed."
  fi

  # Return the desktop file name regardless of whether it was found
  # This allows the user's configuration to be written even if the app isn't installed yet
  echo "$desktop_file"
}

# Creates or updates the mimeapps.list file to set default applications
# based on user preferences stored in variables.json
setup_default_applications() {
  log_info "Setting up default applications with mimeapps.list..."

  # Configuration file paths
  local variables_file
  variables_file=$(load_json_config "variables.json")

  # Verify the variables file exists
  if [[ -z "$variables_file" || ! -f "$variables_file" ]]; then
    log_error "Failed to load variables configuration"
    return 1
  fi

  # Get the user's home directory for creating mimeapps.list
  local user_home
  user_home=$(getent passwd "$USER" | cut -d: -f6)
  local config_dir="${user_home}/.config"
  local mimeapps_file="${config_dir}/mimeapps.list"

  # Create backup if the file already exists
  if [[ -f "$mimeapps_file" ]]; then
    log_info "Creating backup of existing mimeapps.list..."
    local backup_file="${mimeapps_file}.bak.$(date +%Y%m%d%H%M%S)"
    if ! cp "$mimeapps_file" "$backup_file"; then
      log_error "Failed to create backup of mimeapps.list"
      return 1
    fi
    log_info "Backup created at $backup_file"
  fi

  # Make sure the config directory exists
  mkdir -p "$config_dir"

  # Load the default applications from variables.json
  local browser_name
  local terminal_name
  local file_manager_name
  local image_viewer_name
  local text_editor_name

  browser_name=$(parse_json "$variables_file" ".default_applications.browser")
  terminal_name=$(parse_json "$variables_file" ".default_applications.terminal")
  file_manager_name=$(parse_json "$variables_file" ".default_applications.file_manager")
  image_viewer_name=$(parse_json "$variables_file" ".default_applications.image_viewer")
  text_editor_name=$(parse_json "$variables_file" ".default_applications.text_editor")

  # Convert application names to proper desktop file names
  local browser=""
  local terminal=""
  local file_manager=""
  local image_viewer=""
  local text_editor=""

  if [[ -n "$browser_name" ]]; then
    browser=$(app_name_to_desktop_file "$browser_name")
    log_debug "Browser '$browser_name' mapped to desktop file: $browser"
  fi

  if [[ -n "$terminal_name" ]]; then
    terminal=$(app_name_to_desktop_file "$terminal_name")
    log_debug "Terminal '$terminal_name' mapped to desktop file: $terminal"
  fi

  if [[ -n "$file_manager_name" ]]; then
    file_manager=$(app_name_to_desktop_file "$file_manager_name")
    log_debug "File manager '$file_manager_name' mapped to desktop file: $file_manager"
  fi

  if [[ -n "$image_viewer_name" ]]; then
    image_viewer=$(app_name_to_desktop_file "$image_viewer_name")
    log_debug "Image viewer '$image_viewer_name' mapped to desktop file: $image_viewer"
  fi

  if [[ -n "$text_editor_name" ]]; then
    text_editor=$(app_name_to_desktop_file "$text_editor_name")
    log_debug "Text editor '$text_editor_name' mapped to desktop file: $text_editor"
  fi

  # Define the default applications section of mimeapps.list
  log_debug "Generating default applications section..."

  local default_section="[Default Applications]\n"

  # Process browser associations
  if [[ -n "$browser" ]]; then
    local browser_mimes
    # Get browser mime types from variables.json as an array
    mapfile -t browser_mimes < <(parse_json "$variables_file" ".mime_associations.browser[]")

    for mime in "${browser_mimes[@]}"; do
      default_section+="${mime}=${browser}\n"
    done
  fi

  # Process image viewer associations
  if [[ -n "$image_viewer" ]]; then
    local image_mimes
    mapfile -t image_mimes < <(parse_json "$variables_file" ".mime_associations.image_viewer[]")

    for mime in "${image_mimes[@]}"; do
      default_section+="${mime}=${image_viewer}\n"
    done
  fi

  # Process text editor associations
  if [[ -n "$text_editor" ]]; then
    local text_mimes
    mapfile -t text_mimes < <(parse_json "$variables_file" ".mime_associations.text_editor[]")

    for mime in "${text_mimes[@]}"; do
      default_section+="${mime}=${text_editor}\n"
    done
  fi

  # Process file manager associations
  if [[ -n "$file_manager" ]]; then
    local file_mimes
    mapfile -t file_mimes < <(parse_json "$variables_file" ".mime_associations.file_manager[]")

    for mime in "${file_mimes[@]}"; do
      default_section+="${mime}=${file_manager}\n"
    done
  fi

  # Process terminal associations
  if [[ -n "$terminal" ]]; then
    local terminal_mimes
    mapfile -t terminal_mimes < <(parse_json "$variables_file" ".mime_associations.terminal[]")

    for mime in "${terminal_mimes[@]}"; do
      default_section+="${mime}=${terminal}\n"
    done
  fi

  # Define the Added Associations section - adding semicolons for proper formatting
  log_debug "Generating added associations section..."

  local added_section="\n[Added Associations]\n"

  # Add browser associations
  if [[ -n "$browser" ]]; then
    local browser_mimes
    mapfile -t browser_mimes < <(parse_json "$variables_file" ".mime_associations.browser[]")

    for mime in "${browser_mimes[@]}"; do
      added_section+="${mime}=${browser};\n"
    done
  fi

  # Add image viewer associations
  if [[ -n "$image_viewer" ]]; then
    local image_mimes
    mapfile -t image_mimes < <(parse_json "$variables_file" ".mime_associations.image_viewer[]")

    for mime in "${image_mimes[@]}"; do
      added_section+="${mime}=${image_viewer};\n"
    done
  fi

  # Add text editor associations
  if [[ -n "$text_editor" ]]; then
    local text_mimes
    mapfile -t text_mimes < <(parse_json "$variables_file" ".mime_associations.text_editor[]")

    for mime in "${text_mimes[@]}"; do
      added_section+="${mime}=${text_editor};\n"
    done
  fi

  # Add file manager associations
  if [[ -n "$file_manager" ]]; then
    local file_mimes
    mapfile -t file_mimes < <(parse_json "$variables_file" ".mime_associations.file_manager[]")

    for mime in "${file_mimes[@]}"; do
      added_section+="${mime}=${file_manager};\n"
    done
  fi

  # Add terminal associations
  if [[ -n "$terminal" ]]; then
    local terminal_mimes
    mapfile -t terminal_mimes < <(parse_json "$variables_file" ".mime_associations.terminal[]")

    for mime in "${terminal_mimes[@]}"; do
      added_section+="${mime}=${terminal};\n"
    done
  fi

  # Combine everything into the final mimeapps.list content
  local mimeapps_content="${default_section}${added_section}"

  # Write the file
  log_debug "Writing mimeapps.list to $mimeapps_file..."
  if ! echo -e "$mimeapps_content" >"$mimeapps_file"; then
    log_error "Failed to write mimeapps.list"
    return 1
  fi

  log_info "Default applications configured successfully in $mimeapps_file"
  return 0
}
