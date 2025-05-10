# NX Migrator

**NX Migrator** is a Bash script that automates the migration of a Nintendo Switch SD card, including its emuMMC RAW partition and FAT32 content, to a larger SD card with enhanced safety and verification. It leverages Hekate USB Tools or dual SD card readers to ensure a reliable transfer.

## Features
- **Automated Detection**: Identifies source (Hekate USB or SD card reader) and target SD cards.
- **emuMMC Backup/Restore**: Backs up the emuMMC RAW partition and restores it to the target SD.
- **FAT32 Content Copy**: Transfers all FAT32 partition content with verification.
- **Safety Checks**: Ensures sufficient disk space, validates partition sizes, and safely handles mounts/processes.
- **Progress Monitoring**: Uses `pv` for real-time progress (if available).
- **Logging**: Detailed logs for troubleshooting.
- **Error Handling**: Robust checks to prevent data corruption or loss.
- **User-Friendly**: Clear prompts and warnings to guide the user.

## Requirements
- **Operating System**: Linux (Ubuntu/Debian-based recommended).
- **Dependencies**: `parted`, `fdisk`, `dosfstools`, `util-linux`, `bc`, `gdisk`, `coreutils`, `mountpoint`, `findutils`, `psmisc`, `tar`, `pv` (optional for progress bars).
- **Hardware**:
  - Source SD card mounted via Nintendo Switch (using Hekate USB Tools in UMS mode), a single SD card reader with dual ports, or a dual SD card reader.
  - Target SD card in an SD card reader (must be larger than the source).
  - USB connection for the Switch (if using Hekate USB Tools) or a compatible SD card reader setup.
- **Permissions**: Script must be run with `sudo`.

## Installation
1. **Download the Script**:
   ```bash
   wget https://raw.githubusercontent.com/sthetix/nx-migrator/main/nx_migrator.sh
2. **Make it executable**:
   ```bash
   chmod +x nx_migrator.sh
3. **Run the script**:
   ```bash
   sudo ./nx_migrator.sh
