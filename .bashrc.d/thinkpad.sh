# Lenovo BIOS Downloader, Patcher & Auto-Renamer (v7 - Legacy/UTF16 Fixes)
prep_thinkpad_bios() {
    if [ -z "$1" ]; then
        echo "Usage: prep_thinkpad_bios <iso_url> [nodc]"
        echo "Example: prep_thinkpad_bios https://download.lenovo.com/.../n1eur57w.iso nodc"
        return 1
    fi

    local url="$1"
    local bypass_battery="$2"
    local iso_file="temp_bios.iso"
    local img_file="temp_bios.img"
    local mount_dir="/tmp/bios_mnt_$$"
    
    # Grab the exact ID from the URL as our unbreakable fallback (e.g., 8DUJ31US)
    local fallback_id=$(basename "$url" .iso | tr '[:lower:]' '[:upper:]')

    echo "[*] Downloading BIOS ISO..."
    wget -q --show-progress -O "$iso_file" "$url" || { echo "Download failed!"; return 1; }

    if ! command -v geteltorito &> /dev/null; then
        echo "[!] Error: 'geteltorito' is not installed."
        return 1
    fi

    echo "[*] Extracting bootable .img from ISO..."
    geteltorito -o "$img_file" "$iso_file" >/dev/null 2>&1 || { echo "Extraction failed!"; return 1; }

    echo "[*] Mapping partitions and mounting image..."
    mkdir -p "$mount_dir"
    
    local loop_dev=$(sudo losetup -Pf --show "$img_file")
    
    if [ -b "${loop_dev}p1" ]; then
        sudo mount "${loop_dev}p1" "$mount_dir"
    else
        sudo mount "$loop_dev" "$mount_dir"
    fi

    # --- DYNAMIC RENAMING LOGIC ---
    local final_name=""
    local readme_file=$(sudo find "$mount_dir" -maxdepth 3 -iname "readme.txt" | head -n 1)
    
    if [ -n "$readme_file" ]; then
        # Using 'strings' to bypass UTF-16 encoding issues on legacy READMEs
        local model=$(sudo strings "$readme_file" | grep -m 1 -i "ThinkPad" | sed -E 's/.*(ThinkPad[^a-zA-Z0-9]*[a-zA-Z0-9 -]+).*/\1/' | tr -d '\r' | xargs)
        local version=$(sudo strings "$readme_file" | grep -m 1 -i "Version" | tr -d '\r' | sed -E 's/.*Version[^0-9]*([0-9]+\.[0-9]+).*/\1/')
        
        # Clean up trademark symbols
        model="${model//(R)/}"
        model="${model//(TM)/}"
        model=$(echo "$model" | xargs)

        if [ -n "$model" ] && [[ "$model" != "ThinkPad" ]]; then
            final_name="${model// /_}"
            [ -n "$version" ] && final_name="${final_name}_v${version}"
            echo "[*] Detected Firmware from README: $final_name"
        fi
    fi

    # If the README parsing failed, use the unbreakable URL fallback
    if [ -z "$final_name" ]; then
        final_name="ThinkPad_BIOS_${fallback_id}"
        echo "[*] README metadata unreadable. Using ID from URL: $fallback_id"
    fi

    # --- UNIVERSAL BATTERY BYPASS PATCHING ---
    if [ "$bypass_battery" = "nodc" ]; then
        local nodc_file=$(sudo find "$mount_dir" -maxdepth 3 -iname "NoDCCheck_BootX64.efi" | head -n 1)
        local boot_efi=$(sudo find "$mount_dir" -maxdepth 3 -iname "BootX64.efi" | head -n 1)

        if [ -n "$nodc_file" ] && [ -n "$boot_efi" ]; then
            sudo cp "$nodc_file" "$boot_efi"
            echo "[*] Success: Applied modern UEFI bypass (Patched BootX64.efi)."
            
        elif sudo find "$mount_dir" -maxdepth 2 -iname "*.bat" | grep -q "."; then
            echo "[*] Legacy DOS image detected. Injecting '/sd' skip-battery flag..."
            sudo find "$mount_dir" -maxdepth 2 -iname "*.bat" -exec sudo sed -i -E 's/(dosflash(\.exe)?)/\1 \/sd/Ig' {} +
            echo "[*] Success: DOS bypass applied to batch scripts."
            
        else
            echo "[!] Warning: Could not detect UEFI or known DOS battery bypass methods."
        fi
    fi

    # Sync, unmount, and detach the loop device
    sync
    sudo umount "$mount_dir" 2>/dev/null
    sudo losetup -d "$loop_dev"
    rmdir "$mount_dir"

    # Rename the files
    mv "$iso_file" "${final_name}.iso"
    mv "$img_file" "${final_name}.img"

    echo "==========================================="
    echo "[*] Done! Your files are ready:"
    echo "    ISO: ${final_name}.iso"
    echo "    IMG: ${final_name}.img"
    echo "    Flash to your USB with: sudo cp -vi ${final_name}.img /dev/sdX"
}

# Laptop battery check
bathealth() {
    for bat in $(upower -e | grep BAT); do
        upower -i "$bat" | awk '
            /native-path/ {name=$2}
            /^ *energy-full:/ {ef=$2; sub(",", ".", ef)}
            /^ *energy-full-design:/ {efd=$2; sub(",", ".", efd)}
            END {
                printf "%s Health: %.2f%%\n", name, (ef/efd)*100
            }
        '
    done
}
