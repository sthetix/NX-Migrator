#!/bin/bash
# Title: NX Migrator 1.0.1
# Description: Migrates Nintendo Switch SD card emuMMC (RAW partition) and FAT32 content to a larger SD card using Hekate USB Tools.
# Version: 1.0.0
# License: GNU General Public License v2

# Enable debug mode if specified
DEBUG_MODE="no"
[ "$1" == "--debug" ] && { DEBUG_MODE="yes"; set -x; }

# Ensure script runs with sudo
[ "$EUID" -ne 0 ] && { echo -e "\033[1mError: Run with sudo.\033[0m"; exit 1; }

# Get user’s home directory
[ -z "$SUDO_USER" ] && { echo -e "\033[1mError: SUDO_USER not set. Run with sudo.\033[0m"; exit 1; }
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

# Display introduction
clear
echo -e "\033[1m=== NX Migrator 1.0.1 ===\033[0m"
echo -e "\033[1mMigrates Switch SD card (via Hekate USB or SD reader) with emuMMC and FAT32 to a larger SD.\033[0m"
echo -e "\nSteps:\n  1. Detect source and target SD cards\n  2. Backup emuMMC (or use existing)\n  3. Restore emuMMC to target SD\n  4. Copy FAT32 content"
echo -e "\n\033[1mWARNING: Do not remove target SD until 'emuMMC restored' appears, or emuMMC may corrupt.\033[0m"
echo
echo -e "\033[1mPress Enter to proceed...\033[0m"
read -r

# Setup backup directory and log file
BACKUP_DIR="${USER_HOME}/nx_migrator_backups"
LOGFILE="${BACKUP_DIR}/nx_migrator_$(date +%F_%H-%M-%S).log"
echo -e "\033[1mBackup directory: $BACKUP_DIR\033[0m"
mkdir -p "$BACKUP_DIR" || { echo -e "\033[1mError: Cannot create $BACKUP_DIR.\033[0m"; exit 1; }
echo -e "\033[1mLog file: $LOGFILE\033[0m"
touch "$LOGFILE" 2>/dev/null || { echo -e "\033[1mError: Cannot write to $LOGFILE. Check permissions or space.\033[0m"; exit 1; }

# Function to safely log messages
safe_log() {
    [ -f "$LOGFILE" ] && echo "$@" | tee -a "$LOGFILE" || echo "$@"
}

# Redirect output to log and terminal
exec 1> >(while IFS= read -r line; do safe_log "$line"; done) 2>&1

# Check dependencies
safe_log -e "\033[1mChecking dependencies...\033[0m"

# Function to detect OS and set package manager
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        INSTALL_CMD="sudo apt update && sudo apt install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
    else
        safe_log -e "\033[1mError: No supported package manager (apt, pacman, dnf) found.\033[0m"
        exit 1
    fi
    safe_log -e "\033[1mDetected package manager: $PKG_MANAGER\033[0m"
}

# Define commands and corresponding packages for each package manager
COMMANDS=("parted" "sfdisk" "mkfs.vfat" "lsblk" "blkid" "bc" "partprobe" "sgdisk" "blockdev" "dd" "mountpoint" "find" "fuser" "du" "stat" "tar" "pv")
PACKAGES_DEBIAN=("parted" "fdisk" "dosfstools" "util-linux" "util-linux" "bc" "parted" "gdisk" "util-linux" "coreutils" "mountpoint" "findutils" "psmisc" "coreutils" "coreutils" "tar" "pv")
PACKAGES_ARCH=("parted" "util-linux" "dosfstools" "util-linux" "util-linux" "bc" "parted" "gdisk" "util-linux" "coreutils" "mountpoint" "findutils" "psmisc" "coreutils" "coreutils" "tar" "pv")
PACKAGES_FEDORA=("parted" "util-linux" "dosfstools" "util-linux" "util-linux" "bc" "parted" "gdisk" "util-linux" "coreutils" "mountpoint" "findutils" "psmisc" "coreutils" "coreutils" "tar" "pv")

# Detect package manager
detect_package_manager

# Install missing dependencies
for i in "${!COMMANDS[@]}"; do
    cmd="${COMMANDS[$i]}"
    case $PKG_MANAGER in
        apt)
            pkg="${PACKAGES_DEBIAN[$i]}"
            ;;
        pacman)
            pkg="${PACKAGES_ARCH[$i]}"
            ;;
        dnf)
            pkg="${PACKAGES_FEDORA[$i]}"
            ;;
        *)
            safe_log -e "\033[1mError: Unsupported package manager.\033[0m"
            exit 1
            ;;
    esac
    command -v "$cmd" &>/dev/null && continue
    safe_log "Installing $pkg for $cmd..."
    ping -c 1 8.8.8.8 >/dev/null 2>&1 || { safe_log -e "\033[1mError: No internet.\033[0m"; exit 1; }
    $INSTALL_CMD "$pkg" >>"$LOGFILE" 2>&1 || { safe_log -e "\033[1mError: Failed to install $pkg. See $LOGFILE.\033[0m"; exit 1; }
    safe_log "$pkg installed."
done
safe_log -e "\033[1mDependencies ready.\033[0m\n"

