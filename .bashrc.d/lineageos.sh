flash-kernel() {
    [[ -z "$1" ]] && { echo "Usage: flash-kernel <zip>"; return 1; }

    echo "--> Rebooting to Recovery..."
    adb reboot recovery

    echo "--> Waiting for you to select 'Apply from ADB' on the tablet..."
    # The 'sideload' state only appears once you tap the menu option
    while [[ $(adb devices | grep -c "sideload") -eq 0 ]]; do
        sleep 1
    done

    echo "--> Connection detected! Sideloading $1..."
    adb sideload "$1"
}

flash-keyboard() {
    [[ -z "$1" ]] && { echo "Usage: flash-keyboard <path/to/kl>"; return 1; }

    # This extracts 'Vendor_04e8_Product_a035.kl' from the full path
    local filename=$(basename "$1")

    echo "--> Rebooting adb to root..."
    adb root

    adb shell "mkdir -p /data/system/devices/keylayout/ && chown system:system /data/system/devices/keylayout/"

    echo "--> Pushing keyboard layout..."
    # We push the source path ($1) to the clean destination filename ($filename)
    adb push "$1" /data/system/devices/keylayout/"$filename"

    adb shell "chmod 644 /data/system/devices/keylayout/$filename"
    adb shell "chown system:system /data/system/devices/keylayout/$filename"

    echo "--> Applying SELinux context..."
    adb shell "chcon u:object_r:system_data_file:s0 /data/system/devices/keylayout/$filename"

    echo "--> Restarting Android Framework..."
    adb shell "stop && start"

    echo "--> Verification:"
    adb shell ls -lZ /data/system/devices/keylayout/"$filename"
}

reset-keyboard() {
    echo "--> Removing custom layout overrides..."
    adb root
    adb shell rm -rf /data/system/devices/keylayout/*

    echo "--> Restarting Android Framework to restore defaults..."
    adb shell "stop && start"

    echo "--> Done. Tablet is back to factory defaults."
}
