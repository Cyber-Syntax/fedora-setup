#!/bin/bash

# VARIABLES (general used like username, borgbackup location etc.)
# NOTE: Change these variables as needed.
USER="developer"
hostname_desktop="fedora"
hostname_laptop="fedora-laptop"
boot_file="/etc/default/grub"
tcp_bbr="/etc/sysctl.d/99-tcp-bbr.conf"
sudoers_file="/etc/sudoers.d/custom-conf"

# borg variables
borgbackup_timer="/etc/systemd/system/borgbackup-home.timer"
borgbackup_service="/etc/systemd/system/borgbackup-home.service"
borgbackup_script="/home/$USER/Documents/scripts/desktop/borg/home-borgbackup.sh"
move_opt_dir="/opt/borg/home-borgbackup.sh"

# trash-cli variables
trash_cli_service="/etc/systemd/system/trash-cli.service"
trash_cli_timer="/etc/systemd/system/trash-cli.timer"

# Browser
#NOTE: Change these variables as your profile name otherwise it will not work.
PROFILE="sqwu9kep.default-release"
firefox_profile="/home/$USER/.mozilla/firefox/$PROFILE"
librewolf_dir="/home/$USER/.librewolf/"
librewolf_profile="/home/$USER/.librewolf/profiles.ini"