# Cleanup function for mounts and processes
cleanup_mounts() {
    safe_log -e "\033[1mCleaning mounts and processes...\033[0m"
    sudo pkill -9 cp dd tar pv 2>/dev/null
    for MNT in "$SOURCE_MOUNT" "$DEST_MOUNT" "/media/$SUDO_USER/SWITCH SD" "/media/$SUDO_USER/SWITCH SD1" "/dev/sda"* "/dev/sdb"*; do
        if mountpoint -q "$MNT" 2>/dev/null || mount | grep -q "$MNT"; then
            sudo lsof "$MNT" >/dev/null 2>&1 && { safe_log -e "\033[1mWarning: Processes using $MNT. Terminating...\033[0m"; sudo lsof "$MNT" >>"$LOGFILE" 2>&1; sudo fuser -km "$MNT" 2>>"$LOGFILE"; sleep 1; }
            sudo umount "$MNT" 2>>"$LOGFILE" || { safe_log -e "\033[1mWarning: umount failed for $MNT. Lazy unmounting...\033[0m"; sudo umount -l "$MNT" 2>>"$LOGFILE"; }
        fi
    done
    rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null
    mount | grep -q "$SOURCE_MOUNT" || mount | grep -q "$DEST_MOUNT" && { safe_log -e "\033[1mError: Unmount failed. Check with 'sudo lsof' or 'sudo fuser -m'.\033[0m"; mount >>"$LOGFILE" 2>&1; sudo lsof /dev/sda* /dev/sdb* >>"$LOGFILE" 2>&1; sudo fuser -m /dev/sda* /dev/sdb* >>"$LOGFILE" 2>&1; exit 1; }
    safe_log -e "\033[1mUnmount completed.\033[0m"
}

# Trap signals for cleanup
trap 'cleanup_mounts; exit 1' INT TERM
trap 'cleanup_mounts' EXIT

