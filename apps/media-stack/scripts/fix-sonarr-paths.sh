#!/bin/sh
# RDT-Client Path Fixer for Sonarr v4
# This script wraps single-file downloads into folders to fix the 'Trailing Slash' bug.

TARGET_DIR="/mnt/media/downloads/tv"

cd "$TARGET_DIR" || exit

for file in *.mkv *.mp4 *.avi; do
    if [ -f "$file" ]; then
        folder_name="${file}"
        echo "Fixing single file: $file -> wrap in folder: $folder_name"
        mkdir -p "$folder_name"
        mv "$file" "$folder_name/"
    fi
done
