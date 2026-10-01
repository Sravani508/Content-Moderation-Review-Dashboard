#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Offensive Message Detection System — full startup
#  Run:  bash start.sh
# ─────────────────────────────────────────────────────────────────────────────
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Paths installed in the previous setup
JAVA_HOME="$HOME/jdk17"
MAVEN="$HOME/maven/bin/mvn"
MONGO="$HOME/mongodb/bin/mongod"
MONGO_DATA="$HOME/mongodb/data"
MONGO_LOG="$HOME/mongodb/log/mongod.log"

export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
BOLD="\033[1m"
RESET="\033[0m"

ok()   { echo -e "${GREEN}${BOLD}[OK]${RESET}  $1"; }
info() { echo -e "${YELLOW}${BOLD}[..] ${RESET} $1"; }
fail() { echo -e "${RED}${BOLD}[ERR]${RESET} $1"; exit 1; }

# ── kill any previous instance ────────────────────────────────────────────────
info "Stopping any previous instances..."
pkill -f "offensive-message-detector.*\.jar" 2>/dev/null || true
pkill -f "python.*app.py"                    2>/dev/null || true
sleep 1

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}   Offensive Message Detection System — Startup     ${RESET}"
echo -e "${BOLD}════════════════════════════════════════════════════${RESET}"
echo ""

# ── 1. MongoDB ────────────────────────────────────────────────────────────────
info "Starting MongoDB..."
mkdir -p "$MONGO_DATA" "$(dirname "$MONGO_LOG")"

if pgrep -x mongod > /dev/null 2>&1; then
    ok "MongoDB already running"
else
    "$MONGO" --dbpath "$MONGO_DATA" \
             --logpath "$MONGO_LOG" \
             --port 27017 \
             --fork
    sleep 2
    ok "MongoDB started  (port 27017)"
fi

# ── 2. Python ML service ──────────────────────────────────────────────────────
info "Setting up Python ML service..."
cd "$ROOT/python-ml-service"

if [ ! -d ".venv" ]; then
    info "Creating Python virtual environment..."
    python3 -m venv .venv
    .venv/bin/pip install --quiet -r requirements.txt
    ok "Python dependencies installed"
fi

if [ ! -f "model/classifier.pkl" ]; then
    info "Training classifier (first run only)..."
    .venv/bin/python -c "
import sys; sys.path.insert(0,'.')
from model.trainer import train_and_save
train_and_save()
"
    ok "Model trained and saved"
fi

info "Starting Python ML service..."
ML_PORT=5001 MONGO_URI=mongodb://localhost:27017/ \
    .venv/bin/python app.py > /tmp/ml_service.log 2>&1 &
echo $! > /tmp/ml.pid

# wait for it
for i in $(seq 1 40); do
    if curl -s http://localhost:5001/health | grep -q "ok"; then
        ok "ML service running  (port 5001)"
        break
    fi
    sleep 1
    if [ $i -eq 40 ]; then
        echo "ML service log:"; cat /tmp/ml_service.log
        fail "ML service failed to start"
    fi
done

# ── 3. Java Spring Boot ───────────────────────────────────────────────────────
info "Building Java backend (may take ~30 s first time)..."
cd "$ROOT/java-backend"

JAR="$ROOT/java-backend/target/offensive-message-detector-1.0.0.jar"

if [ ! -f "$JAR" ]; then
    "$MAVEN" package -DskipTests -q || fail "Maven build failed"
    ok "JAR built"
else
    ok "JAR already built (skipping compile)"
fi

info "Starting Java Spring Boot backend..."
nohup java -jar "$JAR" > /tmp/java_backend.log 2>&1 &
echo $! > /tmp/java.pid

# wait for it
for i in $(seq 1 30); do
    if curl -s http://localhost:8080/api/health | grep -q "UP"; then
        ok "Java backend running  (port 8080)"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        echo "Java log tail:"; tail -20 /tmp/java_backend.log
        fail "Java backend failed to start"
    fi
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ✅  All services are running!${RESET}"
echo -e "${BOLD}════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Dashboard  →${RESET}  Open in browser:"
echo -e "             file://$ROOT/dashboard.html"
echo ""
echo -e "  ${BOLD}Java API   →${RESET}  http://localhost:8080/api/health"
echo -e "  ${BOLD}ML Service →${RESET}  http://localhost:5001/health"
echo -e "  ${BOLD}MongoDB    →${RESET}  mongodb://localhost:27017/offensive_detector"
echo ""
echo -e "  ${YELLOW}To stop everything:  bash $ROOT/stop.sh${RESET}"
echo ""

# Open browser automatically if possible
if command -v xdg-open &>/dev/null; then
    xdg-open "file://$ROOT/dashboard.html" 2>/dev/null &
fi