# Step 1: Detect source and target SD cards
safe_log -e "\033[1m=== Step 1/4: Detect SD Cards ===\033[0m"
safe_log -e "\033[1mScanning for SD cards...\033[0m"
echo -n "Detecting"
SOURCE_SD="" SOURCE_SD_SIZE="" SOURCE_FAT_PART="" SOURCE_RAW_PART="" DEST_SD="" DEST_SD_SIZE=""
TIMEOUT=60 COUNT=0
while { [ -z "$SOURCE_SD" ] || [ -z "$DEST_SD" ]; } && [ $COUNT -lt $TIMEOUT ]; do
    echo "lsblk output:" >>"$LOGFILE"
    LC_ALL=C lsblk -o NAME,SIZE,LABEL,TYPE,FSTYPE >>"$LOGFILE" 2>&1
    NEW_DISKS=$(LC_ALL=C lsblk -o NAME,SIZE,LABEL,TYPE | grep disk | grep -v "$(lsblk -o NAME,MOUNTPOINT | grep / | awk '{print $1}')" | grep -E '^[a-zA-Z0-9]+')
    if [ -n "$NEW_DISKS" ] && [ "$(echo "$NEW_DISKS" | wc -l)" -ge 2 ]; then
        echo -e "\n\033[1mDetected devices:\033[0m"
        echo "$NEW_DISKS"
        dmesg | grep -i "usb" | tail -n 5 | grep -E "new.*device" >>"$LOGFILE"
        echo -e "\033[1mEnter source SD device (e.g., sdc) for Hekate USB or 'retry':\033[0m"
        read -r SOURCE_SD
        if [ "$SOURCE_SD" = "retry" ] || [ -z "$SOURCE_SD" ] || [ ! -b "/dev/$SOURCE_SD" ]; then
            SOURCE_SD=""; echo -n "Retrying"; continue
        fi
        SOURCE_SD="/dev/$SOURCE_SD"
        SOURCE_SD_SIZE=$(lsblk -b -n -o SIZE "$SOURCE_SD" 2>/dev/null | head -n 1)
        [ -z "$SOURCE_SD_SIZE" ] && { safe_log -e "\033[1mError: Cannot get size of $SOURCE_SD.\033[0m"; SOURCE_SD=""; echo -n "Retrying"; continue; }
        SOURCE_SD_SIZE_GB=$(echo "scale=1; $SOURCE_SD_SIZE / 1024 / 1024 / 1024" | bc)
        PART_INFO=$(parted -s "$SOURCE_SD" unit s print 2>/dev/null | grep -E "^ [0-9]+" || true)
        echo "parted output for source:" >>"$LOGFILE"
        parted -s "$SOURCE_SD" unit s print >>"$LOGFILE" 2>&1
        [ -z "$PART_INFO" ] && { safe_log -e "\033[1mError: No partitions on $SOURCE_SD. Check Hekate UMS.\033[0m"; SOURCE_SD=""; echo -n "Retrying"; continue; }
        while read -r LINE; do
            PART_NUM=$(echo "$LINE" | awk '{print $1}')
            PART_TYPE=$(echo "$LINE" | awk '{print $5}')
            PART_SIZE=$(echo "$LINE" | awk '{print $4}' | grep -oE '[0-9]+')
            PART_SIZE_MB=$(echo "$PART_SIZE * 512 / 1024 / 1024" | bc)
            [[ "$PART_TYPE" =~ fat32|exfat|vfat|fat ]] && SOURCE_FAT_PART="/dev/${SOURCE_SD##*/}${PART_NUM}"
            [[ "$PART_TYPE" =~ ^(primary|)$ && $PART_SIZE_MB -ge 4000 && $PART_SIZE_MB -le 58000 ]] && SOURCE_RAW_PART="/dev/${SOURCE_SD##*/}${PART_NUM}"
        done <<<"$PART_INFO"
        if [ -z "$SOURCE_FAT_PART" ]; then
            for PART in $(lsblk -ln -o NAME "$SOURCE_SD" | grep -E "^${SOURCE_SD##*/}[0-9]+$"); do
                FS_TYPE=$(blkid -s TYPE -o value "/dev/$PART" 2>/dev/null || true)
                [[ "$FS_TYPE" =~ fat32|exfat|vfat|fat ]] && sudo dd if="/dev/$PART" of="/dev/null" bs=512 count=1 status=none 2>/dev/null && { SOURCE_FAT_PART="/dev/$PART"; break; }
            done
        fi
        if [ -z "$SOURCE_RAW_PART" ]; then
            for PART in $(lsblk -ln -o NAME,SIZE "$SOURCE_SD" | grep -E "^${SOURCE_SD##*/}[0-9]+$" | awk '{print $1}'); do
                PART_SIZE=$(lsblk -b -n -o SIZE "/dev/$PART" 2>/dev/null)
                PART_SIZE_MB=$((PART_SIZE / 1024 / 1024))
                [ "$PART_SIZE_MB" -ge 4000 ] && [ "$PART_SIZE_MB" -le 58000 ] && { SOURCE_RAW_PART="/dev/$PART"; break; }
            done
        fi
        [ -z "$SOURCE_FAT_PART" ] || [ -z "$SOURCE_RAW_PART" ] && { safe_log -e "\033[1mError: Invalid partitions on $SOURCE_SD (need FAT32/exFAT and RAW 4-58 GB).\033[0m"; SOURCE_SD=""; echo -n "Retrying"; continue; }
        RAW_SIZE_MB=$(blockdev --getsize64 "$SOURCE_RAW_PART" 2>/dev/null | awk '{print $1 / 1024 / 1024}')
        [ -z "$RAW_SIZE_MB" ] || [ "$RAW_SIZE_MB" -lt 4000 ] || [ "$RAW_SIZE_MB" -gt 58000 ] && { safe_log -e "\033[1mError: Invalid RAW partition size ($RAW_SIZE_MB MB, expected 4-58 GB).\033[0m"; SOURCE_SD=""; echo -n "Retrying"; continue; }
        echo -e "\033[1mEnter target SD device (e.g., sdb) for reader or 'retry':\033[0m"
        read -r DEST_SD
        if [ "$DEST_SD" = "retry" ] || [ -z "$DEST_SD" ] || [ ! -b "/dev/$DEST_SD" ] || [ "$DEST_SD" = "${SOURCE_SD##*/}" ]; then
            DEST_SD=""; echo -n "Retrying"; continue
        fi
        DEST_SD="/dev/$DEST_SD"
        DEST_SD_SIZE=$(lsblk -b -n -o SIZE "$DEST_SD" 2>/dev/null | head -n 1)
        [ -z "$DEST_SD_SIZE" ] && { safe_log -e "\033[1mError: Cannot get size of $DEST_SD.\033[0m"; DEST_SD=""; echo -n "Retrying"; continue; }
        DEST_SD_SIZE_GB=$(echo "scale=1; $DEST_SD_SIZE / 1024 / 1024 / 1024" | bc)
        [ "$DEST_SD_SIZE" -lt "$SOURCE_SD_SIZE" ] && { safe_log -e "\033[1mError: Target SD ($DEST_SD_SIZE_GB GB) smaller than source ($SOURCE_SD_SIZE_GB GB).\033[0m"; DEST_SD=""; echo -n "Retrying"; continue; }
        safe_log -e "\033[1mDetected devices:\033[0m"
        safe_log "Source SD (Hekate USB): $SOURCE_SD ($SOURCE_SD_SIZE_GB GB)"
        safe_log "  FAT32/exFAT: $SOURCE_FAT_PART"
        safe_log "  RAW (emuMMC): $SOURCE_RAW_PART ($RAW_SIZE_MB MB)"
        safe_log "Target SD (reader): $DEST_SD ($DEST_SD_SIZE_GB GB)"
        safe_log -e "\033[1mAre these correct? (yes/no)\033[0m"
        read -r CONFIRM_DEVICES
        CONFIRM_DEVICES=$(echo "$CONFIRM_DEVICES" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        echo "User confirmed devices: $CONFIRM_DEVICES" >>"$LOGFILE"
        [ "$CONFIRM_DEVICES" == "yes" ] && break
        SOURCE_SD="" SOURCE_FAT_PART="" SOURCE_RAW_PART="" DEST_SD=""
        echo -n "Retrying"
    fi
    echo -n "."; sleep 1; COUNT=$((COUNT + 1))
done

[ -z "$SOURCE_SD" ] || [ -z "$DEST_SD" ] && {
    safe_log -e "\033[1mError: Cannot detect source or target SD.\033[0m"
    safe_log "Ensure:\n  - Switch connected via Hekate USB Tools in UMS mode.\n  - Target SD inserted in reader."
    lsblk -o NAME,SIZE,LABEL,TYPE,FSTYPE
    echo "Debug: dmesg output:" >>"$LOGFILE"
    sudo dmesg | tail -n 20 >>"$LOGFILE" 2>&1
    exit 1
}

# Unmount any automounted partitions
safe_log -e "\033[1mUnmounting automounted partitions...\033[0m"
for SD in "$SOURCE_SD" "$DEST_SD"; do
    for PART in $(lsblk -ln -o NAME "$SD" | grep -E "^${SD##*/}[0-9]+$" || true); do
        echo "Checking /dev/$PART for mounts" >>"$LOGFILE"
        if mountpoint -q "/dev/$PART" 2>/dev/null || mount | grep -q "/dev/$PART"; then
            for i in {1..3}; do
                sudo lsof "/dev/$PART" >/dev/null 2>&1 && { safe_log -e "\033[1mWarning: Processes using /dev/$PART. Terminating...\033[0m"; sudo lsof "/dev/$PART" >>"$LOGFILE" 2>&1; sudo fuser -km "/dev/$PART" 2>>"$LOGFILE"; sleep 1; }
                sudo umount "/dev/$PART" 2>>"$LOGFILE" && { echo "Unmounted /dev/$PART" >>"$LOGFILE"; break; }
                safe_log -e "\033[1mWarning: Failed to unmount /dev/$PART (try $i/3), retrying...\033[0m"
                sleep 1
            done
            mountpoint -q "/dev/$PART" 2>/dev/null || mount | grep -q "/dev/$PART" && { safe_log -e "\033[1mError: Cannot unmount /dev/$PART.\033[0m"; safe_log "Check with 'sudo lsof /dev/$PART' or 'sudo fuser -m /dev/$PART'."; exit 1; }
        else
            echo "/dev/$PART not mounted" >>"$LOGFILE"
        fi
    done
done
sync
safe_log -e "\033[1mAll partitions unmounted.\033[0m"

# Step 2: Backup or verify emuMMC
safe_log -e "\033[1m=== Step 2/4: Backup/Verify emuMMC ===\033[0m"
BACKUP_FILE="$BACKUP_DIR/emummc.img"
if [ -f "$BACKUP_FILE" ]; then
    safe_log -e "\033[1mFound emuMMC backup: $BACKUP_FILE\033[0m"
    safe_log "Options:  1. Redump RAW partition (overwrites backup) 2. Use existing backup"
    while true; do
        safe_log -e "\033[1mChoose option (1 or 2):\033[0m"
        read -r BACKUP_OPTION
        BACKUP_OPTION=$(echo "$BACKUP_OPTION" | tr -d '[:space:]')
        echo "User chose backup option: $BACKUP_OPTION" >>"$LOGFILE"
        case "$BACKUP_OPTION" in
            1) safe_log -e "\033[1mRedumping emuMMC (~$RAW_SIZE_MB MB)...\033[0m"; SKIP_BACKUP="no"; break ;;
            2) safe_log -e "\033[1mUsing backup: $BACKUP_FILE\033[0m"; SKIP_BACKUP="yes"; break ;;
            *) safe_log -e "\033[1mInvalid choice. Enter 1 or 2.\033[0m" ;;
        esac
    done
