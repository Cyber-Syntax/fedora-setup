#!/usr/bin/env bash
# Author: Serif Cyber-Syntax
# License: BSD 3-Clause
# Comprehensive installation and configuration script
#for sudo dnf-based systems.

# Prevents the script from continuing on errors, unset variables, and pipe failures.
set -euo pipefail
IFS=$'\n\t'

# Source additional functions from separate files.
source src/logging.sh
source src/variables.sh
source src/packages.sh
source src/general.sh
source src/apps.sh
source src/desktop.sh
source src/laptop.sh

# Variable notifying the user that the script is running.
if ! id "$USER" &>/dev/null; then
  log_warn "You forget to change variables according to your needs. Go src/variables.sh and change according to your needs."
  # Check if user forgot to change the VARIABLES.
  if [ -n "$SUDO_USER" ]; then
    whoami="$SUDO_USER"
  else
    whoami=$(whoami)
  fi

  log_warn "Script USER variable is: $USER but your username: $whoami."
  log_warn "Please change the USER variable and other variables according to your system configuration."

  exit 1
fi

# Help message
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]
WARNING:
I AM NOT RESPONSIBLE FOR ANY DAMAGE CAUSED BY THIS SCRIPT. USE AT YOUR OWN RISK. This script is need root privileges which can be dangerous.
NOTE: Please change the variables as your system configuration.

This scripts automates the installation and configuration on Fedora Linux.

Options:
  -h    Display this help message.

NOTE: Below options consider safe to use but still be careful.
  -b    Install Brave Browser.
  -B    Setup borgbackup service.
  -c    Enable tap-to-click for touchpad.
  -i    Install core packages.
  -I    Install system-specific(desktop, laptop) packages.
  -t    Setup trash-cli service.
  -f    Setup useful linux configurations (boot timeout, tcp_bbr, terminal password timeout).
  -F    Install Flatpak packages.
  -l    Install Librewolf browser.
  -L    Install Lazygit.
  -U    Switch UFW from firewald and enable it.
  -q    Install Qtile packages.
  -Q    Qtile udev rule for xbacklight.
  -r    Enable RPM Fusion repositories.
  -d    Speed up DNF (set max_parallel_downloads, pkg_gpgcheck, etc.).
  -x    Swap ffmpeg-free with ffmpeg.

Experimental: Below functions are need to tested with caution.
  -a    Execute all functions. (NOTE:System detection handled by hostname)
  -T    Setup TLP for laptop.
  -P    Setup thinkfan for laptop.
  -s    Enable Syncthing service.
  -g    Remove GNOME desktop environment (keep NetworkManager).
  -z    Setup zenpower for Ryzen 5000 series
  -n    Install NVIDIA CUDA
  -N    Switch to nvidia-open drivers
  -v    Setup VA-API for NVIDIA RTX series
  -p    Install ProtonVPN repository and enable OpenVPN for SELinux
  -o    Install Ollama with its install.sh script
  -u    Run system updates (autoremove, fwupdmgr commands).
  -V    Setup virtualization with virt-manager and configure libvirt.


Example:
  Setup all according to machine: sudo $0 -a
  Setup system-specific packages: sudo $0 -I
  Setup TLP for laptop: sudo $0 -T
EOF
  exit 1
}

# Detect system type based on hostname
detect_system_type() {
  local hostname detected_type
  hostname=$(hostname 2>/dev/null || echo "unknown")

  log_debug "Detected hostname: $hostname"

  if [[ "$hostname" == "$hostname_desktop" ]]; then
    detected_type="desktop"
  elif [[ "$hostname" == "$hostname_laptop" ]]; then
    detected_type="laptop"
  else
    log_error "Unknown hostname '$hostname'. Expected:"
    log_error "Desktop: $hostname_desktop"
    log_error "Laptop:  $hostname_laptop"
    exit 1
  fi

  # Output only the type to stdout
  echo "$detected_type"
}

