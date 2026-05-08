#!/usr/bin/env bash
# fetch_model.sh - print a resumable download command for the selected
# RWKV-7 weight file.
#
# This script does NOT run curl itself. Model weights are 1-27 GB and take
# 5-30 minutes to download, routinely longer than agent command timeouts.
# The skill hands this step off to the user so they see real progress and
# the agent does not silently get killed mid-download.
#
# Reads ~/.rwkv7-skill/state/choice.env (written during deploy Step 2) for
# MODEL_SIZE. If the target file is already present at the expected size,
# this script reports "already present" and no manual action is needed.

set -euo pipefail

STATE_DIR="${RWKV7_SKILL_STATE_DIR:-$HOME/.rwkv7-skill/state}"
mkdir -p "$STATE_DIR"
CHOICE_FILE="${RWKV7_SKILL_CHOICE:-$STATE_DIR/choice.env}"
MODELS_DIR="${RWKV7_SKILL_MODELS_DIR:-$HOME/.rwkv7-skill/models}"
HF_BASE="${RWKV7_SKILL_HF_BASE:-https://huggingface.co/BlinkDL/rwkv7-g1/resolve/main}"
CURL_CONNECT_TIMEOUT="${RWKV7_SKILL_CURL_CONNECT_TIMEOUT:-10}"
CURL_HEAD_MAX_TIME="${RWKV7_SKILL_CURL_HEAD_MAX_TIME:-60}"

if [ ! -f "$CHOICE_FILE" ]; then
    echo "ERROR: $CHOICE_FILE missing. Write ENGINE= and MODEL_SIZE= to it first (SKILL.md Step 2)." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CHOICE_FILE"
: "${MODEL_SIZE:?MODEL_SIZE not set in $CHOICE_FILE}"

# Known-good file map. The RWKV team trains fresh "data-version" variants
# (G1 → G1a → ... → G1e → G1f → ...) as they iterate on training data;
# filenames include the variant letter + release date. Pins below target
# the latest stable variant per size for the current skill snapshot.
#
# When the HF URL below 404s, a new variant has landed. Open
# https://huggingface.co/BlinkDL/rwkv7-g1/tree/main, pick the newest
# rwkv7-g1<letter>-<size>-<date>-ctx<ctxlen>.pth for each size, and update
# this case table plus references/model-catalog.md.
case "$MODEL_SIZE" in
    0.4B)  FILE="rwkv7-g1d-0.4b-20260210-ctx8192.pth"  ; EXPECT_GB=1  ; EXPECT_MB=902   ;;
    1.5B)  FILE="rwkv7-g1f-1.5b-20260419-ctx8192.pth"  ; EXPECT_GB=3  ; EXPECT_MB=3056  ;;
    2.9B)  FILE="rwkv7-g1f-2.9b-20260420-ctx8192.pth"  ; EXPECT_GB=6  ; EXPECT_MB=5897  ;;
    7.2B)  FILE="rwkv7-g1f-7.2b-20260414-ctx8192.pth"  ; EXPECT_GB=15 ; EXPECT_MB=14400 ;;
    13.3B) FILE="rwkv7-g1f-13.3b-20260415-ctx8192.pth" ; EXPECT_GB=27 ; EXPECT_MB=26541 ;;
    *) echo "ERROR: unknown MODEL_SIZE=$MODEL_SIZE" >&2; exit 2 ;;
esac

mkdir -p "$MODELS_DIR"
DEST="$MODELS_DIR/$FILE"
URL="$HF_BASE/$FILE"

file_size_mb() {
    local path="$1"
    local bytes
    if bytes="$(stat -f '%z' "$path" 2>/dev/null)"; then
        :
    elif bytes="$(stat -c '%s' "$path" 2>/dev/null)"; then
        :
    else
        echo 0
        return
    fi
    echo $((bytes / 1024 / 1024))
}

