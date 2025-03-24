#!/bin/bash
# Author: Serif Cyber-Syntax
# License: BSD 3-Clause
# Comprehensive installation and configuration script
#for dnf-based systems.

# Bash settings for strict error checking.
set -euo pipefail
IFS=$'\n\t'

# Source additional functions from separate files.
source variables.sh # make sure this sourced first to use variables in other files
source general_func.sh
source desktop_func.sh
source general_app.sh
source packages.sh

# Variable notifying the user that the script is running.
if ! id "$USER" &>/dev/null; then
  echo "WARNING: You forget to change variables according to your needs."
  # Check if user forgot to change the VARIABLES.
  if [ -n "$SUDO_USER" ]; then
    whoami="$SUDO_USER"
  else
    whoami=$(whoami)
  fi

  echo "Script USER variable is: $USER but your username: $whoami."
  echo "Please change the USER variable and other variables according to your system configuration."

  exit 1
fi

# Check if the script is run as root.
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root. Use sudo or switch to root." >&2
    exit 1
  fi
}

# Help message
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]
WARNING:
I AM NOT RESPONSIBLE FOR ANY DAMAGE CAUSED BY THIS SCRIPT. USE AT YOUR OWN RISK.
This script is need root privileges which can be dangerous.
Please, always review the script before running it.

NOTE: Please change the variables as your system configuration.

This scripts automates the installation and configuration on Fedora Linux.

Options:
  -a    Execute all functions. (NOTE:System detection handled by hostname)
  -b    Install Brave Browser.
  -B    Setup borgbackup service.
  -t    Setup trash-cli service.
  -f    Setup useful linux configurations (boot timeout, tcp_bbr, terminal password timeout).
  -F    Install Flatpak packages.
  -l    Install Librewolf browser.
  -L    Install Lazygit.
  -q    Install Qtile packages.
  -r    Enable RPM Fusion repositories.
  -d    Speed up DNF (set max_parallel_downloads, pkg_gpgcheck, etc.).
  -x    Swap ffmpeg-free with ffmpeg.
  -u    Run system updates (autoremove, fwupdmgr commands).
WARNING: Below functions are need to tested with caution.
  -g    Remove GNOME desktop environment (keep NetworkManager).
  -z    Setup zenpower for Ryzen 5000 series
  -n    Install NVIDIA CUDA
  -N    Switch to nvidia-open drivers
  -v    Setup VA-API for NVIDIA RTX series
  -p    Install ProtonVPN repository and enable OpenVPN for SELinux
  -o    Install Ollama with its install.sh script
  -h    Display this help message.

Example:
  sudo $0 -a
EOF
  exit 1
}

# Detect system type based on hostname.
detect_system_type() {
  local hostname
  hostname=$(hostname)
  echo "Detected hostname: $hostname"

  #Make sure hostnames is correct
  if [[ "$hostname" == "$hostname_desktop" ]]; then
    echo "desktop"
  elif [[ "$hostname" == "$hostname_laptop" ]]; then
    echo "laptop"
  else
    echo "Error: Unknown hostname. Please check the hostname." >&2
    exit 1
  fi
}

install_core_packages() {
  echo "Updating repositories..."
  dnf update -y || {
    echo "Error: Failed to update repositories." >&2
    return 1
  }

  echo "Installing core packages in one command..."
  dnf install -y "${CORE_PACKAGES[@]}" || {
    echo "Error: Failed to install core packages." >&2
    return 1
  }

  echo "Core packages installation completed."
}

install_system_specific_packages() {
  local system_type="$1"

  if [[ "$system_type" == "desktop" ]]; then
    echo "Installing desktop-specific packages..."
    # one line install
    dnf install -y "${DESKTOP_PACKAGES[@]}" || {
      echo "Error: Failed to install desktop packages." >&2
      return 1
    }
    echo "Desktop packages installation completed."
  elif [[ "$system_type" == "laptop" ]]; then
    echo "Installing laptop-specific packages..."
    # one line install
    dnf install -y "${LAPTOP_PACKAGES[@]}" || {
      echo "Error: Failed to install laptop packages." >&2
      return 1
    }
    echo "Laptop packages installation completed."
  else
    echo "Unknown system type. Skipping system-specific packages."
  fi
}