else
    safe_log -e "\033[1mNo emuMMC backup found in $BACKUP_DIR. Creating new backup...\033[0m"
    SKIP_BACKUP="no"
fi

# Backup emuMMC
if [ "$SKIP_BACKUP" != "yes" ]; then
    safe_log -e "\033[1mChecking disk space for backup...\033[0m"
    EMUMMC_SIZE=$(blockdev --getsize64 "$SOURCE_RAW_PART" 2>/dev/null)
    [ -z "$EMUMMC_SIZE" ] || [ "$EMUMMC_SIZE" -le 0 ] && { safe_log -e "\033[1mError: Cannot get size of $SOURCE_RAW_PART.\033[0m"; exit 1; }
    EMUMMC_SIZE_MB=$((EMUMMC_SIZE / 1024 / 1024))
    REQUIRED_SPACE=$EMUMMC_SIZE
    AVAILABLE_SPACE=$(df -B1 "$BACKUP_DIR" | tail -1 | awk '{print $4}')
    REQUIRED_SPACE_GB=$(echo "scale=1; $REQUIRED_SPACE / 1024 / 1024 / 1024" | bc)
    AVAILABLE_SPACE_GB=$(echo "scale=1; $AVAILABLE_SPACE / 1024 / 1024 / 1024" | bc)
    [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ] && { safe_log -e "\033[1mError: Not enough space in $BACKUP_DIR. Need ~$REQUIRED_SPACE_GB GB, have $AVAILABLE_SPACE_GB GB.\033[0m"; exit 1; }
    safe_log -e "\033[1mSpace sufficient (~$AVAILABLE_SPACE_GB GB, need ~$REQUIRED_SPACE_GB GB).\033[0m"
    safe_log -e "\033[1mBacking up emuMMC (~$EMUMMC_SIZE_MB MB)...\033[0m\033[?25l"
    [ -f "$BACKUP_FILE" ] && { echo "Removing $BACKUP_FILE..." >>"$LOGFILE"; sudo rm -f "$BACKUP_FILE" || { safe_log -e "\033[1mError: Cannot remove $BACKUP_FILE.\033[0m"; exit 1; }; }
    if command -v pv >/dev/null 2>&1 && tty >/dev/null 2>&1; then
        sudo pv -s "$EMUMMC_SIZE" -F "%t %b %r %p %e" -f -i 0.5 "$SOURCE_RAW_PART" 2> >(tee -a "$LOGFILE" >/dev/tty) | sudo dd of="$BACKUP_FILE" bs=4M 2>>"$LOGFILE"; echo -ne "\033[?25h"
        DD_STATUS=$?
    else
        safe_log -e "\033[1mWarning: pv unavailable or no TTY, using dd...\033[0m"
        sudo dd if="$SOURCE_RAW_PART" of="$BACKUP_FILE" bs=4M status=progress 2>&1 | tee -a "$LOGFILE"
        DD_STATUS=$?
    fi
    sync
    [ $DD_STATUS -ne 0 ] && { safe_log -e "\033[1mError: emuMMC backup failed. See $LOGFILE.\033[0m"; exit 1; }
    BACKUP_SIZE=$(stat -c %s "$BACKUP_FILE" 2>/dev/null || echo 0)
    BACKUP_SIZE_MB=$((BACKUP_SIZE / 1024 / 1024))
    [ "$BACKUP_SIZE" -lt "$EMUMMC_SIZE" ] && { safe_log -e "\033[1mError: Backup size ($BACKUP_SIZE_MB MB) smaller than expected ($EMUMMC_SIZE_MB MB).\033[0m"; exit 1; }
    safe_log -e "\033[1mBackup size verified: $BACKUP_SIZE_MB MB\033[0m"
