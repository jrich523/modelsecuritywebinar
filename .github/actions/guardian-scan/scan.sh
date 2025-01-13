#!/bin/bash

export MODEL_FILE=$1
export BUCKET_MODEL_PATH="s3://bucket/$MODEL_FILE"
export LOCAL_MODEL_PATH="${PWD}/${MODEL_FILE}"

echo "Starting Guardian scan..."

OUTPUT=$(pip install guardian-client==1.1.1 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ Failed to install guardian-client"
    echo "Exit code: $EXIT_CODE"
    echo "Error output: $OUTPUT"
    exit $EXIT_CODE
fi
echo "$LICENSE_ID" | docker login proxy.platform.protectai.com --username user --password-stdin
docker compose -f .github/actions/guardian-scan/docker-compose.yaml --project-directory "${GITHUB_WORKSPACE}" up -d
echo "initiating scan on $BUCKET_MODEL_PATH"
# this will put the activity stream to stderr, and store the json object return
OUTPUT=$(guardian-client scan --poll-interval-secs 2 "${BUCKET_MODEL_PATH}")
EXIT_CODE=$?
RESULT=$(echo "$OUTPUT" | jq -r ".aggregate_eval_outcome") || "ERROR"
if [[ $EXIT_CODE -ne 0 && "$RESULT" != "FAIL" ]]; then
    echo "❌ Failed to scan model!"
    echo "Error output: $OUTPUT"
    exit $EXIT_CODE
fi
echo "Result:"
echo "$OUTPUT"

docker compose -f .github/actions/guardian-scan/docker-compose.yaml down
#format and save comment body


ISSUES=$(echo "$OUTPUT" | jq -r .aggregate_eval_summary)
COMMENT_BODY="## Protect AI Guardian Scan Results\n\n"

# Add result with emoji
if [ "$RESULT" == "PASS" ]; then
    COMMENT_BODY+="✅ **Status: PASS**\n\n"
else
    COMMENT_BODY+="❌ **Status: FAIL**\n\n"
    echo "$OUTPUT" | jq -r '.policy_violations[] | "::error title=\(.policy_name)::\(.compliance_issues[0])"'
fi

# Extract values from the ISSUES JSON
CRITICAL=$(echo "$ISSUES" | jq -r '.critical_count')
HIGH=$(echo "$ISSUES" | jq -r '.high_count')
MEDIUM=$(echo "$ISSUES" | jq -r '.medium_count')
LOW=$(echo "$ISSUES" | jq -r '.low_count')

# Create markdown table
COMMENT_BODY+="| Severity | Count |\n"
COMMENT_BODY+="|----------|-------|\n"
COMMENT_BODY+="| 🔴 CRITICAL | $CRITICAL |\n"
COMMENT_BODY+="| 🟠 HIGH | $HIGH |\n"
COMMENT_BODY+="| 🟡 MEDIUM | $MEDIUM |\n"
COMMENT_BODY+="| 🔵 LOW | $LOW |\n"

COMMENT_BODY=$(echo -e "$COMMENT_BODY")

# Find existing comment
URL=$(gh pr view "$PR_NUMBER" --json comments --jq '.comments[] | select(.body | startswith("## Protect AI Guardian Scan Results")) | .url')

if [ -n "$URL" ]; then
    # Update existing comment
    COMMENT_ID="${URL##*-}"
    PATCH_RESULT=$(gh api --method PATCH \
      "/repos/$GITHUB_REPOSITORY/issues/comments/$COMMENT_ID" \
      -f body="$COMMENT_BODY")
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
    echo "Failed to update comment!"
    echo "Exit code: $EXIT_CODE"
    echo "Error output: $PATCH_RESULT"
fi

else
    # Create new comment
    gh pr comment "$PR_NUMBER" -b "$COMMENT_BODY"
fi

if [ "$RESULT" == "FAIL" ]; then
    exit 1
fi
