#!/bin/bash

# 1. Kill any running emulator processes to release file locks
echo "Killing existing emulator processes..."
pkill -9 emulator 2>/dev/null
pkill -9 qemu-system-x86_64 2>/dev/null

# 2. Clean up stale lock files that prevent clean boots
echo "Cleaning up lock files..."
find ~/.android/avd/ -name "*.lock" -delete

# 3. Update all AVD configurations for stability
echo "Updating AVD configurations in ~/.android/avd/..."
for config in ~/.android/avd/*.avd/config.ini; do
    if [ -f "$config" ]; then
        echo "Optimizing: $config"

        # Set GPU mode to 'host' for hardware acceleration
        if grep -q "hw.gpu.mode" "$config"; then
            sed -i 's/^hw.gpu.mode=.*/hw.gpu.mode=host/' "$config"
        else
            echo "hw.gpu.mode=host" >> "$config"
        fi

        # Force Cold Boot and disable Fast Boot (snapshots)
        if grep -q "fastboot.forceColdBoot" "$config"; then
            sed -i 's/^fastboot.forceColdBoot=.*/fastboot.forceColdBoot=yes/' "$config"
        else
            echo "fastboot.forceColdBoot=yes" >> "$config"
        fi

        if grep -q "fastboot.forceFastBoot" "$config"; then
            sed -i 's/^fastboot.forceFastBoot=.*/fastboot.forceFastBoot=no/' "$config"
        else
            echo "fastboot.forceFastBoot=no" >> "$config"
        fi
    fi
done

echo "--------------------------------------------------------"
echo "Fixes applied! On the new machine, please:"
echo "1. Run this script: sh fix_emulators.sh"
echo "2. Open Android Studio Device Manager."
echo "3. Launch your emulator using 'Cold Boot Now'."
echo "--------------------------------------------------------"