fi

# Verify backup size
safe_log -e "\033[1mVerifying emuMMC backup...\033[0m"
EMUMMC_SIZE=$(stat -c %s "$BACKUP_FILE")
EMUMMC_SIZE_MB=$((EMUMMC_SIZE / 1024 / 1024))
[ "$EMUMMC_SIZE_MB" -lt 4000 ] || [ "$EMUMMC_SIZE_MB" -gt 58000 ] && { safe_log -e "\033[1mError: emuMMC size ($EMUMMC_SIZE_MB MB) outside 4-58 GB.\033[0m"; exit 1; }
safe_log -e "\033[1mBackup verified: $EMUMMC_SIZE_MB MB\033[0m\n"

# Step 3: Restore emuMMC RAW partition
safe_log -e "\033[1m=== Step 3/4: Restore emuMMC RAW Partition ===\033[0m"
safe_log -e "\033[1mWARNING: $DEST_SD will be erased!\033[0m"
safe_log -e "\033[1mType 'YES' to continue:\033[0m"
read -r CONFIRM
CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
[ "$CONFIRM" != "yes" ] && { safe_log "Aborted."; exit 1; }

# Wipe target SD card
safe_log -e "\033[1mWiping target SD...\033[0m"
echo "Device state before wipe:" >>"$LOGFILE"
lsblk -o NAME,SIZE,MOUNTPOINT >>"$LOGFILE" 2>&1
sudo lsof /dev/sda* >>"$LOGFILE" 2>&1
sudo fuser -m /dev/sda* >>"$LOGFILE" 2>&1
sudo dd if=/dev/zero of="$DEST_SD" bs=512 count=2048 status=none 2>>"$LOGFILE" || {
    safe_log -e "\033[1mError: Cannot wipe $DEST_SD.\033[0m"
    safe_log "Ensure SD is not in use or write-protected."
    echo "Processes holding /dev/sda:" >>"$LOGFILE"
    sudo lsof /dev/sda* >>"$LOGFILE" 2>&1
    sudo fuser -m /dev/sda* >>"$LOGFILE" 2>&1
    exit 1
}
sync
for i in {1..3}; do
    sudo partprobe "$DEST_SD" >>"$LOGFILE" 2>&1 && { echo "Updated partition table on try $i" >>"$LOGFILE"; break; }
    safe_log -e "\033[1mWarning: Failed to update partition table (try $i/3), retrying...\033[0m"
    echo "Checking processes holding $DEST_SD:" >>"$LOGFILE"
    sudo lsof /dev/sda* >>"$LOGFILE" 2>&1
    sudo fuser -m /dev/sda* >>"$LOGFILE" 2>&1
    sleep 1
done
sudo partprobe "$DEST_SD" >>"$LOGFILE" 2>&1 || safe_log -e "\033[1mWarning: Partition table update failed, proceeding.\033[0m"
sync

# Create partition table
safe_log -e "\033[1mCreating partitions...\033[0m"
echo "Device state before parted:" >>"$LOGFILE"
lsblk -o NAME,SIZE,MOUNTPOINT >>"$LOGFILE" 2>&1
for i in {1..3}; do
    sudo parted -s "$DEST_SD" mklabel msdos >>"$LOGFILE" 2>&1 && { echo "Created MBR table on try $i" >>"$LOGFILE"; break; }
    safe_log -e "\033[1mWarning: Failed to create MBR table on $DEST_SD (try $i/3), retrying...\033[0m"
    echo "Checking processes holding $DEST_SD:" >>"$LOGFILE"
    sudo lsof /dev/sda* >>"$LOGFILE" 2>&1
    sudo fuser -m /dev/sda* >>"$LOGFILE" 2>&1
    sync
    sleep 1
done
sudo parted -s "$DEST_SD" mklabel msdos >>"$LOGFILE" 2>&1 || {
    safe_log -e "\033[1mError: Cannot create MBR table on $DEST_SD.\033[0m"
    safe_log "Possible causes:\n  - SD in use (check 'sudo lsof $DEST_SD' or 'sudo fuser -m $DEST_SD').\n  - SD write-protected or faulty.\n  - Kernel partition table not updated (reinsert SD or reboot)."
    echo "Processes holding $DEST_SD:" >>"$LOGFILE"
    sudo lsof /dev/sda* >>"$LOGFILE" 2>&1
    sudo fuser -m /dev/sda* >>"$LOGFILE" 2>&1
    exit 1
}

