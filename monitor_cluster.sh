#!/bin/bash

# ==============================================================================
# Slurm Watch Trigger Launcher
# Purpose: Utilizing system 'watch' for terminal render optimization.
# ==============================================================================

SNAPSHOT_SCRIPT="./cluster_snapshot.sh"

# Ensure the snapshot script exists and has execution permissions
if [ ! -f "$SNAPSHOT_SCRIPT" ]; then
    echo "[ERROR] $SNAPSHOT_SCRIPT not found!"
    exit 1
fi
chmod +x "$SNAPSHOT_SCRIPT"

echo "[INFO] Launching Slurm Monitor using native 'watch'..."
echo "[INFO] Refresh interval: 2 seconds. Press Ctrl+C to exit."
sleep 1

# --color: Preserves ANSI color highlighting from the snapshot script
# -n 2: Safely poll every 2 seconds
watch --color -n 2 "$SNAPSHOT_SCRIPT"