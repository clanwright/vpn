#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nix_bin="$(command -v nix)"
jq_bin="$(command -v jq)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/vpn-publisher-runtime-test.XXXXXX")"
cleanup() {
	rm -rf -- "$test_root"
}
trap cleanup EXIT

mock_bin="$test_root/bin"
runtime_root="$test_root/case"
execution_cwd="$test_root/cwd"
mkdir -p "$mock_bin" "$execution_cwd" "$runtime_root/runtime/published" "$runtime_root/runtime/generations"

cat >"$mock_bin/install" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
directory=false
mode=""
args=()
while (($#)); do
	case "$1" in
	-d) directory=true; shift ;;
	-o | -g) shift 2 ;;
	-m) mode="$2"; shift 2 ;;
	*) args+=("$1"); shift ;;
	esac
done
if "$directory"; then
	mkdir -p -- "${args[@]}"
	if [[ -n "$mode" ]]; then /bin/chmod "$mode" "${args[@]}"; fi
else
	/bin/cp "${args[0]}" "${args[1]}"
	if [[ -n "$mode" ]]; then /bin/chmod "$mode" "${args[1]}"; fi
fi
MOCK

cat >"$mock_bin/chown" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$mock_bin/chmod" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${VPN_PUBLISHER_TEST_FAIL_SECRET_CHMOD:-0}" == 1 && "$1" == 0400 ]]; then
	exit 74
fi
if [[ "$1" == 0400 ]]; then
	shift
	exec /bin/chmod 0600 "$@"
fi
exec /bin/chmod "$@"
MOCK

cat >"$mock_bin/mv" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == -Tf ]]; then
	shift
	exec /bin/mv -f "$@"
fi
exec /bin/mv "$@"
MOCK

cat >"$mock_bin/mktemp" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f "$VPN_PUBLISHER_TEST_MKTEMP_STATE" ]]; then
	read -r count <"$VPN_PUBLISHER_TEST_MKTEMP_STATE"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$VPN_PUBLISHER_TEST_MKTEMP_STATE"
if [[ "${VPN_PUBLISHER_TEST_FAIL_MKTEMP_AT:-0}" == "$count" ]]; then
	exit 73
fi
exec /usr/bin/mktemp "$@"
MOCK

cat >"$mock_bin/jq" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${VPN_PUBLISHER_TEST_FAIL_JQ:-0}" == 1 ]]; then
	exit 75
fi
exec "$VPN_PUBLISHER_TEST_REAL_JQ" "$@"
MOCK

chmod +x "$mock_bin"/*

secret_path="$test_root/fake-secret"
token_path="$test_root/fake-token"
generated_script="$test_root/generated-publisher.sh"
failure_log="$test_root/failure.log"
printf '%s' 'fake secret "quoted" $dollar \ slash' >"$secret_path"
printf '%s' 'fixture_path_token_0123456789abcdef' >"$token_path"

export VPN_PUBLISHER_TEST_ROOT="$runtime_root"
export VPN_PUBLISHER_TEST_SECRET="$secret_path"
export VPN_PUBLISHER_TEST_TOKEN="$token_path"
export VPN_PUBLISHER_TEST_MKTEMP_STATE="$test_root/mktemp-state"
export VPN_PUBLISHER_TEST_REAL_JQ="$jq_bin"
export PATH="$mock_bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

"$nix_bin" eval --offline --max-jobs 0 --builders '' --impure --raw \
	--option allow-import-from-derivation false \
	--file "$repository_root/checks/publisher-runtime-fixture.nix" >"$generated_script"

assert_no_private_temporaries() {
	local leaked
	leaked="$(find "$runtime_root/runtime" -maxdepth 1 \( -name '.secret.*' -o -name '.artifact.*' \) -print -quit)"
	if [[ -n "$leaked" ]]; then
		printf 'private temporary leaked: %s\n' "$leaked" >&2
		return 1
	fi
}

assert_execution_cwd_empty() {
	local unexpected
	unexpected="$(find "$execution_cwd" -mindepth 1 -print -quit)"
	if [[ -n "$unexpected" ]]; then
		printf 'generated publisher wrote outside its runtime directory: %s\n' "$unexpected" >&2
		return 1
	fi
}

reset_case() {
	rm -rf -- "$runtime_root/runtime"
	mkdir -p "$runtime_root/runtime/published" "$runtime_root/runtime/generations"
	rm -f -- "$VPN_PUBLISHER_TEST_MKTEMP_STATE" "$failure_log"
}

(cd "$execution_cwd" && bash "$generated_script")
published="$runtime_root/runtime/published/current/profiles/fixture_path_token_0123456789abcdef/profile.json"
test -L "$runtime_root/runtime/published/current"
jq --rawfile expected "$secret_path" \
	-e '.credential == $expected and .marker == "publisher-runtime-fixture"' "$published" >/dev/null
assert_no_private_temporaries
assert_execution_cwd_empty

reset_case
export VPN_PUBLISHER_TEST_FAIL_MKTEMP_AT=3
if (cd "$execution_cwd" && bash "$generated_script") 2>"$failure_log"; then
	printf 'publisher unexpectedly succeeded after injected artifact mktemp failure\n' >&2
	exit 1
fi
unset VPN_PUBLISHER_TEST_FAIL_MKTEMP_AT
grep -Fq 'stage=preparation reason=temporary-file-failed' "$failure_log"
test ! -e "$runtime_root/runtime/published/current"
test -z "$(find "$runtime_root/runtime/generations" -mindepth 1 -print -quit)"
assert_no_private_temporaries
assert_execution_cwd_empty

reset_case
export VPN_PUBLISHER_TEST_FAIL_JQ=1
if (cd "$execution_cwd" && bash "$generated_script") 2>"$failure_log"; then
	printf 'publisher unexpectedly succeeded after injected jq failure\n' >&2
	exit 1
fi
unset VPN_PUBLISHER_TEST_FAIL_JQ
grep -Fq 'stage=profile-rendering reason=render-failed' "$failure_log"
test ! -e "$runtime_root/runtime/published/current"
test -z "$(find "$runtime_root/runtime/generations" -mindepth 1 -print -quit)"
assert_no_private_temporaries
assert_execution_cwd_empty

reset_case
export VPN_PUBLISHER_TEST_FAIL_SECRET_CHMOD=1
if (cd "$execution_cwd" && bash "$generated_script") 2>"$failure_log"; then
	printf 'publisher unexpectedly succeeded after injected secret chmod failure\n' >&2
	exit 1
fi
unset VPN_PUBLISHER_TEST_FAIL_SECRET_CHMOD
grep -Fq 'stage=credential-loading reason=credential-invalid-or-unavailable' "$failure_log"
test ! -e "$runtime_root/runtime/published/current"
test -z "$(find "$runtime_root/runtime/generations" -mindepth 1 -print -quit)"
assert_no_private_temporaries
assert_execution_cwd_empty

printf 'publisher runtime harness: PASS (success, artifact mktemp failure, jq failure, secret chmod failure)\n'