# Calculate partition layout
DISK_SIZE_SECTORS=$(parted -s "$DEST_SD" unit s print | grep "Disk $DEST_SD" | awk '{print $3}' | grep -oE '[0-9]+')
[ -z "$DISK_SIZE_SECTORS" ] && { DISK_SIZE_SECTORS=$(sudo blockdev --getsz "$DEST_SD"); [ -z "$DISK_SIZE_SECTORS" ] && { safe_log -e "\033[1mError: Cannot get disk size.\033[0m"; exit 1; }; }
RAW_SIZE_SECTORS=$((EMUMMC_SIZE / 512))
[ $((RAW_SIZE_SECTORS % 2)) -ne 0 ] && RAW_SIZE_SECTORS=$((RAW_SIZE_SECTORS + 1))
AU_ALIGN_SECTORS=32768
PADDING_SECTORS=2048
RAW_END_SECTOR=$((DISK_SIZE_SECTORS - PADDING_SECTORS))
RAW_START_SECTOR=$((RAW_END_SECTOR - RAW_SIZE_SECTORS + 1))
FAT_START_SECTOR=$AU_ALIGN_SECTORS
FAT_END_SECTOR=$((RAW_START_SECTOR - 1))
FAT_SIZE_SECTORS=$((FAT_END_SECTOR - FAT_START_SECTOR + 1))

# Validate partition boundaries
FAT_SIZE_MB=$((FAT_SIZE_SECTORS * 512 / 1024 / 1024))
[ "$FAT_SIZE_MB" -lt 4096 ] && { safe_log -e "\033[1mError: FAT32 partition too small ($FAT_SIZE_MB MB, need 4096 MB).\033[0m"; exit 1; }
[ "$RAW_START_SECTOR" -le "$FAT_END_SECTOR" ] || [ "$RAW_START_SECTOR" -le 0 ] && { safe_log -e "\033[1mError: Invalid RAW partition start ($RAW_START_SECTOR).\033[0m"; exit 1; }
[ "$RAW_END_SECTOR" -gt "$DISK_SIZE_SECTORS" ] && { safe_log -e "\033[1mError: RAW partition end ($RAW_END_SECTOR) exceeds disk ($DISK_SIZE_SECTORS).\033[0m"; exit 1; }

# Create partitions
sudo parted -s "$DEST_SD" unit s mkpart primary fat32 "$FAT_START_SECTOR" "$FAT_END_SECTOR" >>"$LOGFILE" 2>&1 || { safe_log -e "\033[1mError: Cannot create FAT32 partition.\033[0m"; exit 1; }
sudo parted -s "$DEST_SD" set 1 lba on >>"$LOGFILE" 2>&1 || safe_log -e "\033[1mWarning: Failed to set lba flag, proceeding.\033[0m"
sudo parted -s "$DEST_SD" unit s mkpart primary "$RAW_START_SECTOR" "$RAW_END_SECTOR" >>"$LOGFILE" 2>&1 || { safe_log -e "\033[1mError: Cannot create RAW partition.\033[0m"; exit 1; }
sudo sfdisk --part-type "$DEST_SD" 2 E0 >>"$LOGFILE" 2>&1 || safe_log -e "\033[1mWarning: Failed to set type 0xE0, proceeding.\033[0m"
sudo partprobe "$DEST_SD" >>"$LOGFILE" 2>&1 || safe_log -e "\033[1mWarning: Partition table update failed, proceeding.\033[0m"
sync
sleep 1

# Format FAT32 partition
safe_log -e "\033[1mFormatting FAT32...\033[0m"
DEST_FAT_PART="/dev/${DEST_SD##*/}1"
sudo mkfs.vfat -F 32 -s 128 -R 3318 -n "SWITCH SD" "$DEST_FAT_PART" >>"$LOGFILE" 2>&1 || { safe_log -e "\033[1mError: Cannot format $DEST_FAT_PART.\033[0m"; exit 1; }
safe_log -e "\033[1mFormatted $DEST_FAT_PART as FAT32\033[0m"

# Verify FAT32 formatting
CLUSTER_SIZE=$(sudo fsck.vfat -v "$DEST_FAT_PART" 2>>"$LOGFILE" | grep "bytes per cluster" | awk '{print $1}')
[ "$CLUSTER_SIZE" != "65536" ] && { safe_log -e "\033[1mError: FAT32 cluster size $CLUSTER_SIZE bytes, expected 65536.\033[0m"; exit 1; }

# Restore RAW partition
safe_log -e "\033[1mWARNING: Do not remove target SD until 'emuMMC restored' appears.\033[0m"
safe_log -e "\033[1mRestoring emuMMC (~$EMUMMC_SIZE_MB MB)...\033[0m\033[?25l"
DEST_RAW_PART="/dev/${DEST_SD##*/}2"
[ ! -f "$BACKUP_FILE" ] && { safe_log -e "\033[1mError: No emuMMC backup in $BACKUP_DIR.\033[0m"; exit 1; }
sudo dd if="$BACKUP_FILE" of=/dev/null bs=512 count=1 status=none 2>/dev/null || { safe_log -e "\033[1mError: Backup $BACKUP_FILE unreadable or corrupted.\033[0m"; exit 1; }
DEST_RAW_SIZE=$(blockdev --getsize64 "$DEST_RAW_PART")
DEST_RAW_SIZE_MB=$((DEST_RAW_SIZE / 1024 / 1024))
[ "$EMUMMC_SIZE_MB" -gt "$DEST_RAW_SIZE_MB" ] && { safe_log -e "\033[1mError: emuMMC ($EMUMMC_SIZE_MB MB) larger than RAW ($DEST_RAW_SIZE_MB MB).\033[0m"; exit 1; }

if command -v pv >/dev/null 2>&1 && tty >/dev/null 2>&1; then
    sudo pv -s "$EMUMMC_SIZE" -F "%t %b %r %p %e" -f -i 0.5 "$BACKUP_FILE" 2> >(tee -a "$LOGFILE" >/dev/tty) | sudo dd of="$DEST_RAW_PART" bs=4M 2>>"$LOGFILE"; echo -ne "\033[?25h"
    DD_STATUS=$?