# Install system-specific packages
install_system_specific_packages() {
  local system_type
  system_type=$(detect_system_type)
  system_type=$(detect_system_type)
  # local system_type="${1:-unknown}"
  local pkg_list=()

  case "$system_type" in
  desktop)
    log_info "Installing desktop-specific packages..."
    pkg_list=("${DESKTOP_PACKAGES[@]}")
    ;;
  laptop)
    log_info "Installing laptop-specific packages..."
    pkg_list=("${LAPTOP_PACKAGES[@]}")
    ;;
  *)
    log_warn "Unknown system type '$system_type'. Skipping system-specific packages."
    return 0
    ;;
  esac

  # Check if package list is empty
  if [[ ${#pkg_list[@]} -eq 0 ]]; then
    log_warn "No packages defined for $system_type installation"
    return 0
  fi

  log_debug "Package list: ${pkg_list[*]}"

  # Install packages with error handling
  if ! sudo dnf install -y "${pkg_list[@]}"; then
    echo "Error: Failed to install some $system_type packages. Trying individual installations..." >&2

    # Fallback to per-package installation
    for pkg in "${pkg_list[@]}"; do
      echo "Attempting to install $pkg..."
      if ! sudo dnf install -y "$pkg"; then
        echo "Warning: Failed to install package $pkg" >&2
      fi
    done
  fi

  echo "${system_type^} packages installation completed."
}

install_core_packages() {
  log_info "Updating repositories..."
  if ! sudo dnf install -y "${CORE_PACKAGES[@]}"; then
    log_error "Error: Failed to install core packages." >&2
    return 1
  fi

  log_info "Core packages installation completed."
}

install_flatpak_packages() {
  log_info "Installing Flatpak packages..."

  # Setup flathub if not already setup
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  # Install flatpak packages as the regular user
  if ! flatpak install -y flathub "${FLATPAK_PACKAGES[@]}"; then
    log_error "Failed to install Flatpak packages."
    return 1
  fi

  log_info "Flatpak packages installation completed."
}

#TEST: Both desktop and laptop
trash_cli_setup() {
  log_info "Setting up trash-cli service..."

  # Create service file
  if ! sudo cp "$trash_cli_service_file" "$dir_trash_cli_service"; then
    log_error "Failed to copy trash-cli service file"
    return 1
  fi

  # Create timer file
  if ! sudo cp "$trash_cli_timer_file" "$dir_trash_cli_timer"; then
    log_error "Failed to copy trash-cli timer file"
    return 1
  fi

  log_info "Enabling trash-cli timer..."
  sudo systemctl daemon-reload
  sudo systemctl enable --now trash-cli.timer

  log_info "trash-cli service setup completed."
}

# This functions configures boot (GRUB), sysctl for TCP/BBR, and sudoers.
grub_timeout() {
  echo "Setting up boot configuration..."

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
      # Fixed: Using printf with sudo tee to properly handle redirection with elevated privileges
      #TEST:
      echo 'GRUB_TIMEOUT=0\n' | sudo tee -a "$boot_file" >/dev/null
    fi
  fi

  # Verify the change
  if ! grep -q '^GRUB_TIMEOUT=0' "$boot_file"; then
    echo "Error: Failed to set GRUB_TIMEOUT" >&2
    return 1
  fi
  #NOTE:
  #Current new nvidia-open need below line on GRUB_CMDLINE_LINUX to be able to load nvidia
  #pcie_port_pm=off

  echo "Regenerating GRUB configuration..."
  sudo grub2-mkconfig -o /boot/grub2/grub.cfg

}

sudoers_setup() {
  # 4. Sudoers snippet (common for both systems).
  #TODO: sudoers.d folder is not work?
  # switch to cp instead of cat
  echo "Creating/updating sudoers snippet ($sudoers_file)..."
  cat <<EOF >"$sudoers_file"
## Allow borgbackup script to run without password
developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh

## Increase timeout on terminal password prompt
Defaults timestamp_type=global
Defaults env_reset,timestamp_timeout=20
EOF
  chmod 0440 "$sudoers_file"
}

tcp_bbr_setup() {
  # Copy TCP BBR configuration file
  echo "Setting up TCP BBR configuration..."
  if ! sudo cp "$tcp_bbr_file" "$dir_tcp_bbr"; then
    log_error "Failed to copy TCP BBR configuration file"
    return 1
  fi

  echo "Reloading sysctl settings..."
  sudo sysctl --system

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

# TEST: Install ProtonVPN repository and enable OpenVPN for SELinux.
# This function downloads the ProtonVPN repository package and installs it.
# Then it attempts to enable OpenVPN for SELinux by installing a local policy module.
install_protonvpn() {
  echo "Installing ProtonVPN repository..."
  # Note: The URL may need to be updated to the latest version.

  # add if repo not exist
  #FIX: protonvpn.rpm created on the current directory problem
  if [[ ! -f "/etc/yum.repos.d/protonvpn-stable.repo" ]]; then
    wget -O protonvpn.rpm "https://repo.protonvpn.com/fedora-$(awk '{print $3}' /etc/fedora-release)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.2-1.noarch.rpm"
  fi
  #FIX: still asking for key
  #    ProtonVPN Fedora Stable repository                                                                                            100% |  11.1 KiB/s |   3.7 KiB |  00m00s
  # >>> Librepo error: repomd.xml GPG signature verification error: Signing key not found
  #  https://repo.protonvpn.com/fedora-41-stable/public_key.asc                                                                    100% |  13.3 KiB/s |   3.6 KiB |  00m00s
  # Importing OpenPGP key 0x6:
  #  UserID     : "Proton Technologies AG <opensource@proton.me>"
  #  Fingerprint: <cleaned_by_me>
  #  From       : https://repo.protonvpn.com/fedora-41-stable/public_key.asc
  # Is this ok [y/N]:

  if ! sudo dnf install -y ./protonvpn.rpm; then
    echo "Failed to install ProtonVPN repository"
    return 1
  fi

  if ! sudo dnf check-update --refresh; then
    echo "Failed to refresh repositories"
    # Continue anyway, as check-update can return non-zero for updates
  fi

  if ! sudo dnf install -y proton-vpn-gnome-desktop; then
    echo "Failed to install ProtonVPN GNOME desktop integration"
    return 1
  fi

  echo "ProtonVPN installation completed."

  echo "Enabling OpenVPN for SELinux..."
  #FIXME: sending else in this block
  if [[ -f "myopenvpn.pp" ]]; then
    if ! semodule -i myopenvpn.pp; then
      echo "Failed to install SELinux OpenVPN module"
      return 1
    fi
    echo "SELinux OpenVPN module installed."
  else
    echo "Warning: myopenvpn.pp not found. Please provide the SELinux policy module."
  fi
}

# This function performs cleanup and firmware update checks.
system_updates() {
  echo "Running system updates..."
  for attempt in {1..3}; do
    if sudo dnf autoremove -y; then
      break
    fi
    echo "Autoremove failed (attempt $attempt/3), retrying..."
    sleep $((attempt * 5))
  done || {
    echo "Failed to complete autoremove after 3 attempts"
    return 1
  }
  #TODO: This command dangerous because of boot update can cause problems
  # maybe get only updates and show them to user
  # fwupdmgr get-devices
  # fwupdmgr refresh --force
  # fwupdmgr get-updates -y
  # fwupdmgr update -y
  echo "System updates completed. (TEST: Review update logs for any errors.)"
}

# Syncthing setup
syncthing_setup() {
  log_info "Setting up Syncthing..."

  # For user-specific services, don't use sudo
  if ! systemctl --user enable --now syncthing; then
    log_error "Failed to enable Syncthing service"
    return 1
  fi

  log_info "Syncthing enabled successfully."
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

# neovim clearing
clear_neovim() {
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

#TEST: fedora mirror country change to get good speeds
#TODO: need little research on this to make it more efficient
mirror_country_change() {
  log_info "Changing Fedora mirror country..."
  # on /etc/yum.repos.d/fedora.repo and similar repos need only `&country=de` in the end on metalink
  # metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch&country=de
  # variable mirror_country="de" handled on variable.sh
  # also there is 3 metalink on the files generally, [fedora-source], [fedora] and [fedora-debuginfo]
  # also need to commeent t he baseurl
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

# sshd setup, copy ssh keys to laptop from desktop etc.
ssh_setup_laptop() {
  log_info "Setting up SSH for laptop"

  # Enable password authentication to be able to receive keys
  if ! sudo systemctl enable --now sshd; then
    log_error "Failed to enable SSH service"
    return 1
  fi

  # Write sshd config to allow password authentication
  #TODO: Add some security here
  cat <<EOF >/etc/ssh/sshd_config.d/temp_password_auth.conf
PasswordAuthentication yes
PermitRootLogin no
PermitEmptyPasswords yes
EOF
  log_info "SSH password authentication enabled for laptop."
  log_info "Setting up SSH..."

  # TODO: need to create keys but if they are not created yet.
  # NOTE: desktop sends keys to laptop here
  if ! ssh-copy-id $USER@$LAPTOP_IP; then
    log_error "Failed to copy SSH keys to laptop"
    return 1
  fi

  log_info "SSH keys copied successfully."
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

#TODO: Setup virtualization
# add options etc.
#TESTING:
virt_manager_setup() {
  log_info "Setting up virtualization..."

  # Install required packages
  sudo dnf install -y @virtualization
  sudo dnf group install -y --with-optional virtualization

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

  # Fix network nat issue, switch iptables
  sudo cp "$libvirt_file" "$dir_libvirt"

  # enable network ufw
  sudo ufw allow in on virbr0
  sudo ufw allow out on virbr0

  log_info "Virtualization setup completed. You may need to log out and log back in for group membership changes to take effect."
}

# --- Main function ---

main() {
  # Quick check for help option.
  if [[ "$#" -eq 1 && "$1" == "-h" ]]; then
    usage
  fi

  log_debug "Initializing script with args: $*"

  # Initialize sudo dnf speed first
  #TODO: Is there a better way to do this?
  speed_up_dnf || log_warn "Failed to optimize DNF configuration"

  # Initialize option flags.
  all_option=false
  install_core_packages_option=false
  install_system_specific_packages_option=false
  flatpak_option=false
  librewolf_option=false
  qtile_option=false
  brave_option=false
  rpm_option=false
  dnf_speed_option=false
  swap_ffmpeg_option=false
  config_option=false
  lazygit_option=false
  ollama_option=false
  trash_cli_option=false
  borgbackup_option=false
  syncthing_option=false

  # New experimental option flags.
  ufw_option=false
  qtile_udev_option=false
  touchpad_option=false
  thinkfan_option=false
  tlp_option=false
  remove_gnome_option=false
  zenpower_option=false
  switch_nvidia_open_option=false
  nvidia_cuda_option=false
  vaapi_option=false
  protonvpn_option=false
  update_system_option=false
  virt_option=false

  # Process command-line options.
  while getopts "abBcdFfghIilLnNopPrstTuUvVzqQx" opt; do
    case $opt in
    a) all_option=true ;;
    b) brave_option=true ;;
    B) borgbackup_option=true ;;
    c) touchpad_option=true ;;
    i) install_core_packages_option=true ;;
    I) install_system_specific_packages_option=true ;;
    s) syncthing_option=true ;;
    d) dnf_speed_option=true ;;
    V) virt_option=true ;;
    F) flatpak_option=true ;;
    f) config_option=true ;;
    l) librewolf_option=true ;;
    L) lazygit_option=true ;;
    q) qtile_option=true ;;
    Q) qtile_udev_option=true ;;
    r) rpm_option=true ;;
    x) swap_ffmpeg_option=true ;;
    o) ollama_option=true ;;
    g) remove_gnome_option=true ;;
    n) nvidia_cuda_option=true ;;
    N) switch_nvidia_open_option=true ;;
    v) vaapi_option=true ;;
    p) protonvpn_option=true ;;
    P) thinkfan_option=true ;;
    t) trash_cli_option=true ;;
    T) tlp_option=true ;;
    u) update_system_option=true ;;
    U) ufw_option=true ;;
    z) zenpower_option=true ;;
    h) usage ;;
    *) usage ;;
    esac
  done

  # If no optional flags were provided, show usage and exit.
  if [[ "$all_option" == "false" ]] &&
    [[ "$install_core_packages_option" == "false" ]] &&
    [[ "$install_system_specific_packages_option" == "false" ]] &&
    [[ "$flatpak_option" == "false" ]] &&
    [[ "$borgbackup_option" == "false" ]] &&
    [[ "$touchpad_option" == "false" ]] &&
    [[ "$trash_cli_option" == "false" ]] &&
    [[ "$tlp_option" == "false" ]] &&
    [[ "$thinkfan_option" == "false" ]] &&
    [[ "$syncthing_option" == "false" ]] &&
    [[ "$librewolf_option" == "false" ]] &&
    [[ "$qtile_option" == "false" ]] &&
    [[ "$qtile_udev_option" == "false" ]] &&
    [[ "$brave_option" == "false" ]] &&
    [[ "$rpm_option" == "false" ]] &&
    [[ "$dnf_speed_option" == "false" ]] &&
    [[ "$swap_ffmpeg_option" == "false" ]] &&
    [[ "$config_option" == "false" ]] &&
    [[ "$lazygit_option" == "false" ]] &&
    [[ "$ollama_option" == "false" ]] &&
    [[ "$remove_gnome_option" == "false" ]] &&
    [[ "$zenpower_option" == "false" ]] &&
    [[ "$nvidia_cuda_option" == "false" ]] &&
    [[ "$switch_nvidia_open_option" == "false" ]] &&
    [[ "$vaapi_option" == "false" ]] &&
    [[ "$protonvpn_option" == "false" ]] &&
    [[ "$ufw_option" == "false" ]] &&
    [[ "$update_system_option" == "false" ]] &&
    [[ "$virt_option" == "false" ]]; then
    log_warn "No options specified"
    usage
  fi

  system_type=$(detect_system_type)
  log_info "Detected system type: $system_type"

  local need_core_packages=false
  #TESTING: new options lazygit,ufw and add more if needed
  if $all_option || $qtile_option || $trash_cli_option || $borgbackup_option || $syncthing_option || $ufw_option || $lazygit_option; then
    need_core_packages=true
    log_debug "Core packages are needed due to selected options"
  fi

  # Install core packages.
  if $need_core_packages; then
    install_core_packages
  fi

  #TESTING:
  # If laptop or desktop option is selected, install system-specific packages.
  if $tlp_option || $thinkfan_option || $install_system_specific_packages_option; then
    install_system_specific_packages "$system_type"
  fi

  if $nvidia_cuda_option || $switch_nvidia_open_option || $vaapi_option || $borgbackup_option; then
    install_system_specific_packages "$system_type"
  fi

  if $all_option; then
    log_info "Executing all additional functions..."

    install_system_specific_packages "$system_type"

    # System-specific additional functions.
    #NOTE: This starts first to make sure hostname is changed first
    if [[ "$system_type" == "laptop" ]]; then
      log_info "Executing laptop-specific functions..."
      laptop_hostname_change
      #TEST: Currently on laptop but can be used on globally when desktop switch lightdm
      nopasswdlogin_group
      tlp_setup
      thinkfan_setup
      touchpad_setup
    elif [[ "$system_type" == "desktop" ]]; then
      log_info "Executing desktop-specific functions..."
      # Desktop-specific functions could be added here.
      switch_nvidia_open
      nvidia_cuda_setup
      vaapi_setup
      borgbackup_setup
      # zenpower_setup #WARN: is it safe?
    fi

    enable_rpm_fusion
    install_qtile_packages
    install_qtile_udev_rule
    ffmpeg_swap
    setup_files "$system_type"
    switch_ufw_setup

    # services
    syncthing_setup
    trash_cli_setup

    # app installations
    install_librewolf
    install_brave
    install_lazygit
    install_protonvpn
    install_flatpak_packages

  else
    log_info "Executing selected additional functions..."
    if $ufw_option; then switch_ufw_setup; fi
    if $lazygit_option; then install_lazygit; fi
    if $install_core_packages_option; then install_core_packages; fi
    if $install_system_specific_packages_option; then install_system_specific_packages "$system_type"; fi
    if $touchpad_option; then touchpad_setup; fi
    if $flatpak_option; then install_flatpak_packages; fi
    if $librewolf_option; then install_librewolf; fi
    if $qtile_option; then install_qtile_packages; fi
    if $qtile_udev_option; then install_qtile_udev_rule; fi
    if $brave_option; then install_brave; fi
    if $rpm_option; then enable_rpm_fusion; fi
    if $trash_cli_option; then trash_cli_setup; fi
    if $tlp_option; then tlp_setup; fi
    if $thinkfan_option; then thinkfan_setup; fi
    if $syncthing_option; then syncthing_setup; fi
    if $borgbackup_option; then borgbackup_setup; fi
    if $dnf_speed_option; then speed_up_dnf; fi
    if $swap_ffmpeg_option; then ffmpeg_swap; fi
    if $ollama_option; then install_ollama; fi
    if $config_option; then setup_files "$system_type"; fi
    if $remove_gnome_option; then remove_gnome; fi
    if $zenpower_option; then zenpower_setup; fi
    if $nvidia_cuda_option; then nvidia_cuda_setup; fi
    if $switch_nvidia_open_option; then switch_nvidia_open; fi
    if $vaapi_option; then vaapi_setup; fi
    if $protonvpn_option; then install_protonvpn; fi
    if $update_system_option; then system_updates; fi
    if $virt_option; then virt_manager_setup; fi
  fi

  log_info "Script execution completed."
}

# Execute main with provided command-line arguments.
main "$@"
