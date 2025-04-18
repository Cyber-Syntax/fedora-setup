#!/usr/bin/env bash
# Author: Serif Cyber-Syntax
# License: BSD 3-Clause
# Comprehensive installation and configuration script
#for sudo dnf-based systems.

# Prevents the script from continuing on errors, unset variables, and pipe failures.
set -euo pipefail
IFS=$'\n\t'

#!/usr/bin/env bash

# Setup XDG Base Directory paths if not already set
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

source src/logging.sh
source src/config.sh
source src/general.sh
source src/apps.sh
source src/desktop.sh
source src/laptop.sh

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
  -A    Install application packages.
  -D    Install development packages.

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

# Check if any options that use DNF installation are enabled
needs_dnf_speedup() {
  # Return true if any of these options are enabled
  if $all_option ||
    $install_core_packages_option ||
    $install_system_specific_packages_option ||
    $install_app_packages_option ||
    $install_dev_packages_option ||
    $librewolf_option ||
    $qtile_option ||
    $brave_option ||
    $rpm_option ||
    $tlp_option ||
    $nvidia_cuda_option ||
    $switch_nvidia_open_option ||
    $virt_option ||
    $ufw_option ||
    $trash_cli_option ||
    $borgbackup_option ||
    $zenpower_option ||
    $vaapi_option ||
    $swap_ffmpeg_option ||
    $protonvpn_option ||
    $ollama_option; then
    return 0 # true in bash
  fi
  return 1 # false in bash
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
  log_info "Installing core packages..."
  if ! sudo dnf install -y "${CORE_PACKAGES[@]}"; then
    log_error "Error: Failed to install core packages." >&2
    return 1
  fi

  log_info "Core packages installation completed."
}

install_app_packages() {
  log_info "Installing application packages..."
  if ! sudo dnf install -y "${APPS_PACKAGES[@]}"; then
    log_error "Error: Failed to install application packages." >&2
    return 1
  fi

  log_info "Application packages installation completed."
}

install_dev_packages() {
  log_info "Installing development packages..."
  if ! sudo dnf install -y "${DEV_PACKAGES[@]}"; then
    log_error "Error: Failed to install development packages." >&2
    return 1
  fi

  log_info "Development packages installation completed."
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

#TODO: need little research on this to make it more efficient
mirror_country_change() {
  log_info "Changing Fedora mirror country..."
  # on /etc/yum.repos.d/fedora.repo and similar repos need only `&country=de` in the end on metalink
  # metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch&country=de
  # variable mirror_country="de" handled on variable.sh
  # also there is 3 metalink on the files generally, [fedora-source], [fedora] and [fedora-debuginfo]
  # also need to commeent the baseurl
}

main() {
  # Show help message if no arguments are provided or if -h is passed.
  if [[ "$#" -eq 1 && "$1" == "-h" ]]; then
    usage
  fi

  log_debug "Initializing script with args: $*"

  # Initialize option flags.
  all_option=false
  install_core_packages_option=false
  install_system_specific_packages_option=false
  install_app_packages_option=false
  install_dev_packages_option=false
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
  while getopts "abBcdDFfghIiAalLnNopPrstTuUvVzqQx" opt; do
    case $opt in
      a) all_option=true ;;
      A) install_app_packages_option=true ;;
      D) install_dev_packages_option=true ;;
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
    [[ "$install_app_packages_option" == "false" ]] &&
    [[ "$install_dev_packages_option" == "false" ]] &&
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
  if $all_option || $qtile_option || $trash_cli_option || $borgbackup_option || $syncthing_option || $ufw_option || $lazygit_option || $virt_option; then
    need_core_packages=true
    log_debug "Core packages are needed due to selected options"
  fi

  # Apply DNF speedup if any options requiring DNF installation are enabled
  if needs_dnf_speedup; then
    log_info "Optimizing DNF configuration for faster package operations..."
    speed_up_dnf || log_warn "Failed to optimize DNF configuration"
  fi

  # Install core packages.
  if $need_core_packages; then
    install_core_packages
  fi

  # If laptop or desktop option is selected, install system-specific packages.
  if $tlp_option || $thinkfan_option || $install_system_specific_packages_option; then
    install_system_specific_packages "$system_type"
  fi

  if $nvidia_cuda_option || $switch_nvidia_open_option || $vaapi_option || $borgbackup_option; then
    install_system_specific_packages "$system_type"
  fi

  # Handle all_option logic
  if $all_option; then
    log_info "Executing all additional functions..."

    # Install all package types
    install_core_packages
    install_app_packages
    install_dev_packages
    install_system_specific_packages "$system_type"

    # System-specific additional functions.
    #NOTE: This starts first to make sure hostname is changed first
    if [[ "$system_type" == "laptop" ]]; then
      log_info "Executing laptop-specific functions..."
      laptop_hostname_change
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

    nopasswdlogin_group
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
    if $install_app_packages_option; then install_app_packages; fi
    if $install_dev_packages_option; then install_dev_packages; fi
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