else
    safe_log -e "\033[1mWarning: pv unavailable or no TTY, using dd...\033[0m"
    sudo dd if="$BACKUP_FILE" of="$DEST_RAW_PART" bs=4M status=progress 2>&1 | tee -a "$LOGFILE"
    DD_STATUS=$?
fi
sync
sleep 5
[ $DD_STATUS -ne 0 ] && { safe_log -e "\033[1mError: emuMMC restore failed. See $LOGFILE.\033[0m"; exit 1; }
safe_log -e "\033[1memuMMC restored\033[0m"

# Step 4: Copy FAT32 content
safe_log -e "\033[1m=== Step 4/4: Copy FAT32 Content ===\033[0m"
SOURCE_MOUNT="/media/$SUDO_USER/source_fat32"
DEST_MOUNT="/media/$SUDO_USER/dest_fat32"

# Function to check and use existing mount
check_mount() {
    local PART="$1" MNT="$2" READONLY="$3" DESC="$4"
    EXISTING_MOUNT=$(findmnt -n -o TARGET --source "$PART" 2>/dev/null)
    if [ -n "$EXISTING_MOUNT" ]; then
        if [ "$EXISTING_MOUNT" = "$MNT" ]; then
            if [ "$READONLY" = "yes" ]; then
                MOUNT_OPTS=$(findmnt -n -o OPTIONS --source "$PART")
                [[ "$MOUNT_OPTS" =~ ro ]] || { sudo mount -o remount,ro "$MNT" >>"$LOGFILE" 2>&1 || { safe_log -e "\033[1mError: Cannot remount $PART read-only at $MNT.\033[0m"; return 1; }; }
            fi
            return 0
        else
            sudo umount "$EXISTING_MOUNT" 2>>"$LOGFILE" || { safe_log -e "\033[1mError: Cannot unmount $PART from $EXISTING_MOUNT.\033[0m"; return 1; }
        fi
    fi
    safe_log -e "\033[1mMounting $DESC...\033[0m"
    sudo mkdir -p "$MNT" || { safe_log -e "\033[1mError: Cannot create $MNT.\033[0m"; return 1; }
    MOUNT_CMD="sudo mount"
    [ "$READONLY" = "yes" ] && MOUNT_CMD="$MOUNT_CMD -o ro"
    $MOUNT_CMD "$PART" "$MNT" >>"$LOGFILE" 2>&1 || { safe_log -e "\033[1mError: Cannot mount $PART at $MNT.\033[0m"; sudo rmdir "$MNT" 2>/dev/null; return 1; }
    safe_log -e "\033[1mMounted $DESC\033[0m"
    return 0
}

