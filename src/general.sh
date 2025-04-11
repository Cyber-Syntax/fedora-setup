#!/bin/bash

# Source the logging module
source src/logging.sh
source src/variables.sh

# Tweaks DNF configuration to improve performance.
speed_up_dnf() {
  log_info "Configuring DNF for improved performance..."
  dnf_conf="/etc/dnf/dnf.conf"
  # Backup current dnf.conf if no backup exists.
  if [[ ! -f "${dnf_conf}.bak" ]]; then
    #TESTING: error handling
    cp "$dnf_conf" "${dnf_conf}.bak" || {
      log_error "Failed to create backup of $dnf_conf"
      return 1
    }
  fi
  # 250K = 0.25MB/s
  local settings=(
    "max_parallel_downloads=20"
    "pkg_gpgcheck=True"
    "skip_if_unavailable=True"
    "minrate=250k"
    "timeout=15"
    "retries=5"
  )

  for setting in "${settings[@]}"; do
    if ! grep -q "^$setting" "$dnf_conf"; then
      log_debug "Adding setting: $setting"
      echo "$setting" >>"$dnf_conf"
    fi
  done

  log_info "DNF configuration updated successfully."
}

switch_ufw_setup() {
  log_info "Switching to UFW from firewalld..."

  # Execute commands directly instead of using log_cmd
  systemctl disable --now firewalld
  if [ $? -ne 0 ]; then
    log_error "Failed to disable firewalld"
    return 1
  fi

  systemctl enable --now ufw
  if [ $? -ne 0 ]; then
    log_error "Failed to enable UFW"
    return 1
  fi

  log_info "UFW installation completed."
  log_info "Updating UFW rules..."

  local ufw_commands=(
    "ufw default deny incoming"
    "ufw default allow outgoing"
    "ufw allow from 192.168.1.0/16"
    "ufw allow ssh"
  )

  for cmd in "${ufw_commands[@]}"; do
    eval "$cmd"
    if [ $? -ne 0 ]; then
      log_error "Failed to set UFW rule: $cmd"
      return 1
    fi
  done

  log_info "Opening ports for Syncthing..."
  
  ufw allow 22000
  if [ $? -ne 0 ]; then
    log_warn "Failed to open Syncthing TCP port"
  fi
  
  ufw allow 21027/udp
  if [ $? -ne 0 ]; then
    log_warn "Failed to open Syncthing discovery port"
  fi

  log_info "Syncthing ports opened. Check UFW status with 'ufw status verbose'"
}

# Swaps ffmpeg-free with ffmpeg if ffmpeg-free is installed.
ffmpeg_swap() {
  log_info "Checking for ffmpeg-free package..."
  if dnf list installed ffmpeg-free &>/dev/null; then
    log_info "Swapping ffmpeg-free with ffmpeg..."
    
    # Execute command directly instead of using log_cmd
    dnf swap ffmpeg-free ffmpeg --allowerasing -y
    if [ $? -eq 0 ]; then
      log_info "ffmpeg swap completed successfully."
    else
      log_error "Failed to swap ffmpeg packages"
      return 1
    fi
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
  free_repo_count=$(dnf repolist | awk '$1=="rpmfusion-free" {print $1}' | wc -l)
  nonfree_repo_count=$(dnf repolist | awk '$1=="rpmfusion-nonfree" {print $1}' | wc -l)

  # Check if both "rpmfusion-free" and "rpmfusion-nonfree" are already enabled.
  if [[ $free_repo_count -gt 0 && $nonfree_repo_count -gt 0 ]]; then
    log_info "RPM Fusion free and nonfree repositories are already enabled. Skipping installation."
    return 0
  fi

  # Otherwise, install the repositories.
  log_info "Installing RPM Fusion repositories..."
  
  # Execute command directly instead of using log_cmd
  dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm
  if [ $? -ne 0 ]; then
    log_error "Failed to install RPM Fusion repositories"
    return 1
  fi

  log_info "Upgrading system packages..."
  
  # Execute commands directly instead of using log_cmd
  dnf upgrade --refresh -y
  if [ $? -ne 0 ]; then
    log_warn "System upgrade failed"
  fi
  
  dnf group upgrade -y core
  if [ $? -ne 0 ]; then
    log_warn "Core group upgrade failed"
  fi

  log_info "Installing additional RPM Fusion components..."
  
  # Execute command directly instead of using log_cmd
  dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted dnf-plugins-core
  if [ $? -ne 0 ]; then
    log_error "Failed to install RPM Fusion tainted repositories"
    return 1
  fi

  log_info "RPM Fusion repositories enabled successfully."
}
