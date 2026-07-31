#!/usr/bin/env bash
# test_runner.sh - Linux port of test_runner.ps1. Orchestrates headless Godot
# tests. Usage:
#   ./test_runner.sh                     # syntax pre-check only
#   ./test_runner.sh test_ship_designs   # run a single test

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_PATH="$SCRIPT_DIR/Godot_v4.4.1-stable_linux.x86_64"

C_CYAN='\033[36m'
C_YELLOW='\033[33m'
C_GREEN='\033[32m'
C_RED='\033[31m'
C_RESET='\033[0m'

if [[ ! -x "$GODOT_PATH" ]]; then
    printf "${C_RED}Godot executable not found at %s${C_RESET}\n" "$GODOT_PATH" >&2
    printf "Download the 4.4.1-stable Linux build and place it there:\n" >&2
    printf "  https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip\n" >&2
    printf "Then: unzip and chmod +x the extracted binary.\n" >&2
    exit 1
fi

# shellcheck source=./import_check.sh
source "$SCRIPT_DIR/import_check.sh"
import_if_stale "$SCRIPT_DIR" "$GODOT_PATH"

printf "${C_CYAN}==========================================${C_RESET}\n"
printf "${C_CYAN} Running Automated Tests for Project Deep Space ${C_RESET}\n"
printf "${C_CYAN}==========================================${C_RESET}\n"

TEST_NAME="${1:-}"

if [[ -z "$TEST_NAME" ]]; then
    # Syntax validation deliberately skipped on Linux for the same reason the
    # PowerShell runner skips it on the console binary: --headless --check-only
    # reports false parse errors on autoload identifiers (e.g. DebugSettings).
    # See CLAUDE.md's "Headless gotchas". Validate a script by running a test
    # that loads it instead.
    printf "\n${C_GREEN}[1] No specific test provided. Orchestration ready.${C_RESET}\n"
    exit 0
fi

printf "\n${C_YELLOW}[1] Running Test Scenario: %s${C_RESET}\n" "$TEST_NAME"

LOG_DIR="$SCRIPT_DIR/test_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$TEST_NAME.log"
ERR_FILE="$LOG_DIR/$TEST_NAME.err.log"
rm -f "$LOG_FILE" "$ERR_FILE"

# --fixed-fps 60 DECOUPLES the loop from real time. Headless Godot otherwise
# SLEEPS to hold 60Hz, so a frame-capped sim test runs in real time (e.g.
# test_missile_ai's scenarios = ~32s wall-clock) despite doing milliseconds of
# work -- and real-time sleep does NOT parallelize, so under N-way contention
# the loop can't hold 60Hz and wall-clock slips toward the cap (that was the
# "flaky timeout", never CPU-load). --fixed-fps runs the same fixed 1/60 delta
# with identical frame counts (deterministic) but no sleep -> ~17x faster.
# Determinism also needs main.gd's seed() (the global RNG -- sensor noise,
# missile jink -- was the real flakiness source; see _run_test).
#
# Hard per-test timeout stays as a backstop for a genuinely hung test.
TEST_TIMEOUT_SEC=600

START_TIME=$(date +%s.%N)
# `timeout --kill-after=5` sends SIGTERM at the cap and follows with SIGKILL if
# Godot doesn't exit within 5s -- ensures stdout/stderr pipes close so the read
# below unblocks. Exit code 124 = timed out and was killed by timeout(1).
set +e
timeout --kill-after=5 "$TEST_TIMEOUT_SEC" \
    "$GODOT_PATH" --path "$SCRIPT_DIR" --headless --fixed-fps 60 --run-test "$TEST_NAME" \
    >"$LOG_FILE" 2>"$ERR_FILE"
EXIT_CODE=$?
set -e
END_TIME=$(date +%s.%N)
LATENCY=$(awk -v s="$START_TIME" -v e="$END_TIME" 'BEGIN{printf "%.2f", e-s}')

if [[ "$EXIT_CODE" -eq 124 ]]; then
    printf "\n  ${C_RED}>>> [TEST FAILED] %s (TIMEOUT -- killed after %ss) <<<${C_RESET}\n" "$TEST_NAME" "$TEST_TIMEOUT_SEC"
    printf "Test did not exit within the time budget -- treated as a hang. Partial log:\n"
    cat "$LOG_FILE"
    if [[ -s "$ERR_FILE" ]]; then
        printf "Error Output:\n"
        cat "$ERR_FILE"
    fi
    exit 1
fi

if [[ "$EXIT_CODE" -eq 0 ]] && grep -q '\[TEST PASSED\]' "$LOG_FILE"; then
    printf "\n  ${C_GREEN}>>> [TEST PASSED] %s (%ss) <<<${C_RESET}\n" "$TEST_NAME" "$LATENCY"
    exit 0
else
    printf "\n  ${C_RED}>>> [TEST FAILED] %s (%ss) <<<${C_RESET}\n" "$TEST_NAME" "$LATENCY"
    printf "Exit Code: %s\n" "$EXIT_CODE"
    printf "Log Output:\n"
    cat "$LOG_FILE"
    if [[ -s "$ERR_FILE" ]]; then
        printf "Error Output:\n"
        cat "$ERR_FILE"
    fi
    exit 1
fi
