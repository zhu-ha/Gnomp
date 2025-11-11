#!/bin/bash

BACKUP_DIR="$HOME/gnome_backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

backup() {
    echo "Backing up GNOME settings..."

    # Export all dconf settings
    DCONF_FILE="$BACKUP_DIR/dconf_settings_$TIMESTAMP.txt"
    dconf dump / > "$DCONF_FILE"

    # Backup user extensions explicitly
    EXTENSIONS_DIR="$HOME/.local/share/gnome-shell/extensions"
    EXTENSIONS_BACKUP="$BACKUP_DIR/extensions_$TIMESTAMP"
    if [ -d "$EXTENSIONS_DIR" ]; then
        mkdir -p "$EXTENSIONS_BACKUP"
        cp -r "$EXTENSIONS_DIR"/* "$EXTENSIONS_BACKUP/"
    fi

    # Create archive with all configs + dconf + extensions
    BACKUP_FILE="$BACKUP_DIR/gnome_settings_$TIMESTAMP.tar.gz"
    tar -czf "$BACKUP_FILE" \
        "$HOME/.config" \
        "$HOME/.local/share" \
        "$HOME/.gnome" \
        "$DCONF_FILE" \
        -C "$BACKUP_DIR" "$(basename "$EXTENSIONS_BACKUP")"

    echo "Backup complete: $BACKUP_FILE"
}

restore() {
    read -rp "Enter the full path of the backup file (drag and drop supported): " BACKUP_FILE
    BACKUP_FILE="${BACKUP_FILE%\"}"
    BACKUP_FILE="${BACKUP_FILE#\"}"

    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Backup file not found."
        exit 1
    fi

    # Extract backup to a temporary directory first
    TEMP_RESTORE_DIR=$(mktemp -d)
    tar -xzf "$BACKUP_FILE" -C "$TEMP_RESTORE_DIR"

    echo "Restoring configuration files..."
    cp -r "$TEMP_RESTORE_DIR/.config/" "$HOME/.config/"
    cp -r "$TEMP_RESTORE_DIR/.local/share/" "$HOME/.local/share/"
    cp -r "$TEMP_RESTORE_DIR/.gnome/" "$HOME/.gnome/"

    # Restore dconf from the exact file in the backup
    DCONF_FILE=$(find "$TEMP_RESTORE_DIR" -type f -name "dconf_settings_*.txt" | head -1)
    if [ -f "$DCONF_FILE" ]; then
        dconf load / < "$DCONF_FILE"
        echo "dconf settings restored from $DCONF_FILE"
    fi

    # Restore extensions
    EXT_BACKUP_DIR=$(find "$TEMP_RESTORE_DIR" -type d -name "extensions_*" | head -1)
    if [ -d "$EXT_BACKUP_DIR" ]; then
        mkdir -p "$HOME/.local/share/gnome-shell/extensions"
        cp -r "$EXT_BACKUP_DIR"/* "$HOME/.local/share/gnome-shell/extensions/"
    fi

    echo "Reloading GNOME Shell extensions..."
    if command -v gnome-extensions >/dev/null 2>&1; then
        gnome-extensions reset --all
        gnome-extensions enable $(gnome-extensions list)
    fi

    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        echo "Reloading GNOME Shell via D-Bus (Wayland)..."
        gdbus call \
            --session \
            --dest org.gnome.Shell \
            --object-path /org/gnome/Shell \
            --method org.gnome.Shell.Eval "global.reexec_self()"
        echo "Extensions should now be fully applied. Log out and back in if any issues remain."
    elif [ "$XDG_SESSION_TYPE" = "x11" ]; then
        echo "Restarting GNOME Shell (X11)..."
        gnome-shell --replace & disown
    fi

    rm -rf "$TEMP_RESTORE_DIR"
    echo "Restore complete."
}

echo "Select an option:"
echo "1) Backup"
echo "2) Restore"
read -rp "Enter choice: " choice

case "$choice" in
    1) backup ;;
    2) restore ;;
    *) echo "Invalid choice"; exit 1 ;;
esac
