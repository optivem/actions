#!/usr/bin/env bash
# bulk-update-project-item-status.sh — for every item on a ProjectV2 where the
# single-select FIELD_ID currently equals FROM_OPTION_ID, set it to TO_OPTION_ID.
#
# Inputs come from action.yml as env vars: PROJECT_ID, FIELD_ID, FROM_OPTION_ID,
# TO_OPTION_ID, GH_TOKEN. Output is `items-moved` (count) on GITHUB_OUTPUT.
#
# Items are paged 100 at a time. Filtering is done client-side in jq because the
# ProjectV2 API doesn't support server-side filtering by single-select option.

set -euo pipefail

source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

moved=0
cursor=""

while :; do
  if [[ -z "$cursor" ]]; then
    AFTER='null'
  else
    AFTER="\"$cursor\""
  fi

  # Pull items + each item's status field value. fieldValues(first: 20) is wide
  # enough for any practical project — boards rarely have more than a handful
  # of fields. Filter to the matching field-id client-side.
  response=$(gh_retry api graphql -f query="
    query {
      node(id: \"$PROJECT_ID\") {
        ... on ProjectV2 {
          items(first: 100, after: $AFTER) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              content {
                ... on Issue       { number title }
                ... on PullRequest { number title }
              }
              fieldValues(first: 20) {
                nodes {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    optionId
                    field { ... on ProjectV2SingleSelectField { id } }
                  }
                }
              }
            }
          }
        }
      }
    }")

  mapfile -t to_move < <(
    echo "$response" | jq -r \
      --arg fieldId "$FIELD_ID" \
      --arg fromOpt "$FROM_OPTION_ID" '
        .data.node.items.nodes[]
        | . as $item
        | ($item.fieldValues.nodes[]
           | select(.field.id == $fieldId and .optionId == $fromOpt)) as $hit
        | "\($item.id)\t#\($item.content.number // "?") \($item.content.title // "(untitled)")"
      '
  )

  for entry in "${to_move[@]}"; do
    [[ -z "$entry" ]] && continue
    item_id="${entry%%$'\t'*}"
    label="${entry#*$'\t'}"
    echo "Advancing $label  (item $item_id)"
    gh_retry api graphql \
      -F projectId="$PROJECT_ID" \
      -F itemId="$item_id" \
      -F fieldId="$FIELD_ID" \
      -F optionId="$TO_OPTION_ID" \
      -f query='
        mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
          updateProjectV2ItemFieldValue(input: {
            projectId: $projectId,
            itemId: $itemId,
            fieldId: $fieldId,
            value: { singleSelectOptionId: $optionId }
          }) {
            projectV2Item { id }
          }
        }' > /dev/null
    moved=$((moved + 1))
  done

  has_next=$(echo "$response" | jq -r '.data.node.items.pageInfo.hasNextPage')
  cursor=$(echo "$response" | jq -r '.data.node.items.pageInfo.endCursor')
  [[ "$has_next" == "true" ]] || break
done

echo "Moved $moved item(s)."
echo "items-moved=$moved" >> "$GITHUB_OUTPUT"
