#!/usr/bin/env bash
# Stops all system services

GREEN="\033[92m"; BOLD="\033[1m"; RESET="\033[0m"
ok() { echo -e "${GREEN}${BOLD}[OK]${RESET}  $1"; }

echo "Stopping Offensive Message Detection System..."

pkill -f "offensive-message-detector.*\.jar" 2>/dev/null && ok "Java backend stopped"   || echo "  Java was not running"
pkill -f "python.*app.py"                    2>/dev/null && ok "ML service stopped"      || echo "  ML service was not running"

if pgrep -x mongod > /dev/null 2>&1; then
    "$HOME/mongodb/bin/mongod" --dbpath "$HOME/mongodb/data" --shutdown 2>/dev/null
    ok "MongoDB stopped"
else
    echo "  MongoDB was not running"
fi

rm -f /tmp/ml.pid /tmp/java.pid
echo ""
echo -e "${BOLD}All services stopped.${RESET}"