install_flatpak_packages() {
  echo "Installing Flatpak packages..."
  # Setup flathub if not already setup
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  # one line flatpak install
  flatpak install -y flathub "${FLATPAK_PACKAGES[@]}" || {
    echo "Error: Failed to install Flatpak packages." >&2
    return 1
  }
  echo "Flatpak packages installation completed."
}

install_qtile_packages() {
  echo "Installing Qtile packages..."
  local qtile_packages=(
    feh
    picom
    i3lock
    rofi
    qtile-extras
    lxappearance
    gammastep
    numlockx
    dunst
    flameshot
    playerctl
    xev # X event viewer
  )
  # one line install
  dnf install -y "${qtile_packages[@]}" || {
    echo "Error: Failed to install Qtile packages." >&2
    return 1
  }

  echo "Qtile packages installation completed."
}

#TEST: Both desktop and laptop
trash_cli_setup() {
  echo "Setting up trash-cli service..."
  cat <<EOF >"$trash_cli_service"
[Unit]
Description=Trash-cli cleanup service
After=network.target
# The network dependency is optional, but good practice if your command relies on network availability.

[Service]
Type=oneshot
User=developer
# Adjust the path if trash-empty is not in /usr/bin. This command removes files older than 30 days.
ExecStart=/usr/bin/trash-empty 30

# No Restart option here because this is a one-shot service.
EOF

  cat <<EOF >"$trash_cli_timer"
[Unit]
Description=Daily timer for trash-cli cleanup

[Timer]
# Runs the service daily.
OnCalendar=daily
# Persistent makes sure that if the scheduled run was missed, it will run as soon as possible.
Persistent=true

[Install]
WantedBy=timers.target
EOF

  echo "Reloading systemd..."
  systemctl daemon-reload
  echo "Enabling and starting trash-cli service..."
  systemctl enable --now trash-cli.timer
  echo "trash-cli service setup completed."
}

# Overwrites various configuration files.
# TEST: This function configures boot (GRUB), sysctl for TCP/BBR, and sudoers.
setup_files() {
  local system_type="$1"
  echo "Setting up configuration files for $system_type..."

  # 1. Boot configuration (common for both systems)
  #backup
  if [[ ! -f "$boot_file.bak" ]]; then
    cp "$boot_file" "$boot_file.bak"
  fi

  echo "Overwriting boot configuration ($boot_file) with GRUB_TIMEOUT=0..."
  echo "GRUB_TIMEOUT=0" >"$boot_file"
  echo "Regenerating GRUB configuration..."
  grub2-mkconfig -o /boot/grub2/grub.cfg

  # 2. Autologin lightdm
  local lightdm_custom="/etc/lightdm/lightdm.conf"
  # backup
  if [[ ! -f "$lightdm_custom.bak" ]]; then
    cp "$lightdm_custom" "$lightdm_custom.bak"
  fi

  echo "Overwriting LightDM configuration ($lightdm_custom) for $system_type..."
  #autologin-session=qtile.desktop
  cat <<EOF >"$lightdm_custom"
[Seat:*]
autologin-user=$USER
EOF

  #TODO: pam setup needed on lightdm
  #WARN: This need to be appended to the file
  #TEST:
  local pam_lightdm="/etc/pam.d/lightdm"
  # make a backup of the original file
  if [[ ! -f "$pam_lightdm.bak" ]]; then
    cp "$pam_lightdm" "$pam_lightdm.bak"
  fi
  echo "Setting up PAM configuration for LightDM..."
  # Append the following lines to the file.
  grep -qxF 'auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin' "$pam_lightdm" || echo 'auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin' >>"$pam_lightdm"
  grep -qxF 'auth        include     system-login' "$pam_lightdm" || echo 'auth        include     system-login' >>"$pam_lightdm"

  # 3. Increase internet speed with TCP/BBR (common for both systems).
  echo "Overwriting network settings ($tcp_bbr)..."
  cat <<EOF >"$tcp_bbr"
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.wmem_max=104857000
net.core.rmem_max=104857000
net.ipv4.tcp_rmem=4096 87380 104857000
net.ipv4.tcp_wmem=4096 87380 104857000
EOF
  echo "Reloading sysctl settings..."
  sysctl --system

  # 4. Sudoers snippet (common for both systems).
  # WARN: Is it secure to give this?
  echo "Creating/updating sudoers snippet ($sudoers_file)..."
  cat <<EOF >"$sudoers_file"
## Allow borgbackup script to run without password
developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh

## Increase timeout on terminal password prompt
Defaults timestamp_type=global
Defaults env_reset,timestamp_timeout=20
EOF
  chmod 0440 "$sudoers_file"

  echo "Configuration files have been updated for $system_type."
}

