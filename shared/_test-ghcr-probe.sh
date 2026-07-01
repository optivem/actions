#!/usr/bin/env bash
# Local smoke-test harness for shared/ghcr-probe.sh's ghcr_bearer_for().
#
# Invokes ghcr_bearer_for directly against a fake `curl` binary on PATH that
# returns a scripted body+status response, mimicking `curl -w '\n%{http_code}'`.
# Validates the status-aware branches without needing a real GHCR token.
#
#   bash shared/_test-ghcr-probe.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fake_dir=$(mktemp -d -t ghcr-probe-test.XXXXXX)
fake_bin="$fake_dir/curl"

cat >"$fake_bin" <<'FAKE'
#!/usr/bin/env bash
if [[ "${GHCR_FAKE_FAIL:-0}" == "1" ]]; then
    echo "curl: (6) Could not resolve host" >&2
    exit 6
fi
printf '%s' "$GHCR_FAKE_BODY"
printf '\n%s' "$GHCR_FAKE_STATUS"
FAKE
chmod +x "$fake_bin"

trap 'rm -rf "$fake_dir"' EXIT

# shellcheck source=./ghcr-probe.sh
source "$HERE/ghcr-probe.sh"

pass=0
fail=0
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS $label"
        (( pass++ )) || true
    else
        echo "  FAIL $label"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        (( fail++ )) || true
    fi
}

run_case() {
    local label="$1" body="$2" status="$3" fail_curl="$4" \
          expected_bearer="$5" expected_status="$6" expected_rc="$7"

    echo "$label"
    local out rc
    out=$(PATH="$fake_dir:$PATH" GHCR_FAKE_BODY="$body" GHCR_FAKE_STATUS="$status" GHCR_FAKE_FAIL="$fail_curl" \
        ghcr_bearer_for "optivem/shop/backend" "" 2>/dev/null) && rc=0 || rc=$?

    local bearer got_status
    bearer=$(sed -n '1p' <<<"$out")
    got_status=$(sed -n '2p' <<<"$out")

    assert_eq "$label: bearer" "$expected_bearer" "$bearer"
    assert_eq "$label: status" "$expected_status" "$got_status"
    assert_eq "$label: return code" "$expected_rc" "$rc"
}

run_case "Test 1: 200 with token present -> success" \
    '{"token":"good-token-abc"}' '200' '0' \
    'good-token-abc' '200' '0'

run_case "Test 2: 200 with no token field -> malformed response" \
    '{"foo":"bar"}' '200' '0' \
    '' '200' '1'

run_case "Test 3: 401 -> invalid or expired token" \
    '{"errors":[{"code":"UNAUTHORIZED"}]}' '401' '0' \
    '' '401' '1'

run_case "Test 4: 403 -> valid token, wrong scope" \
    '{"errors":[{"code":"DENIED"}]}' '403' '0' \
    '' '403' '1'

run_case "Test 5: 500 -> indeterminate, treat as failure" \
    'Internal Server Error' '500' '0' \
    '' '500' '1'

run_case "Test 6: curl network failure -> indeterminate (000)" \
    '' '' '1' \
    '' '000' '1'

echo ""
echo "Results: $pass passed, $fail failed"
if (( fail > 0 )); then
    exit 1
fi
