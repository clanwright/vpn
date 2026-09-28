#!/usr/bin/env bash
# Called by the publisher harness; only synthetic input and stubbed HTTP.
set -Eeuo pipefail
record_failure() {
	printf 'subscription runtime harness: FAIL near line %s\n' "$1" >&2
	if [[ -n "${VPN_SUBSCRIPTION_TEST_ARTIFACT_DIR:-}" && -d "${test_root:-}" ]]; then
		mkdir -p "$VPN_SUBSCRIPTION_TEST_ARTIFACT_DIR"
		for file in lifecycle.log publication.log mihomo.json singbox.json; do
			if [[ -f "$test_root/$file" ]]; then cp "$test_root/$file" "$VPN_SUBSCRIPTION_TEST_ARTIFACT_DIR/$file"; fi
		done
	fi
}
trap 'record_failure "$LINENO"' ERR

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nix_bin="${VPN_SUBSCRIPTION_TEST_NIX_BIN:-$(command -v nix)}"
jq_bin="${VPN_SUBSCRIPTION_TEST_JQ_BIN:-$(command -v jq)}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/vpn-subscriptions-runtime-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/runtime" "$test_root/cwd"
export VPN_SUBSCRIPTION_TEST_ROOT="$test_root/runtime"
export VPN_SUBSCRIPTION_TEST_URL_FILE="$test_root/url-secret"
export VPN_SUBSCRIPTION_TEST_BODY="$test_root/body.json"
export VPN_SUBSCRIPTION_TEST_NOW=100000
export VPN_SUBSCRIPTION_TEST_HTTP=200
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=0
export VPN_SUBSCRIPTION_TEST_CALLS="$test_root/curl-calls"
export VPN_SUBSCRIPTION_TEST_CONVERTER="$test_root/converter.jq"
export VPN_SUBSCRIPTION_TEST_COMPOSER="$test_root/composer.jq"
printf '%s' 'https://synthetic.example.invalid/subscription/fixture-secret-url' >"$VPN_SUBSCRIPTION_TEST_URL_FILE"
cp "$repository_root/checks/fixtures/external-subscriptions.json" "$VPN_SUBSCRIPTION_TEST_BODY"

cat >"$test_root/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output=''
while (($#)); do
	case "$1" in
	-o | --output) output="$2"; shift 2 ;;
	*) shift ;;
	esac
done
printf 'call\n' >>"$VPN_SUBSCRIPTION_TEST_CALLS"
if [[ -n "${VPN_SUBSCRIPTION_TEST_PUBLISHED:-}" ]]; then
	jq -e '[.outbounds[] | select(.type == "naive")] | length == 1' "$VPN_SUBSCRIPTION_TEST_PUBLISHED" >/dev/null
	printf 'own available before fetch\n' >"$VPN_SUBSCRIPTION_TEST_OWN_READY"
fi
# Assert the generator suppresses raw curl output containing a URL.
printf 'synthetic curl diagnostic: fixture-secret-url\n' >&2
if [[ -n "$output" ]]; then cp "$VPN_SUBSCRIPTION_TEST_BODY" "$output"; fi
if [[ -n "${VPN_SUBSCRIPTION_TEST_NOW_FILE:-}" && -n "${VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS:-}" ]]; then
	read -r now <"$VPN_SUBSCRIPTION_TEST_NOW_FILE"
	printf '%s\n' "$((now + VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS))" >"$VPN_SUBSCRIPTION_TEST_NOW_FILE"
fi
printf '%s' "$VPN_SUBSCRIPTION_TEST_HTTP"
exit "$VPN_SUBSCRIPTION_TEST_CURL_EXIT"
MOCK
cat >"$test_root/bin/date" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == '+%s' || "$*" == '-u +%s' ]]; then
	if [[ -n "${VPN_SUBSCRIPTION_TEST_NOW_FILE:-}" ]]; then cat "$VPN_SUBSCRIPTION_TEST_NOW_FILE"; else printf '%s\n' "$VPN_SUBSCRIPTION_TEST_NOW"; fi
else
	exec /bin/date "$@"
