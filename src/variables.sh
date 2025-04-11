#!/usr/bin/env bash

# WARN: Change these variables as needed.
USER="developer"
SESSION="qtile"
LAPTOP_IP="192.168.1.54"

# Hostname
hostname_desktop="fedora"
hostname_laptop="fedora-laptop"

# Browser
PROFILE="sqwu9kep.default-release"
firefox_profile="/home/$USER/.mozilla/firefox/$PROFILE"
librewolf_dir="/home/$USER/.librewolf/"
librewolf_profile="/home/$USER/.librewolf/profiles.ini"

# Libvirtd
libvirt_file="./configs/libvirt/network.conf"
dir_libvirt="/etc/libvirt/network.conf"

# DNF repository directory
REPO_DIR="/etc/yum.repos.d"

# Mirror
mirror_country="de"

# Configuration directories
config_dir="./configs"
boot_file="/etc/default/grub"
sudoers_file="/etc/sudoers.d/custom-conf"

# dir_<file> : is the destination file
# file_<file> : is the source file in the repo

# Grub
# dir_grub="/etc/default/grub"
# grub_file="./configs/grub"

# network
dir_tcp_bbr="/etc/sysctl.d/99-tcp-bbr.conf"
tcp_bbr_file="./configs/99-tcp-bbr.conf"

# Sudoers
# dir_sudoers="/etc/sudoers.d/custom-conf"
# sudoers_file="./configs/custom-conf"

# borg variables
dir_borg_script="/opt/borg/home-borgbackup.sh"
borg_script_file="./configs/borg/home-borgbackup.sh"
dir_borg_timer="/etc/systemd/system/borgbackup-home.timer"
dir_borg_service="/etc/systemd/system/borgbackup-home.service"
borg_timer_file="./configs/borg/borgbackup-home.timer"
borg_service_file="./configs/borg/borgbackup-home.service"

# trash-cli variables
dir_trash_cli_service="/etc/systemd/system/trash-cli.service"
dir_trash_cli_timer="/etc/systemd/system/trash-cli.timer"
trash_cli_service_file="./configs/trash-cli/trash-cli.service"
trash_cli_timer_file="./configs/trash-cli/trash-cli.timer"

# TLP
tlp_file="./configs/01-mytlp.conf"
dir_tlp="/etc/tlp.d/01-mytlp.conf"

# touchpad
dir_touchpad="/etc/X11/xorg.conf.d/99-touchpad.conf"
touchpad_file="./configs/99-touchpad.conf"

# intel
intel_file="./configs/20-intel.conf"
dir_intel="/etc/X11/xorg.conf.d/20-intel.conf"

# qtile rules
dir_qtile_rules="/etc/udev/rules.d/99-qtile.rules"
qtile_rules_file="./configs/99-qtile.rules"

# qtile backlight
dir_backlight="/etc/X11/xorg.conf.d/99-backlight.conf"
backlight_file="./configs/99-backlight.conf"

# thinkfan
dir_thinkfan="/etc/thinkfan.conf"
thinkfan_file="./configs/thinkfan.conf"