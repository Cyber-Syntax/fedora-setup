#!/usr/bin/env bash
# Author: Serif Cyber-Syntax
# License: BSD 3-Clause
# Comprehensive installation and configuration script
#for dnf-based systems.

# Bash settings for strict error checking.
set -euo pipefail
IFS=$'\n\t'

# Source additional functions from separate files.
source src/variables.sh
source src/packages.sh
source src/general.sh
source src/apps.sh
source src/desktop.sh
source src/laptop.sh

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

  # Send diagnostic messages to stderr
  echo "Detected hostname: $hostname" >&2

  if [[ "$hostname" == "$hostname_desktop" ]]; then
    detected_type="desktop"
  elif [[ "$hostname" == "$hostname_laptop" ]]; then
    detected_type="laptop"
  else
    echo "Error: Unknown hostname '$hostname'. Expected:" >&2
    echo "Desktop: $hostname_desktop" >&2
    echo "Laptop:  $hostname_laptop" >&2
    exit 1
  fi

  # Output only the type to stdout
  echo "$detected_type"
}

# Install system-specific packages
install_system_specific_packages() {
  local system_type=$(detect_system_type)
  # local system_type="${1:-unknown}"
  local pkg_list=()

  case "$system_type" in
  desktop)
    echo "Installing desktop-specific packages..."
    pkg_list=("${DESKTOP_PACKAGES[@]}")
    ;;
  laptop)
    echo "Installing laptop-specific packages..."
    pkg_list=("${LAPTOP_PACKAGES[@]}")
    ;;
  *)
    echo "Warning: Unknown system type '$system_type'. Skipping system-specific packages." >&2
    return 0
    ;;
  esac

  # Check if package list is empty
  if [[ ${#pkg_list[@]} -eq 0 ]]; then
    echo "Warning: No packages defined for $system_type installation" >&2
    return 0
  fi

  # Install packages with error handling
  if ! dnf install -y "${pkg_list[@]}"; then
    echo "Error: Failed to install some $system_type packages. Trying individual installations..." >&2

    # Fallback to per-package installation
    for pkg in "${pkg_list[@]}"; do
      echo "Attempting to install $pkg..."
      if ! dnf install -y "$pkg"; then
        echo "Warning: Failed to install package $pkg" >&2
      fi
    done
  fi

  echo "${system_type^} packages installation completed."
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

# This functions configures boot (GRUB), sysctl for TCP/BBR, and sudoers.
grub_timeout() {
  echo "Setting up boot configuration..."

  # 1. Boot configuration - Safer GRUB_TIMEOUT modification
  # Backup original file
  if [[ ! -f "$boot_file.bak" ]]; then
    cp -p "$boot_file" "$boot_file.bak"
  fi

  # Update existing GRUB_TIMEOUT or add new entry
  if grep -q '^GRUB_TIMEOUT=' "$boot_file"; then
    # Replace any existing timeout value
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$boot_file"
  else
    # Add new timeout setting after GRUB_CMDLINE_LINUX or at end of file
    if grep -q '^GRUB_CMDLINE_LINUX=' "$boot_file"; then
      sed -i '/^GRUB_CMDLINE_LINUX=/a GRUB_TIMEOUT=0' "$boot_file"
    else
      echo 'GRUB_TIMEOUT=0' >>"$boot_file"
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
  grub2-mkconfig -o /boot/grub2/grub.cfg

}
sudoers_setup() {

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
}

tcp_bbr_setup() {

  # 3. TCP/BBR configuration - Append if missing
  #FIXME: Couldn't write 'fq' to 'net/core/default_qdisc', ignoring: No such file or directory
  #Couldn't write 'bbr' to 'net/ipv4/tcp_congestion_control', ignoring: No such file or directory
  declare -A sysctl_params=(
    ["net.core.default_qdisc"]="fq"
    ["net.ipv4.tcp_congestion_control"]="bbr"
    ["net.core.wmem_max"]="104857000"
    ["net.core.rmem_max"]="104857000"
    ["net.ipv4.tcp_rmem"]="4096 87380 104857000"
    ["net.ipv4.tcp_wmem"]="4096 87380 104857000"
  )

  for param in "${!sysctl_params[@]}"; do
    if ! grep -qE "^$param = " "$tcp_bbr"; then
      echo "$param = ${sysctl_params[$param]}" >>"$tcp_bbr"
    fi
  done

  #   # 3. Increase internet speed with TCP/BBR (common for both systems).
  #   echo "Overwriting network settings ($tcp_bbr)..."
  #   cat <<EOF >"$tcp_bbr"
  # net.core.default_qdisc=fq
  # net.ipv4.tcp_congestion_control=bbr
  # net.core.wmem_max=104857000
  # net.core.rmem_max=104857000
  # net.ipv4.tcp_rmem=4096 87380 104857000
  # net.ipv4.tcp_wmem=4096 87380 104857000
  # EOF
  echo "Reloading sysctl settings..."
  sysctl --system

}

lightdm_autologin() {

  local conf_file="/etc/lightdm/lightdm.conf"
  local tmp_file=$(mktemp)

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

  #   # 2. Autologin lightdm
  #   local lightdm_custom="/etc/lightdm/lightdm.conf"
  #   # backup
  #   if [[ ! -f "$lightdm_custom.bak" ]]; then
  #     cp "$lightdm_custom" "$lightdm_custom.bak"
  #   fi
  #
  #   echo "Overwriting LightDM configuration ($lightdm_custom) for $system_type..."
  #   cat <<EOF >"$lightdm_custom"
  # [Seat:*]
  # autologin-guest=false
  # autologin-user=$USER
  # autologin-session=$SESSION
  # autologin-user-timeout=0
  # autologin-in-background=false
  # EOF
  #

  #Pam setup needed on lightdm
  local pam_lightdm="/etc/pam.d/lightdm"
  # make a backup of the original file
  if [[ ! -f "$pam_lightdm.bak" ]]; then
    cp "$pam_lightdm" "$pam_lightdm.bak"
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
  groupadd -r nopasswdlogin 2>/dev/null || echo "Group 'nopasswdlogin' already exists."
  groupadd -r autologin 2>/dev/null || echo "Group 'autologin' already exists."
  gpasswd -a "$USER" nopasswdlogin
  gpasswd -a "$USER" autologin
  echo "Group created for passwordless login."
  echo "Add users to the nopasswdlogin group to enable passwordless login."
  usermod -aG nopasswdlogin,autologin "$USER"
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
# Syncthing setup
syncthing_setup() {
  echo "Setting up Syncthing..."
  #FIX: this script run root which cause this "Failed to connect to user scope bus via local transport: No medium found"
  # need to run this without root or find a workaround
  #NOTE: it was already running though??
  systemctl --user enable --now syncthing
  echo "Syncthing enabled."
}

# Switch display manager to lightdm
switch_lightdm() {
  echo "Switching display manager to LightDM..."
  dnf install -y lightdm
  systemctl disable gdm
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
oh_my_zsh_setup() {
  echo "Installing oh-my-zsh..."
  sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  #TODO: plugins installation: currently manual, need automation with package managers like dnf probably
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
  git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
  # How to solve root issue?
}

#TEST: fedora mirror country change to get good speeds
#TODO: need little research on this to make it more efficient
mirror_country_change() {
  echo "Changing Fedora mirror country..."
  # on /etc/yum.repos.d/fedora.repo and similar repos need only `&country=de` in the end on metalink
  # metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch&country=de
  # variable mirror_country="de" handled on variable.sh
  # also there is 3 metalink on the files generally, [fedora-source], [fedora] and [fedora-debuginfo]
  # also need to commeent t he baseurl

}

#TEST: When you use same home partition when you switch distro, selinux context is not correct
#TODO: add option
selinux_restorecon() {
  echo "Restoring SELinux context for home directory..."
  restorecon -R /home/
}

# sshd setup, copy ssh keys to laptop from desktop etc.
ssh_setup_laptop() {
  echo "Setting up SSH for laptop"

  # Enable password authentication to be able to receive keys
  systemctl enable --now sshd
  # Write sshd config to allow password authentication
  #TODO: Add some security here
  cat <<EOF >/etc/ssh/sshd_config.d/temp_password_auth.conf
PasswordAuthentication yes
PermitRootLogin no
PermitEmptyPasswords yes
EOF
  echo "SSH password authentication enabled for laptop."
}
ssh_setup_desktop() {
  echo "Setting up SSH..."

  # TODO: need to create keys but if they are not created yet.
  # NOTE: desktop sends keys to laptop here
  ssh-copy-id $USER@$LAPTOP_IP
}

# TODO: mpv setup

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

  # Process command-line options.
  while getopts "abBcdFfghIilLnopPrstTuvzqQx" opt; do
    case $opt in
    a) all_option=true ;;
    b) brave_option=true ;;
    B) borgbackup_option=true ;;
    c) touchpad_option=true ;;
    i) install_core_packages_option=true ;;
    I) install_system_specific_packages_option=true ;;
    s) syncthing_option=true ;;
    d) dnf_speed_option=true ;;
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
    [[ "$update_system_option" == "false" ]]; then
    usage
  fi

  # Detect system type.
  system_type=$(detect_system_type)
  echo "Detected system type: $system_type"

  # Determine if core packages are needed.
  local need_core_packages=false
  #TESTING: new options lazygit,ufw and add more if needed
  if $all_option || $qtile_option || $trash_cli_option || $borgbackup_option || $syncthing_option || $ufw_option || $lazygit_option; then
    need_core_packages=true
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
    echo "Executing all additional functions..."

    install_system_specific_packages "$system_type"

    # System-specific additional functions.
    #NOTE: This starts first to make sure hostname is changed first
    if [[ "$system_type" == "laptop" ]]; then
      echo "Executing laptop-specific functions..."
      laptop_hostname_change
      #TEST: Currently on laptop but can be used on globally when desktop switch lightdm
      nopasswdlogin_group
      tlp_setup
      thinkfan_setup
      touchpad_setup
    elif [[ "$system_type" == "desktop" ]]; then
      echo "Executing desktop-specific functions..."
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
    echo "Executing selected additional functions..."
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
  fi

  echo "Script execution completed."
}

# Execute main with provided command-line arguments.
main "$@"
