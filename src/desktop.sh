#!/usr/bin/env bash

source src/logging.sh
source src/variables.sh

#TODO: Need to automate update to ollama?
install_ollama() {
  log_info "Installing Ollama..."

  # Check if Ollama is already installed
  if command -v ollama &>/dev/null; then
    log_info "Ollama is already installed"
    return 0
  fi

  log_debug "Downloading and running Ollama install script..."
  if log_cmd "curl -fsSL https://ollama.com/install.sh | sed s/--add-repo/addrepo/ | sh"; then
    # Verify installation
    if command -v ollama &>/dev/null; then
      log_info "Ollama installation completed successfully"
      return 0
    else
      log_error "Ollama binary not found after installation"
      return 1
    fi
  else
    log_error "Failed to install Ollama"
    return 1
  fi
}

#TEST: Currently only for desktop
borgbackup_setup() {
  # send sh script to /opt/borg/home-borgbackup.sh
  log_info "Moving borgbackup script to /opt/borg/home-borgbackup.sh..."

  # Check directory, create if not exists
  if [[ ! -d "/opt/borg" ]]; then
    log_debug "Creating /opt/borg directory"
    mkdir -p "/opt/borg" || {
      log_error "Failed to create /opt/borg directory"
      return 1
    }
  fi
  # move from ~/Documents/scripts/desktop/borg/home-borgbackup.sh
  if ! mv "$borgbackup_script" "$move_opt_dir"; then
    log_error "Failed to move borgbackup script"
    return 1
  fi

  log_info "Setting up borgbackup service..."
  cat <<EOF >"$borgbackup_service"
[Unit]
Description=Home Backup using BorgBackup

[Service]
Type=oneshot
ExecStart=/opt/borg/home-borgbackup.sh
EOF

  cat <<EOF >"$borgbackup_timer"
[Unit]
Description=Timer for Home Backup using BorgBackup

[Timer]
# Schedules the backup at 10:00 every day.
OnCalendar=*-*-* 10:00:00
Persistent=true
# Note: systemd timers work with local time. To follow Europe/Istanbul time, ensure your system’s timezone is set accordingly.

[Install]
WantedBy=timers.target
EOF

  log_info "Reloading systemd..."
  log_cmd "systemctl daemon-reload"
  log_info "Enabling and starting borgbackup service..."
  if log_cmd "systemctl enable --now borgbackup-home.timer"; then
    log_info "borgbackup service setup completed."
  else
    log_error "Failed to enable borgbackup service"
    return 1
  fi

}

# Autologin for gdm
#NOTE: currently backlog
#TODO: Need to make $USER variable
gdm_auto_login() {
  log_info "Setting up GDM autologin..."
  local gdm_custom="/etc/gdm/custom.conf"

  # Check if user is root or has sudo privileges
  if [[ $EUID -ne 0 ]]; then
    log_error "This function must be run as root or with sudo privileges"
    return 1
  fi

  # Verify username is set
  if [[ -z "$USER" ]]; then
    log_error "USER environment variable is not set"
    return 1
  fi

  log_debug "Creating GDM configuration at $gdm_custom..."
  if ! cat <<EOF >"$gdm_custom"; then
[daemon]
WaylandEnable=false
DefaultSession=qtile.desktop
AutomaticLoginEnable=True
AutomaticLogin=$USER
EOF
    log_error "Failed to create GDM configuration file"
    return 1
  fi

  # Verify file was created and has correct content
  if [[ ! -f "$gdm_custom" ]]; then
    log_error "GDM configuration file was not created"
    return 1
  fi

  log_info "GDM autologin setup completed successfully"
  return 0
}