#TEST: Group for passwordless login
#Seems like this isn't called or work?
nopasswdlogin_group() {
  echo "Creating group for passwordless login..."
  groupadd -r nopasswdlogin 2>/dev/null || echo "Group 'nopasswdlogin' already exists."
  groupadd -r autologin 2>/dev/null || echo "Group 'autologin' already exists."
  # CHANGED: Replaced literal "username" with the USER variable for consistency.
  gpasswd -a "$USER" nopasswdlogin
  gpasswd -a "$USER" autologin
  echo "Group created for passwordless login."
  echo "Add users to the nopasswdlogin group to enable passwordless login."
  usermod -aG nopasswdlogin,autologin "$USER"
}

# Change hostname for laptop.
laptop_hostname_change() {
  echo "Changing hostname for laptop..."
  hostnamectl set-hostname "$hostname_laptop"
  echo "Hostname changed to $hostname_laptop."
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

  dnf install -y ./protonvpn.rpm && dnf check-update --refresh
  dnf install -y proton-vpn-gnome-desktop
  echo "ProtonVPN installation completed."

  echo "Enabling OpenVPN for SELinux..."
  #FIXME: sending else in this block
  if [[ -f "myopenvpn.pp" ]]; then
    semodule -i myopenvpn.pp
    echo "SELinux OpenVPN module installed."
  else
    echo "Warning: myopenvpn.pp not found. Please provide the SELinux policy module."
  fi
}

# TEST: Run system updates.
# This function performs cleanup and firmware update checks.
system_updates() {
  echo "Running system updates..."
  for attempt in {1..3}; do
    dnf autoremove -y && break
    echo "Autoremove failed (attempt $attempt/3), retrying..."
    sleep $((attempt * 5))
  done || {
    echo "Failed to complete autoremove after 3 attempts"
    return 1
  }

  fwupdmgr get-devices
  fwupdmgr refresh --force
  fwupdmgr get-updates -y
  fwupdmgr update -y
  echo "System updates completed. (TEST: Review update logs for any errors.)"
}
# Switch display manager to lightdm
switch_lightdm() {
  echo "Switching display manager to LightDM..."
  dnf install -y lightdm
  systemctl disable --now gdm
  systemctl enable lightdm

  echo "Display manager switched to LightDM."
}

# neovim clearing
clear_neovim() {
  echo "Backup neoVim configuration..."
  mv ~/.local/share/nvim{,.bak}
  mv ~/.local/state/nvim{,.bak}
  mv ~/.cache/nvim{,.bak}
}
#TODO: ip change

# oh-my-zsh setup
#TEST: This probably going to be cause issue because of script run as root.
# TODO: need to find a solution for this.
oh_my_zsh() {
  echo "Installing oh-my-zsh..."
  sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  #TODO: plugins installation: currently manual, need automation with package managers like dnf probably
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
  git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
}

# Security
##Randomize MAC address and  This could be used to track general network activity.
#TODO: keep static hostname
#sudo bash -c 'cat > /etc/NetworkManager/conf.d/00-macrandomize.conf' <<-'EOF'
#[device]
#wifi.scan-rand-mac-address=yes
#
#[connection]
#wifi.cloned-mac-address=random
#ethernet.cloned-mac-address=random
#EOF
#
#sudo systemctl restart NetworkManager

# --- Main function ---