# Mount partitions
check_mount "$SOURCE_FAT_PART" "$SOURCE_MOUNT" "yes" "source FAT32 partition" || { sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; safe_log -e "\033[1mError: Cannot mount source FAT32.\033[0m"; exit 1; }
check_mount "$DEST_FAT_PART" "$DEST_MOUNT" "no" "destination FAT32 partition" || { sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; safe_log -e "\033[1mError: Cannot mount destination FAT32.\033[0m"; exit 1; }
mountpoint -q "$SOURCE_MOUNT" && mountpoint -q "$DEST_MOUNT" || { safe_log -e "\033[1mError: Invalid mount points.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
[ ! -d "$SOURCE_MOUNT/Nintendo" ] && { safe_log -e "\033[1mError: Source FAT32 empty or missing Nintendo folder.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }

TEST_FILE="$DEST_MOUNT/.nx_migrator_test"
sudo touch "$TEST_FILE" 2>>"$LOGFILE" || { safe_log -e "\033[1mError: $DEST_MOUNT not writable.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
sudo rm -f "$TEST_FILE"

TOTAL_SIZE=$(sudo du -sb --block-size=1 "$SOURCE_MOUNT" 2>>"$LOGFILE" | awk '{print $1}' || echo 0)
[ -z "$TOTAL_SIZE" ] || [ "$TOTAL_SIZE" -eq 0 ] && { safe_log -e "\033[1mError: Cannot estimate source size.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
TOTAL_SIZE_GB=$(echo "scale=1; $TOTAL_SIZE / 1024 / 1024 / 1024" | bc)
TOTAL_FILES=$(find "$SOURCE_MOUNT" -type f | wc -l)
safe_log -e "\033[1mCopying ~$TOTAL_SIZE_GB GB (~$TOTAL_FILES files)...\033[0m"

# Check if copy is needed
SOURCE_FILE_COUNT=$(find "$SOURCE_MOUNT" -type f | wc -l)
DEST_FILE_COUNT=$(find "$DEST_MOUNT" -type f | wc -l)
FORCE="${FORCE:-0}"
if [ "$FORCE" != "1" ] && [ "$SOURCE_FILE_COUNT" -eq "$DEST_FILE_COUNT" ]; then
    SOURCE_CHECKSUM=$(find "$SOURCE_MOUNT" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}')
    DEST_CHECKSUM=$(find "$DEST_MOUNT" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}')
    if [ "$SOURCE_CHECKSUM" = "$DEST_CHECKSUM" ]; then
        safe_log -e "\033[1mNo copy needed (source/destination synced).\033[0m"
        [ "$DEST_FILE_COUNT" -lt "$SOURCE_FILE_COUNT" ] && { safe_log -e "\033[1mError: Destination has fewer files ($DEST_FILE_COUNT) than source ($SOURCE_FILE_COUNT).\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
        safe_log -e "\033[1mVerified: $DEST_FILE_COUNT files.\033[0m"
        sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>>"$LOGFILE" || { safe_log -e "\033[1mWarning: Unmount failed. Lazy unmounting...\033[0m"; sudo umount -l "$SOURCE_MOUNT" "$DEST_MOUNT" 2>>"$LOGFILE"; }
        sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null
        safe_log -e "\033[1mFAT32 copy skipped (synced).\033[0m"
    else
        [ "$FORCE" = "1" ] && { safe_log -e "\033[1mFORCE=1: Clearing $DEST_MOUNT...\033[0m"; sudo rm -rf "$DEST_MOUNT"/* 2>>"$LOGFILE"; }
        safe_log -e "\033[1mCopying...\033[0m\033[?25l"
        sudo tar -C "$SOURCE_MOUNT" -cf - . | pv -s "$TOTAL_SIZE" -F "%t %b %r %p %e" -f -i 0.5 2> >(tee -a "$LOGFILE" >/dev/tty) | sudo tar -C "$DEST_MOUNT" -xf - 2>>"$LOGFILE"; echo -ne "\033[?25h"
        COPY_STATUS=$?
        [ $COPY_STATUS -ne 0 ] && { safe_log -e "\033[1mError: Copy failed (status $COPY_STATUS). See $LOGFILE.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
        SOURCE_FILE_COUNT=$(find "$SOURCE_MOUNT" -type f | wc -l)
        DEST_FILE_COUNT=$(find "$DEST_MOUNT" -type f | wc -l)
        [ "$DEST_FILE_COUNT" -lt "$SOURCE_FILE_COUNT" ] && { safe_log -e "\033[1mError: Incomplete copy. Expected $SOURCE_FILE_COUNT files, found $DEST_FILE_COUNT.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
        safe_log -e "\033[1mVerified: $DEST_FILE_COUNT files copied.\033[0m"
        sync
        sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>>"$LOGFILE" || { safe_log -e "\033[1mWarning: Unmount failed. Lazy unmounting...\033[0m"; sudo umount -l "$SOURCE_MOUNT" "$DEST_MOUNT" 2>>"$LOGFILE"; }
        sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null
        safe_log -e "\033[1mFAT32 content copied.\033[0m"
    fi
else
    [ "$FORCE" = "1" ] && { safe_log -e "\033[1mFORCE=1: Clearing $DEST_MOUNT...\033[0m"; sudo rm -rf "$DEST_MOUNT"/* 2>>"$LOGFILE"; }
    safe_log -e "\033[1mCopying...\033[0m\033[?25l"
    sudo tar -C "$SOURCE_MOUNT" -cf - . | pv -s "$TOTAL_SIZE" -F "%t %b %r %p %e" -f -i 0.5 2> >(tee -a "$LOGFILE" >/dev/tty) | sudo tar -C "$DEST_MOUNT" -xf - 2>>"$LOGFILE"; echo -ne "\033[?25h"
    COPY_STATUS=$?
    [ $COPY_STATUS -ne 0 ] && { safe_log -e "\033[1mError: Copy failed (status $COPY_STATUS). See $LOGFILE.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
    SOURCE_FILE_COUNT=$(find "$SOURCE_MOUNT" -type f | wc -l)
    DEST_FILE_COUNT=$(find "$DEST_MOUNT" -type f | wc -l)
    [ "$DEST_FILE_COUNT" -lt "$SOURCE_FILE_COUNT" ] && { safe_log -e "\033[1mError: Incomplete copy. Expected $SOURCE_FILE_COUNT files, found $DEST_FILE_COUNT.\033[0m"; sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null; exit 1; }
    safe_log -e "\033[1mVerified: $DEST_FILE_COUNT files copied.\033[0m"
    sync
    sudo umount "$SOURCE_MOUNT" "$DEST_MOUNT" 2>>"$LOGFILE" || { safe_log -e "\033[1mWarning: Unmount failed. Lazy unmounting...\033[0m"; sudo umount -l "$SOURCE_MOUNT" "$DEST_MOUNT" 2>>"$LOGFILE"; }
    sudo rmdir "$SOURCE_MOUNT" "$DEST_MOUNT" 2>/dev/null
    safe_log -e "\033[1mFAT32 content copied.\033[0m"
fi

# Cleanup
safe_log -e "\033[1m=== Cleanup ===\033[0m"
safe_log -e "\033[1mMigration done. Delete emuMMC backup in $BACKUP_DIR? (yes/no)\033[0m"
read -r DELETE_BACKUPS
DELETE_BACKUPS=$(echo "$DELETE_BACKUPS" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
if [ "$DELETE_BACKUPS" = "yes" ]; then
    safe_log "Backup deleted."
    sudo rm -rf "$BACKUP_DIR" || safe_log -e "\033[1mWarning: Cannot delete $BACKUP_DIR.\033[0m"
else
    safe_log -e "\033[1mBackup kept in $BACKUP_DIR.\033[0m"
fi

# Completion
safe_log -e "\033[1m=== Migration Complete! ===\033[0m"
safe_log -e "\033[1mInsert new SD ($DEST_SD) into Switch.\033[0m"
safe_log "In Hekate: Home > emuMMC > Migrate emuMMC > Fix RAW\n"
safe_log "Then go to Tools > Arch Bit > Fix Archive Bit"
safe_log -e "\n\033[1mShare feedback!\033[0m"
safe_log "Report issues or suggestions."
exit 0