# TEST: Setup zenpower for Ryzen 5000 series.
# This function enables the zenpower COPR repository and installs zenpower3 and zenmonitor3.
zenpower_setup() {
  log_info "Setting up zenpower for Ryzen 5000 series..."

  # Check if running on AMD CPU
  if ! grep -q "AMD" /proc/cpuinfo; then
    log_error "This system does not appear to have an AMD CPU"
    return 1
  fi

  log_debug "Enabling zenpower3 COPR repository..."
  if ! dnf copr enable shdwchn10/zenpower3 -y; then
    log_error "Failed to enable zenpower3 COPR repository"
    return 1
  fi

  log_debug "Installing zenpower3 and zenmonitor3..."
  if ! dnf install -y zenpower3 zenmonitor3; then
    log_error "Failed to install zenpower packages"
    return 1
  fi

  local blacklist_file="/etc/modprobe.d/zenpower.conf"
  log_debug "Creating k10temp blacklist file at $blacklist_file..."
  if ! echo "blacklist k10temp" >"$blacklist_file"; then
    log_error "Failed to create k10temp blacklist file"
    return 1
  fi

  log_info "Zenpower setup completed successfully"
  log_debug "Note: Please verify if k10temp blacklisting is required for your system"
  return 0
}

# TEST: Install CUDA
nvidia_cuda_setup() {
  log_info "Setting up NVIDIA CUDA..."

  # Check if system has NVIDIA GPU
  if ! lspci | grep -i nvidia &>/dev/null; then
    log_error "No NVIDIA GPU detected in this system"
    return 1
  fi

  local arch
  arch=$(uname -m)
  local cuda_repo
  cuda_repo="https://developer.download.nvidia.com/compute/cuda/repos/fedora41/${arch}/cuda-fedora41.repo"

  log_debug "Adding CUDA repository..."
  if ! dnf config-manager addrepo --from-repofile="$cuda_repo"; then
    log_error "Failed to add CUDA repository"
    return 1
  fi

  log_debug "Cleaning DNF cache..."
  if ! dnf clean all; then
    log_error "Failed to clean DNF cache"
    return 1
  fi

  log_debug "Disabling nvidia-driver module..."
  if ! dnf module disable -y nvidia-driver; then
    log_warn "Failed to disable nvidia-driver module - this might be normal on Fedora 41"
  fi

  log_debug "Setting package exclusions..."
  local exclude_pkgs="nvidia-driver,nvidia-modprobe,nvidia-persistenced,nvidia-settings,nvidia-libXNVCtrl,nvidia-xconfig"
  if ! dnf config-manager setopt "cuda-fedora41-${arch}.exclude=${exclude_pkgs}"; then
    log_error "Failed to set package exclusions"
    return 1
  fi

  log_debug "Installing CUDA toolkit..."
  if ! dnf -y install cuda-toolkit; then
    log_error "Failed to install CUDA toolkit"
    return 1
  fi

  # Verify installation
  if ! command -v nvcc &>/dev/null; then
    log_error "CUDA toolkit installation failed - nvcc not found"
    return 1
  fi

  log_info "CUDA setup completed successfully"
  log_debug "Note: You may need to install xorg-x11-drv-nvidia-cuda-libs package"
  return 0
}

# TEST: Switch nvidia-open
switch_nvidia_open() {
  log_info "Switching to NVIDIA open source drivers..."

  # Check if system has NVIDIA GPU
  if ! lspci | grep -i nvidia &>/dev/null; then
    log_error "No NVIDIA GPU detected in this system"
    return 1
  fi

  # Check for root privileges
  if [[ $EUID -ne 0 ]]; then
    log_error "This function must be run as root or with sudo privileges"
    return 1
  fi

  local nvidia_kmod_macro="/etc/rpm/macros.nvidia-kmod"
  log_debug "Creating NVIDIA kmod macro file..."
  if ! echo "%_with_kmod_nvidia_open 1" >"$nvidia_kmod_macro"; then
    log_error "Failed to create NVIDIA kmod macro file"
    return 1
  fi

  local current_kernel
  current_kernel=$(uname -r)
  log_debug "Rebuilding NVIDIA modules for kernel $current_kernel..."
  if ! akmods --kernels "$current_kernel" --rebuild; then
    log_warn "Initial rebuild failed, attempting with --force..."
    if ! akmods --kernels "$current_kernel" --rebuild --force; then
      log_error "Failed to rebuild NVIDIA modules"
      return 1
    fi
  fi

  log_debug "Disabling RPMFusion non-free NVIDIA driver repository..."
  if ! dnf --disablerepo rpmfusion-nonfree-nvidia-driver; then
    log_error "Failed to disable RPMFusion non-free NVIDIA driver repository"
    return 1
  fi

  log_info "NVIDIA open source driver setup completed"
  log_info "Please wait 10-20 minutes for the NVIDIA modules to build, then reboot"
  log_info "After reboot, verify installation with:"
  log_info "1. 'modinfo nvidia | grep license' - should show 'Dual MIT/GPL'"
  log_info "2. 'rpm -qa kmod-nvidia*' - should show kmod-nvidia-open package"

  return 0
}