fi
MOCK
cat >"$test_root/bin/chown" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$test_root/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
# The synthetic curl returns immediately. This adaptation does not establish
# elapsed-time enforcement by Linux coreutils timeout.
set -euo pipefail
if [[ "$1" == --kill-after=* ]]; then shift; fi
shift
exec "$@"
MOCK
chmod +x "$test_root/bin"/*
export PATH="$test_root/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

generate_fixture() {
	"$nix_bin" eval --offline --max-jobs 0 --builders '' --impure --json \
		--option allow-import-from-derivation false \
		--file "$repository_root/checks/external-subscriptions-runtime-fixture.nix" >"$test_root/fixture.json"
	"$jq_bin" -r '.runtimeScript' "$test_root/fixture.json" >"$test_root/runtime.sh"
	"$jq_bin" -r '.converter' "$test_root/fixture.json" >"$test_root/converter.jq"
	"$jq_bin" -r '.composer' "$test_root/fixture.json" >"$test_root/composer.jq"
	"$jq_bin" '.mihomo' "$test_root/fixture.json" >"$test_root/base-mihomo.json"
	"$jq_bin" '.singBox' "$test_root/fixture.json" >"$test_root/base-singbox.json"
}
generate_fixture

run_lifecycle() {
	local operation="$1"
	(cd "$test_root/cwd" && bash -euo pipefail -c '
		runtime_base="$VPN_SUBSCRIPTION_TEST_ROOT"
		private_tmp_files=()
		trap '\''rm -f -- "${private_tmp_files[@]}"'\'' EXIT
		exec 3>&2
		# Match the publisher boundary: raw tool diagnostics are suppressed.
		exec >/dev/null 2>&1
		source "$1"
		external_prepare
		case "$2" in
		refresh) external_refresh ;;
		prepare) external_prepare ;;
		compose)
			external_prepare
			if jq -e ". != null" "$3" >/dev/null; then external_compose fixture mihomo "$3"; fi
			if jq -e ". != null" "$4" >/dev/null; then external_compose fixture json "$4"; fi
			;;
		unscoped) external_prepare; external_compose unscoped mihomo "$3" ;;
		esac
	' bash "$test_root/runtime.sh" "$operation" "$test_root/mihomo.json" "$test_root/singbox.json") >>"$test_root/lifecycle.log" 2>&1
}
compose() {
	cp "$test_root/base-mihomo.json" "$test_root/mihomo.json"
	cp "$test_root/base-singbox.json" "$test_root/singbox.json"
	run_lifecycle compose
}
assert_nodes() {
	local mihomo_count="$1" singbox_count="$2"
	printf 'subscription nodes at synthetic time %s: expecting Mihomo=%s sing-box=%s\n' "$VPN_SUBSCRIPTION_TEST_NOW" "$mihomo_count" "$singbox_count"
	"$jq_bin" -e --argjson count "$mihomo_count" \
		'[(.proxies // [])[] | select(.type == "vless")] | length == $count' "$test_root/mihomo.json" >/dev/null
	"$jq_bin" -e --argjson count "$singbox_count" \
		'[.outbounds[] | select(.type == "vless")] | length == $count' "$test_root/singbox.json" >/dev/null
}
assert_no_leaks() {
	if rg -q 'fixture-secret-url|11111111-1111-4111-8111-111111111111|fixture-xhttp' "$test_root/lifecycle.log"; then
		printf 'subscription lifecycle leaked private fixture material\n' >&2
		exit 1
	fi
	test -z "$(find "$test_root/cwd" -mindepth 1 -print -quit)"
}

# Converter and composer assertions use real jq, generated production filters,
# and production own-provider templates; no VPN parser is executed.
"$jq_bin" --arg source fixture --argjson auto true -f "$test_root/converter.jq" \
	"$VPN_SUBSCRIPTION_TEST_BODY" >"$test_root/nodes.json"
"$jq_bin" -e 'length == 2 and ([.[] | select(.singBox != null)] | length == 1)
	and all(.[]; .tcp and .udp and .auto)
	and ([.[].mihomo.port] | sort) == [443,8443]
	and (.[0].mihomo.uuid == "11111111-1111-4111-8111-111111111111")' "$test_root/nodes.json" >/dev/null

run_lifecycle refresh
compose
assert_nodes 2 1
"$jq_bin" -e --slurpfile base "$test_root/base-mihomo.json" '
	.dns == $base[0].dns and .tun == $base[0].tun and .hosts == $base[0].hosts
	and ."rule-providers" == $base[0]."rule-providers"
	and all(."proxy-groups"[]; (.proxies | index("DIRECT")) == null)
	and ([."proxy-groups"[] | select(.name == "UDP") | .proxies[] | select(startswith("external-"))] | length == 2)
' "$test_root/mihomo.json" >/dev/null
"$jq_bin" -e --slurpfile base "$test_root/base-singbox.json" '
	.dns == $base[0].dns and .inbounds == $base[0].inbounds
	and .route.rule_set == $base[0].route.rule_set
	and .route.default_domain_resolver == $base[0].route.default_domain_resolver
	and all(.outbounds[] | select(.type == "vless");
		.domain_resolver.server as $resolver | any($base[0].dns.servers[]; .tag == $resolver and .type == "https"))
	and ([.outbounds[] | select(.tag == "UDP") | .outbounds[] | select(startswith("external-"))] | length == 1)
' "$test_root/singbox.json" >/dev/null
cp "$test_root/mihomo.json" "$test_root/first-mihomo.json"
assert_no_leaks

# Profile scope is checked through the lifecycle's selection of accepted nodes.
cp "$test_root/base-mihomo.json" "$test_root/mihomo.json"
run_lifecycle unscoped
"$jq_bin" -e '. == null' "$test_root/mihomo.json" >/dev/null

export VPN_SUBSCRIPTION_TEST_MANUAL=1
generate_fixture
compose
assert_nodes 2 1
"$jq_bin" -e 'all(."proxy-groups"[] | select(.type == "url-test"); all(.proxies[]; startswith("external-") | not))' "$test_root/mihomo.json" >/dev/null
"$jq_bin" -e 'all(.outbounds[] | select(.type == "urltest"); all(.outbounds[]; startswith("external-") | not))' "$test_root/singbox.json" >/dev/null
unset VPN_SUBSCRIPTION_TEST_MANUAL
generate_fixture

# Successful empty snapshots replace old nodes immediately. A valid response
# whose individual tuples are unsupported has the same authoritative result.
printf '[]\n' >"$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=103600
run_lifecycle refresh
compose
assert_nodes 0 0
"$jq_bin" -e --slurpfile base "$test_root/base-singbox.json" '.route.rules == $base[0].route.rules' "$test_root/singbox.json" >/dev/null

cp "$repository_root/checks/fixtures/external-subscriptions.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=107200
run_lifecycle refresh
compose
assert_nodes 2 1
# Change exactly one unsupported TLS semantic field; keep its supported sibling.
"$jq_bin" '.[1].outbounds[0].streamSettings.tlsSettings.allowInsecure = true' \
	"$VPN_SUBSCRIPTION_TEST_BODY" >"$test_root/unsupported.json"
cp "$test_root/unsupported.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=110800
run_lifecycle refresh
compose
assert_nodes 1 1
"$jq_bin" '.[0].outbounds[0].streamSettings.sockopt = {mark: 123}' \
	"$VPN_SUBSCRIPTION_TEST_BODY" >"$test_root/unsupported.json"
cp "$test_root/unsupported.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=114400
run_lifecycle refresh
compose
assert_nodes 0 0

# Invalid response invalidates old nodes. Transient HTTP errors alone preserve
# a bounded prior snapshot; retry is 300 seconds and expiry needs no fetch.
cp "$repository_root/checks/fixtures/external-subscriptions.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=118000
run_lifecycle refresh
compose
assert_nodes 2 1
printf '{malformed\n' >"$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=121600
run_lifecycle refresh
compose
assert_nodes 0 0
cp "$repository_root/checks/fixtures/external-subscriptions.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=121900
run_lifecycle refresh
compose
assert_nodes 2 1
# Partial HTTP 200 plus transport timeout must not accept the body. Advance
# the synthetic clock during curl and require retry measured from completion.
rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at"
export VPN_SUBSCRIPTION_TEST_NOW=123000 VPN_SUBSCRIPTION_TEST_CURL_EXIT=28
export VPN_SUBSCRIPTION_TEST_NOW_FILE="$test_root/now"
export VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS=10
printf '123000\n' >"$VPN_SUBSCRIPTION_TEST_NOW_FILE"
run_lifecycle refresh
compose
assert_nodes 2 1
test "$(cat "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/accepted-at")" == 121900
test "$(cat "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at")" == 123310
unset VPN_SUBSCRIPTION_TEST_NOW_FILE VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=0
export VPN_SUBSCRIPTION_TEST_HTTP=503 VPN_SUBSCRIPTION_TEST_NOW=125500
run_lifecycle refresh
compose
assert_nodes 2 1
calls_before="$(wc -l <"$VPN_SUBSCRIPTION_TEST_CALLS" | tr -d ' ')"
export VPN_SUBSCRIPTION_TEST_NOW=125799
run_lifecycle refresh
test "$(wc -l <"$VPN_SUBSCRIPTION_TEST_CALLS" | tr -d ' ')" == "$calls_before"
export VPN_SUBSCRIPTION_TEST_NOW=125800
run_lifecycle refresh
test "$(wc -l <"$VPN_SUBSCRIPTION_TEST_CALLS" | tr -d ' ')" == "$((calls_before + 1))"
export VPN_SUBSCRIPTION_TEST_NOW=208300
compose
assert_nodes 0 0

# Authentication failures invalidate immediately, including before stale TTL.
cp "$repository_root/checks/fixtures/external-subscriptions.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_HTTP=200 VPN_SUBSCRIPTION_TEST_NOW=210000
run_lifecycle refresh
compose
assert_nodes 2 1
export VPN_SUBSCRIPTION_TEST_HTTP=401 VPN_SUBSCRIPTION_TEST_NOW=213600
run_lifecycle refresh
compose
assert_nodes 0 0
export VPN_SUBSCRIPTION_TEST_HTTP=200 VPN_SUBSCRIPTION_TEST_NOW=213900
run_lifecycle refresh
compose
assert_nodes 2 1
export VPN_SUBSCRIPTION_TEST_HTTP=403 VPN_SUBSCRIPTION_TEST_NOW=217500
run_lifecycle refresh
compose
assert_nodes 0 0

# URL content rotation and source removal revoke old runtime credentials even
# if the next request fails; no old node may survive until the next refresh.
export VPN_SUBSCRIPTION_TEST_HTTP=200 VPN_SUBSCRIPTION_TEST_NOW=217800
run_lifecycle refresh
compose
assert_nodes 2 1
printf '%s' 'https://synthetic.example.invalid/subscription/rotated-fixture-secret-url' >"$VPN_SUBSCRIPTION_TEST_URL_FILE"
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=7 VPN_SUBSCRIPTION_TEST_HTTP=000
run_lifecycle refresh
compose
assert_nodes 0 0
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=0 VPN_SUBSCRIPTION_TEST_HTTP=200 VPN_SUBSCRIPTION_TEST_NOW=218100
run_lifecycle refresh
compose
assert_nodes 2 1
export VPN_SUBSCRIPTION_TEST_REMOVED=1
generate_fixture
compose
assert_nodes 0 0
test ! -e "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture"
assert_no_leaks

# Missing, invalid, and future acceptance timestamps cannot bless a cached
# snapshot left by an interrupted source update. Own Naive remains available.
unset VPN_SUBSCRIPTION_TEST_REMOVED
generate_fixture
for corrupt in missing malformed future; do
	rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at"
	run_lifecycle refresh
	compose
	assert_nodes 2 1
	case "$corrupt" in
	missing) rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/accepted-at" ;;
	malformed) printf 'invalid' >"$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/accepted-at" ;;
	future) printf '%s' "$((VPN_SUBSCRIPTION_TEST_NOW + 1))" >"$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/accepted-at" ;;
	esac
	compose
	assert_nodes 0 0
done

export VPN_SUBSCRIPTION_TEST_SHORT_TTL=1
generate_fixture
rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at"
run_lifecycle refresh
compose
assert_nodes 2 1
export VPN_SUBSCRIPTION_TEST_NOW=218160
compose
assert_nodes 0 0
unset VPN_SUBSCRIPTION_TEST_SHORT_TTL
generate_fixture

# One source's failed, slow synthetic fetch cannot extend a sibling's TTL.
# Each refresh iteration processes one source and composition prunes all.
export VPN_SUBSCRIPTION_TEST_SECOND_SOURCE=1
generate_fixture
rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at"
run_lifecycle refresh
run_lifecycle refresh
compose
assert_nodes 4 2
"$jq_bin" -e '[.proxies[].name] | length == (unique | length)' "$test_root/mihomo.json" >/dev/null
rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at"
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=28
export VPN_SUBSCRIPTION_TEST_NOW_FILE="$test_root/now"
export VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS=90
printf '%s\n' "$VPN_SUBSCRIPTION_TEST_NOW" >"$VPN_SUBSCRIPTION_TEST_NOW_FILE"
run_lifecycle refresh
compose
assert_nodes 2 1
"$jq_bin" -e 'all(.proxies[]; .name | startswith("external-fixture-"))' "$test_root/mihomo.json" >/dev/null
unset VPN_SUBSCRIPTION_TEST_NOW_FILE VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS VPN_SUBSCRIPTION_TEST_SECOND_SOURCE
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=0
generate_fixture

# Execute the complete generated publication loop: its first own generation
# must be exposed during fetch, and a failed second generation must revoke it.
cat >"$test_root/bin/install" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
args=()
directory=false
while (($#)); do
	case "$1" in
	-o | -g) shift 2 ;;
	-d) directory=true; args+=("$1"); shift ;;
	*) args+=("$1"); shift ;;
	esac
done
if ! "$directory"; then
	count=0
	if [[ -f "$VPN_SUBSCRIPTION_TEST_INSTALL_COUNT" ]]; then read -r count <"$VPN_SUBSCRIPTION_TEST_INSTALL_COUNT"; fi
	count=$((count + 1))
	printf '%s\n' "$count" >"$VPN_SUBSCRIPTION_TEST_INSTALL_COUNT"
	if [[ "$count" == 2 ]]; then exit 77; fi
fi
exec /usr/bin/install "${args[@]}"
MOCK
cat >"$test_root/bin/mv" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == -Tf ]]; then shift; exec /bin/mv -f "$@"; fi
exec /bin/mv "$@"
MOCK
cat >"$test_root/bin/chmod" <<'MOCK'
#!/usr/bin/env bash
# Match the existing unprivileged publisher fixture's secret-file adaptation.
set -euo pipefail
if [[ "$1" == 0400 ]]; then shift; exec /bin/chmod 0600 "$@"; fi
exec /bin/chmod "$@"
MOCK
cat >"$test_root/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
# An unexpected extra loop must fail promptly instead of waiting.
exit 78
MOCK
chmod +x "$test_root/bin"/{install,mv,chmod,sleep}
export VPN_PUBLISHER_TEST_EXTERNAL=1
export VPN_PUBLISHER_TEST_ROOT="$test_root/publication"
export VPN_PUBLISHER_TEST_SECRET="$test_root/own-secret"
export VPN_PUBLISHER_TEST_TOKEN="$test_root/own-token"
export VPN_SUBSCRIPTION_TEST_INSTALL_COUNT="$test_root/install-count"
export VPN_SUBSCRIPTION_TEST_OWN_READY="$test_root/own-ready"
export VPN_SUBSCRIPTION_TEST_PUBLISHED="$VPN_PUBLISHER_TEST_ROOT/runtime/published/current/profiles/fixture_path_token_0123456789abcdef/profile.json"
printf '%s' 'synthetic-own-secret' >"$VPN_PUBLISHER_TEST_SECRET"
printf '%s' 'fixture_path_token_0123456789abcdef' >"$VPN_PUBLISHER_TEST_TOKEN"
mkdir -p "$VPN_PUBLISHER_TEST_ROOT/runtime/published" "$VPN_PUBLISHER_TEST_ROOT/runtime/generations"
"$nix_bin" eval --offline --max-jobs 0 --builders '' --impure --raw \
	--option allow-import-from-derivation false \
	--file "$repository_root/checks/publisher-runtime-fixture.nix" >"$test_root/publisher.sh"
if (cd "$test_root/cwd" && bash "$test_root/publisher.sh") >"$test_root/publication.log" 2>&1; then
	printf 'second publication unexpectedly survived injected installation failure\n' >&2
	exit 1
fi
test -f "$VPN_SUBSCRIPTION_TEST_OWN_READY"
test "$(cat "$VPN_SUBSCRIPTION_TEST_INSTALL_COUNT")" == 2
rg -q 'stage=file-installation reason=install-failed' "$test_root/publication.log"
test ! -e "$VPN_PUBLISHER_TEST_ROOT/runtime/published/current"
test -z "$(find "$VPN_PUBLISHER_TEST_ROOT/runtime/generations" -mindepth 1 -print -quit)"
test -z "$(find "$VPN_PUBLISHER_TEST_ROOT/runtime" -name '.secret.*' -o -name '.artifact.*' -o -name '.nodes.*' -o -name '.composed.*' -o -name '.request.*')"
if rg -q 'fixture-secret-url|synthetic-own-secret|11111111-1111-4111-8111-111111111111' "$test_root/publication.log"; then
	printf 'generated publication leaked synthetic private material\n' >&2
	exit 1
fi
assert_no_leaks
printf 'subscription runtime harness: PASS (conversion, composition, scope, manual selection, empty and unsupported, partial200 timeout, retry and TTL, auth, URL rotation, removal, interrupted timestamps, short TTL, sibling expiry during slow fetch, own before fetch, second-publication cleanup, private logs)\n'