main() {
  check_root

  # Quick check for help option.
  if [[ "$#" -eq 1 && "$1" == "-h" ]]; then
    usage
  fi

  # Initialize dnf speed first
  #TODO: Is there a better way to do this?
  speed_up_dnf

  # Initialize option flags.
  all_option=false
  install_core_packages_option=false
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

  # New experimental option flags.
  remove_gnome_option=false
  zenpower_option=false
  switch_nvidia_open_option=false
  nvidia_cuda_option=false
  vaapi_option=false
  protonvpn_option=false
  update_system_option=false

  # Process command-line options.
  while getopts "aFlLqbrdxfogznvpuotBih" opt; do
    case $opt in
    a) all_option=true ;;
    i) install_core_packages_option=true ;;
    b) brave_option=true ;;
    B) borgbackup_option=true ;;
    d) dnf_speed_option=true ;;
    F) flatpak_option=true ;;
    f) config_option=true ;;
    l) librewolf_option=true ;;
    L) lazygit_option=true ;;
    q) qtile_option=true ;;
    r) rpm_option=true ;;
    x) swap_ffmpeg_option=true ;;
    o) ollama_option=true ;;
    g) remove_gnome_option=true ;;
    n) nvidia_cuda_option=true ;;
    N) switch_nvidia_open_option=true ;;
    v) vaapi_option=true ;;
    p) protonvpn_option=true ;;
    t) trash_cli_option=true ;;
    u) update_system_option=true ;;
    z) zenpower_option=true ;;
    h) usage ;;
    *) usage ;;
    esac
  done

  # If no optional flags were provided, show usage and exit.
  if [[ "$all_option" == "false" ]] &&
    [[ "$install_core_packages_option" == "false" ]] &&
    [[ "$flatpak_option" == "false" ]] &&
    [[ "$borgbackup_option" == "false" ]] &&
    [[ "$trash_cli_option" == "false" ]] &&
    [[ "$librewolf_option" == "false" ]] &&
    [[ "$qtile_option" == "false" ]] &&
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
    [[ "$update_system_option" == "false" ]]; then
    usage
  fi

  # Detect system type.
  system_type=$(detect_system_type)
  echo "Detected system type: $system_type"

  # Determine if core packages are needed.
  local need_core_packages=false
  if $all_option || $qtile_option || $trash_cli_option || $borgbackup_option; then
    need_core_packages=true
  fi

  # Install core packages.
  if $need_core_packages; then
    install_core_packages
  fi

  if $all_option; then
    echo "Executing all additional functions..."

    # System-specific additional functions.
    #NOTE: This starts first to make sure hostname is changed first
    if [[ "$system_type" == "laptop" ]]; then
      echo "Executing laptop-specific functions..."
      laptop_hostname_change
      #TEST: Currently on laptop but can be used on globally when desktop switch lightdm
      #TODO: write display-manager switch function
      nopasswdlogin_group
    elif [[ "$system_type" == "desktop" ]]; then
      echo "Executing desktop-specific functions..."
      # Desktop-specific functions could be added here.
      switch_nvidia_open
      nvidia_cuda_setup
      vaapi_setup
      borgbackup_setup
      zenpower_setup #WARN: is it safe?
    fi

    #FIXME: Unknown system type. Skipping system-specific packages.
    install_system_specific_packages "$system_type"
    enable_rpm_fusion
    install_qtile_packages
    trash_cli_setup
    ffmpeg_swap
    setup_files "$system_type"
    switch_ufw_setup

    # app installations
    install_librewolf
    install_brave
    install_lazygit
    install_flatpak_packages

    # Experimental functions.
    install_protonvpn
    system_updates

  else
    echo "Executing selected additional functions..."
    if $lazygit_option; then install_lazygit; fi
    if $install_core_packages_option; then install_core_packages; fi
    if $flatpak_option; then install_flatpak_packages; fi
    if $librewolf_option; then install_librewolf; fi
    if $qtile_option; then install_qtile_packages; fi
    if $brave_option; then install_brave; fi
    if $rpm_option; then enable_rpm_fusion; fi
    if $trash_cli_option; then trash_cli_setup; fi
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
  fi

  echo "Script execution completed."
}

# Execute main with provided command-line arguments.
main "$@"