# TEST: Setup VA-API for NVIDIA RTX series.
vaapi_setup() {
  log_info "Setting up VA-API for NVIDIA RTX series..."

  # Check if system has NVIDIA GPU
  if ! lspci | grep -i nvidia &>/dev/null; then
    log_error "No NVIDIA GPU detected in this system"
    return 1
  fi

  # Install required packages
  log_debug "Installing VA-API related packages..."
  local packages=(
    "meson"
    "libva-devel"
    "gstreamer1-plugins-bad-freeworld"
    "nv-codec-headers"
    "nvidia-vaapi-driver"
    "gstreamer1-plugins-bad-free-devel"
  )

  if ! dnf install -y "${packages[@]}"; then
    log_error "Failed to install VA-API packages"
    return 1
  fi

  local env_file="/etc/environment"
  local env_vars=(
    "MOZ_DISABLE_RDD_SANDBOX=1"
    "LIBVA_DRIVER_NAME=nvidia"
    "__GLX_VENDOR_LIBRARY_NAME=nvidia"
  )

  log_debug "Setting up environment variables in $env_file..."

  # Check if variables already exist
  local need_append=false
  for var in "${env_vars[@]}"; do
    if ! grep -q "^${var}$" "$env_file" 2>/dev/null; then
      need_append=true
      break
    fi
  done

  if [[ "$need_append" == "true" ]]; then
    if ! printf '%s\n' "${env_vars[@]}" >>"$env_file"; then
      log_error "Failed to update environment variables in $env_file"
      return 1
    fi
  else
    log_debug "Environment variables already set in $env_file"
  fi

  log_info "VA-API setup completed successfully"
  log_debug "Note: You may need to reboot for changes to take effect"
  return 0
}

# TEST: Remove GNOME desktop environment while keeping NetworkManager.
# This function removes common GNOME packages. It is experimental.
#WARN: Make sure this won't delete NetworkManager
#NOTE: Do not include this all_option
remove_gnome() {
  log_info "Removing GNOME desktop environment..."

  # First check if NetworkManager is installed
  if ! rpm -q NetworkManager &>/dev/null; then
    log_error "NetworkManager is not installed"
    return 1
  fi

  # Check if GNOME is installed
  local gnome_packages=("gnome-shell" "gnome-session" "gnome-desktop")
  local any_installed=false

  for pkg in "${gnome_packages[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      any_installed=true
      break
    fi
  done

  if [[ "$any_installed" == "false" ]]; then
    log_info "GNOME packages are not installed"
    return 0
  fi

  log_warn "This will remove GNOME desktop environment. Make sure you have another DE installed."
  read -p "Do you want to continue? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "GNOME removal cancelled by user"
    return 0
  fi

  log_debug "Removing GNOME packages..."
  if ! dnf remove -y "${gnome_packages[@]}"; then
    log_error "Failed to remove GNOME packages"
    return 1
  fi

  # Verify NetworkManager is still installed
  if ! rpm -q NetworkManager &>/dev/null; then
    log_error "NetworkManager was removed during GNOME removal!"
    log_error "Please reinstall NetworkManager immediately to maintain network connectivity"
    return 1
  fi

  log_info "GNOME desktop environment removed successfully"
  log_debug "NetworkManager is still installed and preserved"
  return 0
}
