#!/bin/bash
set -e

# Default Display
DISPLAY_NUM=${1:-5}
PORT=$((8080 + DISPLAY_NUM))

echo "Starting Vimp on Broadway Display :$DISPLAY_NUM (http://localhost:$PORT)"

# Ensure gtk4-broadwayd is running
if ! pgrep -x "gtk4-broadwayd" > /dev/null; then
    echo "Starting gtk4-broadwayd..."
    gtk4-broadwayd :$DISPLAY_NUM &
    sleep 1
else
    echo "gtk4-broadwayd already running."
fi

# Run Vimp
export GDK_BACKEND=broadway
export BROADWAY_DISPLAY=:$DISPLAY_NUM

# Build and run
zig build run
