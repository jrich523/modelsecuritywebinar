#!/bin/bash
set -x

MODEL_FILE=$1
BUCKET_PATH=$2
BUCKET_MODEL_PATH="${BUCKET_PATH%/}/${MODEL_FILE#/}"

echo "Starting Guardian scan..."

# check for vars/commands

# aws, pip, guardian-client, jq

# check and build paths

if ! command -v aws; then
    echo "AWS CLI is required!"
    exit 1
fi

OUTPUT=$(pip install guardian-client==0.3.1 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ Failed to install guardian-client"
    echo "Exit code: $EXIT_CODE"
    echo "Error output: $OUTPUT"
    exit $EXIT_CODE
fi

OUTPUT=$(aws s3 cp "${MODEL_FILE}" "${BUCKET_MODEL_PATH}" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ Failed to copy to S3"
    echo "Exit code: $EXIT_CODE"
    echo "Error output: $OUTPUT"
    exit $EXIT_CODE
else
    echo "$OUTPUT"
    echo "Successfully uploaded the model"
fi



# this will put the activity stream to stderr, and store the json object return
OUTPUT=$(guardian-client --log-level debug scan --poll-interval-secs 2 "${BUCKET_MODEL_PATH}")
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ Failed to scan model!"
    echo "Error output: $OUTPUT"
    exit $EXIT_CODE
fi
echo "Result:"
echo "$OUTPUT"

#format and save comment body

RESULT=$(echo "$OUTPUT" | jq -r ".aggregate_eval_outcome")
ISSUES=$(echo "$OUTPUT" | jq -r .scan_summary.issue_counts)
COMMENT_BODY="## Protect AI Guardian Scan Results\n\n"

# Add result with emoji
if [ "$RESULT" == "PASS" ]; then
    COMMENT_BODY+="✅ **Status: PASS**\n\n"
else
    COMMENT_BODY+="❌ **Status: FAIL**\n\n"
fi

# Extract values from the ISSUES JSON
CRITICAL=$(echo "$ISSUES" | jq -r '.CRITICAL')
HIGH=$(echo "$ISSUES" | jq -r '.HIGH')
MEDIUM=$(echo "$ISSUES" | jq -r '.MEDIUM')
LOW=$(echo "$ISSUES" | jq -r '.LOW')

# Create markdown table
COMMENT_BODY+="| Severity | Count |\n"
COMMENT_BODY+="|----------|-------|\n"
COMMENT_BODY+="| 🔴 CRITICAL | $CRITICAL |\n"
COMMENT_BODY+="| 🟠 HIGH | $HIGH |\n"
COMMENT_BODY+="| 🟡 MEDIUM | $MEDIUM |\n"
COMMENT_BODY+="| 🔵 LOW | $LOW |\n"

COMMENT_BODY=$(echo -e "$COMMENT_BODY")

# Find existing comment
URL=$(gh pr view $PR_NUMBER --json comments --jq '.comments[] | select(.body | startswith("## Protect AI Guardian Scan Results")) | .url')

if [ -n "$URL" ]; then
    # Update existing comment
    gh api --method PATCH "$URL" \
      -f body="$COMMENT_BODY"
else
    # Create new comment
    gh pr comment "$PR_NUMBER" -b "$COMMENT_BODY"
fi

if [ "$RESULT" == "FAIL" ]; then
    exit 1
fi