check_remote_file() {
    if [ "$HF_BASE" = "https://huggingface.co/BlinkDL/rwkv7-g1/resolve/main" ] && command -v python3 >/dev/null 2>&1; then
        python3 - "$FILE" <<'PY'
import json
import sys
import urllib.request

target = sys.argv[1]
url = "https://huggingface.co/api/models/BlinkDL/rwkv7-g1"
try:
    with urllib.request.urlopen(url, timeout=30) as response:
        data = json.load(response)
except Exception as exc:
    print(f"ERROR: failed to query Hugging Face model API: {exc}", file=sys.stderr)
    raise SystemExit(3)

files = {item.get("rfilename") for item in data.get("siblings", [])}
raise SystemExit(0 if target in files else 2)
PY
        return $?
    fi

    if curl -sfLI --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_HEAD_MAX_TIME" "$URL" >/dev/null; then
        return 0
    fi
    return $?
}

# Short-circuit: file already downloaded at (approximately) expected size.
# Lets users re-run fetch_model.sh after an interrupted session without
# re-downloading the whole thing.
if [ -f "$DEST" ]; then
    SIZE_MB="$(file_size_mb "$DEST")"
    MIN_MB=$((EXPECT_MB * 9 / 10))
    if [ "$SIZE_MB" -ge "$MIN_MB" ]; then
        echo "Already present: $DEST (${SIZE_MB} MB)"
        # Record MODEL_PATH for downstream scripts (idempotent: choice.env is
        # source'd, so later assignments win over earlier duplicates).
        echo "MODEL_PATH=$DEST" >> "$CHOICE_FILE"
        echo ""
        echo "No manual action needed. Proceed to Step 4."
        exit 0
    fi
    echo "Existing file at $DEST is truncated (${SIZE_MB} MB, expected ~${EXPECT_MB} MB)." >&2
    echo "The curl command below uses -C - to resume, so re-running it will finish the download." >&2
    echo ""
fi

# Verify the exact file exists before handing the user a 404-bound command.
# The date pin in the filename is plausible but not guaranteed once new
# variants land upstream.
if check_remote_file; then
    :
else
    CHECK_STATUS=$?
    if [ "$CHECK_STATUS" -eq 28 ]; then
        echo "ERROR: timed out while checking remote file: $URL" >&2
        echo "Retry later or increase RWKV7_SKILL_CURL_HEAD_MAX_TIME." >&2
        exit 4
    fi
    if [ "$CHECK_STATUS" -eq 3 ]; then
        echo "ERROR: remote file could not be verified: $URL" >&2
        echo "Retry later or set RWKV7_SKILL_HF_BASE to a reachable mirror." >&2
        exit 4
    fi
    echo "ERROR: remote file not found: $URL" >&2
    echo "A new variant may have landed upstream. Open" >&2
    echo "  https://huggingface.co/BlinkDL/rwkv7-g1/tree/main" >&2
    echo "pick the newest rwkv7-g1<letter>-*-<date>-ctx8192.pth for size ${MODEL_SIZE}," >&2
    echo "and update the case block in this script plus" >&2
    echo "references/model-catalog.md before re-running." >&2
    exit 3
fi

# Record MODEL_PATH up front so downstream scripts can read it once the user
# finishes the manual download.
echo "MODEL_PATH=$DEST" >> "$CHOICE_FILE"

# Print the hand-off block. The agent should display the section between
# the delimiter lines to the user verbatim, then wait for confirmation.
cat <<EOF

================================================================
HAND-OFF: long download (~${EXPECT_GB} GB, 5-30 min)
================================================================

This file is too large to download reliably through the agent command
runner. Run the following command in a SEPARATE TERMINAL:

    mkdir -p "$MODELS_DIR"
    cd "$MODELS_DIR"
    curl -L -C - --fail -o "$FILE" \\
      "$URL"

The '-C -' flag enables resume: if the connection drops, re-running the
same command picks up where it left off.

When curl exits 0, verify the file size:

    ls -lh "$DEST"

The size should be close to ${EXPECT_MB} MB (~${EXPECT_GB} GB).

After the user confirms the download is complete and size matches,
proceed to Step 4. The resolved path

    MODEL_PATH=$DEST

has already been recorded in $CHOICE_FILE for downstream scripts.
================================================================
EOF
