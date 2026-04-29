#!/usr/bin/env bash
# resolve-project-status-field.sh — look up a ProjectV2's ID, a named single-select
# field's ID, and that field's options' IDs in one GraphQL round-trip.
#
# Inputs come from action.yml as env vars: PROJECT_TITLE, FIELD_NAME, OWNER,
# OWNER_TYPE ("organization" | "user"), GH_TOKEN. Outputs go to GITHUB_OUTPUT
# as `project-id`, `field-id`, `options-json` (a JSON map: option name → id).

set -euo pipefail

source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"

case "$OWNER_TYPE" in
  organization) ROOT_FIELD='organization' ;;
  user)         ROOT_FIELD='user' ;;
  *)
    echo "::error::owner-type must be 'organization' or 'user' (got '$OWNER_TYPE')."
    exit 1
    ;;
esac

# Single round-trip: walk the owner's projects, then for the matching one pull
# the named single-select field and its options.
response=$(gh_retry api graphql \
  -F owner="$OWNER" \
  -f query="
    query(\$owner: String!) {
      ${ROOT_FIELD}(login: \$owner) {
        projectsV2(first: 100) {
          nodes {
            id
            title
            fields(first: 50) {
              nodes {
                ... on ProjectV2SingleSelectField {
                  id
                  name
                  options { id name }
                }
              }
            }
          }
        }
      }
    }")

project_node=$(echo "$response" | jq -c \
  --arg t "$PROJECT_TITLE" \
  ".data.${ROOT_FIELD}.projectsV2.nodes[] | select(.title == \$t)")
if [[ -z "$project_node" || "$project_node" == "null" ]]; then
  echo "::error::No ProjectV2 titled '$PROJECT_TITLE' found on $OWNER_TYPE '$OWNER'."
  exit 1
fi

project_id=$(echo "$project_node" | jq -r '.id')

field_node=$(echo "$project_node" | jq -c \
  --arg f "$FIELD_NAME" \
  '.fields.nodes[] | select(.name == $f)')
if [[ -z "$field_node" || "$field_node" == "null" ]]; then
  echo "::error::Project '$PROJECT_TITLE' has no single-select field named '$FIELD_NAME'."
  exit 1
fi

field_id=$(echo "$field_node" | jq -r '.id')
options_json=$(echo "$field_node" | jq -c '[.options[] | {(.name): .id}] | add // {}')

echo "Resolved project='$PROJECT_TITLE' field='$FIELD_NAME':"
echo "  project-id   = $project_id"
echo "  field-id     = $field_id"
echo "  options-json = $options_json"

{
  echo "project-id=$project_id"
  echo "field-id=$field_id"
  echo "options-json=$options_json"
} >> "$GITHUB_OUTPUT"
