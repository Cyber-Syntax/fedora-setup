#!/bin/bash

# Source the logging module
source src/logging.sh
source src/variables.sh

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
  #TODO: make .conf file and copy
  local settings=(
    "max_parallel_downloads=20"
    "pkg_gpgcheck=True"
    "skip_if_unavailable=True"
    "minrate=250k"
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
  log_info "Creating/updating sudoers snippet ($sudoers_file)..."

  local sudoers_file="/etc/sudoers.d/custom-conf"
  # dir_sudoers="/etc/sudoers.d/custom-conf"
  # sudoers_file="./configs/custom-conf"

  # Using sudo tee to write to sudoers file with proper permissions
  cat <<EOF | sudo tee "$sudoers_file" >/dev/null
## Allow borgbackup script to run without password
developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh

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

  local ufw_commands=(
    "sudo ufw default deny incoming"
    "sudo ufw default allow outgoing"
    "sudo ufw allow from 192.168.1.0/16"
    "sudo ufw allow ssh"
  )

  for cmd in "${ufw_commands[@]}"; do
    if ! $cmd; then
      log_error "Failed to set UFW rule: $cmd"
      return 1
    fi
  done

  log_info "Opening ports for Syncthing..."

  if ! sudo ufw allow 22000; then
    log_warn "Failed to open Syncthing TCP port"
  fi

  if ! sudo ufw allow 21027/udp; then
    log_warn "Failed to open Syncthing discovery port"
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

lightdm_autologin() {
  local conf_file="/etc/lightdm/lightdm.conf"
  local tmp_file
  tmp_file=$(mktemp)

  # Preserve existing content
  [[ -f "$conf_file" ]] && cat "$conf_file" >"$tmp_file"

  # Add/Update desired section
  if ! grep -q '^\[Seat:\*\]' "$tmp_file"; then
    echo -e "\n[Seat:*]" >>"$tmp_file"
  fi

  # Update settings within the section
  sed -i '/^\[Seat:\*\]/,/^\[/ {
        /^autologin-user=/d
        /^autologin-session=/d
        /^autologin-guest=/d
        /^autologin-user-timeout=/d
        /^autologin-in-background=/d
    }' "$tmp_file"

  cat <<EOF >>"$tmp_file"
autologin-guest=false
autologin-user=$USER
autologin-session=$SESSION
autologin-user-timeout=0
autologin-in-background=false
EOF

  # Install new config
  install -m 644 -o root -g root "$tmp_file" "$conf_file"
  rm "$tmp_file"

  #Pam setup needed on lightdm
  local pam_lightdm="/etc/pam.d/lightdm"
  # make a backup of the original file
  if [[ ! -f "$pam_lightdm.bak" ]]; then
    sudo cp "$pam_lightdm" "$pam_lightdm.bak"
  fi
  echo "Setting up PAM configuration for LightDM..."

  # Auto login without password for lightdm. This also need group setup
  # Append the following lines to the file. Do not change other lines. Add the below lines to the end of the file.
  #TODO: make group setup globally
  grep -qxF 'auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin' "$pam_lightdm" || echo 'auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin' >>"$pam_lightdm"
  grep -qxF 'auth        include     system-login' "$pam_lightdm" || echo 'auth        include     system-login' >>"$pam_lightdm"
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

#TEST: Group for passwordless login
#Seems like this isn't called or work?
nopasswdlogin_group() {
  echo "Creating group for passwordless login..."
  sudo groupadd -r nopasswdlogin 2>/dev/null || echo "Group 'nopasswdlogin' already exists."
  sudo groupadd -r autologin 2>/dev/null || echo "Group 'autologin' already exists."
  sudo gpasswd -a "$USER" nopasswdlogin
  sudo gpasswd -a "$USER" autologin
  echo "Group created for passwordless login."
  echo "Add users to the nopasswdlogin group to enable passwordless login."
  sudo usermod -aG nopasswdlogin,autologin "$USER"
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
  sudo cp "$libvirt_file" "$dir_libvirt"

  # enable network ufw
  sudo ufw allow in on virbr0
  sudo ufw allow out on virbr0

  log_info "Virtualization setup completed. You may need to log out and log back in for group membership changes to take effect."
}
