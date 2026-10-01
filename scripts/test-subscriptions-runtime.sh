#!/usr/bin/env bash
# Called by the publisher harness; only synthetic input and stubbed HTTP.
set -Eeuo pipefail
record_failure() {
	printf 'subscription runtime harness: FAIL near line %s\n' "$1" >&2
}
trap 'record_failure "$LINENO"' ERR

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nix_bin="${VPN_SUBSCRIPTION_TEST_NIX_BIN:-$(command -v nix)}"
jq_bin="${VPN_SUBSCRIPTION_TEST_JQ_BIN:-$(command -v jq)}"
if [[ -n "${VPN_SUBSCRIPTION_TEST_ARTIFACT_DIR:-}" ]]; then
	artifact_dir="$VPN_SUBSCRIPTION_TEST_ARTIFACT_DIR"
	mkdir -p "$artifact_dir"
else
	artifact_root="$repository_root/.work/publisher-runtime"
	mkdir -p "$artifact_root"
	artifact_dir="$(mktemp -d "$artifact_root/subscriptions.$(/bin/date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
fi
test_root="$(mktemp -d "${TMPDIR:-/tmp}/vpn-subscriptions-runtime-test.XXXXXX")"
whole_started="$SECONDS"
finalize() {
	local status="$?"
	trap - EXIT
	if ! /bin/mv -- "$test_root" "$artifact_dir/fixtures"; then
		printf 'Could not retain subscription fixtures: %s\n' "$test_root" >&2
		if [[ $status -eq 0 ]]; then status=1; fi
	fi
	printf 'status\tduration_seconds\n%s\t%s\n' "$status" "$((SECONDS - whole_started))" >"$artifact_dir/summary.tsv"
	printf 'Subscription harness artifacts: %s\n' "$artifact_dir"
	exit "$status"
}
trap finalize EXIT
exec > >(tee "$artifact_dir/harness.log") 2>&1
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
	if [[ -n "${VPN_SUBSCRIPTION_TEST_EXPIRY_PROOF:-}" ]]; then
		# Inspect the exposed generation while this request is still blocked:
		# own Naive and the long-lived source survive, the expired sibling does not.
		test "$((now + VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS))" -ge "$VPN_SUBSCRIPTION_TEST_SIBLING_EXPIRES"
		jq -e '([.outbounds[] | select(.type == "naive")] | length == 1)
			and ([.outbounds[] | select(.type == "vless")] | length == 1)
			and all(.outbounds[] | select(.type == "vless"); .tag | endswith(" · Skala · REALITY"))
			and all(.outbounds[]; (.tag | contains(" · Other · ")) | not)' "$VPN_SUBSCRIPTION_TEST_PUBLISHED" >/dev/null
		cp "$VPN_SUBSCRIPTION_TEST_PUBLISHED" "$VPN_SUBSCRIPTION_TEST_EXPIRY_PROOF.json"
		printf 'sibling absent from publication before slow fetch returned at %s\n' "$((now + VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS))" >"$VPN_SUBSCRIPTION_TEST_EXPIRY_PROOF"
	fi
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

fixture_number=0
generate_fixture() {
	"$nix_bin" eval --offline --max-jobs 0 --builders '' --impure --json \
		--option allow-import-from-derivation false \
		--file "$repository_root/checks/external-subscriptions-runtime-fixture.nix" >"$test_root/fixture.json"
	fixture_number=$((fixture_number + 1))
	cp "$test_root/fixture.json" "$test_root/fixture-$fixture_number.json"
	"$jq_bin" -r '.runtimeScript' "$test_root/fixture.json" >"$test_root/runtime.sh"
	"$jq_bin" -r '.converter' "$test_root/fixture.json" >"$test_root/converter.jq"
	"$jq_bin" -r '.composer' "$test_root/fixture.json" >"$test_root/composer.jq"
	"$jq_bin" '.mihomo' "$test_root/fixture.json" >"$test_root/base-mihomo.json"
	"$jq_bin" '.singBox' "$test_root/fixture.json" >"$test_root/base-singbox.json"
	"$jq_bin" -c '.ownNames' "$test_root/fixture.json" >"$test_root/own-names.json"
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
			if jq -e ". != null" "$3" >/dev/null; then external_compose fixture mihomo "$3" "$5"; fi
			if jq -e ". != null" "$4" >/dev/null; then external_compose fixture json "$4" "$5"; fi
			;;
		unscoped) external_prepare; external_compose unscoped mihomo "$3" "$5" ;;
		esac
	' bash "$test_root/runtime.sh" "$operation" "$test_root/mihomo.json" "$test_root/singbox.json" "$(cat "$test_root/own-names.json")") >>"$test_root/lifecycle.log" 2>&1
}
# Refresh diagnostics written since the last log_mark.
log_mark() {
	log_offset="$(wc -l <"$test_root/lifecycle.log" | tr -d ' ')"
}
refresh_log() {
	tail -n "+$((log_offset + 1))" "$test_root/lifecycle.log" | rg '^VPN external refresh: '
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
# Every Mihomo proxy or group name and every sing-box outbound tag is unique,
# and no group, proxy or outbound is named after a removed group.
assert_unique_names() {
	"$jq_bin" -e '[.proxies[]?.name, ."proxy-groups"[].name] as $names
		| ($names | length) == ($names | unique | length)
		and all($names[]; . != "SELECTIVE" and . != "FULL" and . != "UDP" and . != "SELECTIVE-AUTO" and . != "FULL-AUTO" and . != "UDP-AUTO")' \
		"$test_root/mihomo.json" >/dev/null
	"$jq_bin" -e '[.outbounds[].tag] as $tags | ($tags | length) == ($tags | unique | length)' \
		"$test_root/singbox.json" >/dev/null
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
	"$VPN_SUBSCRIPTION_TEST_BODY" >"$test_root/converted.json"
# Service outbounds are counted, not reported; the sing-box skip of the XHTTP
# node is reported per node with its index and a fixed reason.
"$jq_bin" -e '.service == 2 and .skipped == [{index: 1, target: "sing-box", reason: "unsupported-xhttp"}]' \
	"$test_root/converted.json" >/dev/null
"$jq_bin" '.nodes' "$test_root/converted.json" >"$test_root/nodes.json"
"$jq_bin" -e 'length == 2 and ([.[] | select(.singBox != null)] | length == 1)
	and all(.[]; .tcp and .udp and .auto)
	and ([.[].mihomo.port] | sort) == [443,8443]
	and (.[0].mihomo.uuid == "11111111-1111-4111-8111-111111111111")
	and ([.[] | select(.mihomo.network == "xhttp") | .mihomo."xhttp-opts".host] == ["transport.example.invalid"])' "$test_root/nodes.json" >/dev/null
# The converter stores only the sanitized remark; naming happens at composition.
"$jq_bin" -e 'all(.[]; keys == ["auto","label","mihomo","singBox","tcp","udp"] and .label == "🇩🇪 Германия")' \
	"$test_root/nodes.json" >/dev/null

run_lifecycle refresh
# Cached accepted nodes are converter output: no stored name or digest.
"$jq_bin" -e 'length == 2 and all(.[]; keys == ["auto","label","mihomo","singBox","tcp","udp"])' \
	"$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/accepted.json" >/dev/null
test ! -e "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/digest"
compose
assert_nodes 2 1
reality_name='🇩🇪 Германия · Skala · REALITY'
xhttp_name='🇩🇪 Германия · Skala · XHTTP'
# One server offering both transports: the shared remark gains the transport,
# and the REALITY node has the same client-visible name in both formats.
"$jq_bin" -e --slurpfile base "$test_root/base-mihomo.json" --arg r "$reality_name" --arg x "$xhttp_name" '
	.dns == $base[0].dns and .tun == $base[0].tun and .hosts == $base[0].hosts
	and ."rule-providers" == $base[0]."rule-providers"
	and .rules == $base[0].rules
	and ([."proxy-groups"[].name] == ["Ручной","Авто","GLOBAL"])
	and ([.proxies[].name] | sort) == ([$r, $x] | sort)
	and (."proxy-groups"[0] | .type == "select" and .proxies[0] == "Авто" and (.proxies[1:] | sort) == ([$r, $x] | sort))
	and (."proxy-groups"[1] | .type == "url-test" and (.proxies | sort) == ([$r, $x] | sort))
	and (."proxy-groups"[2] | .type == "select" and .proxies == ["Ручной", "Авто"])
	and all(."proxy-groups"[]; (.proxies | index("DIRECT")) == null)
	and ([.proxies[] | select(.name == $r) | .network] == ["tcp"])
	and ([.proxies[] | select(.name == $x) | .network] == ["xhttp"])
' "$test_root/mihomo.json" >/dev/null
"$jq_bin" -e --slurpfile base "$test_root/base-singbox.json" --arg r "$reality_name" '
	.dns == $base[0].dns and .inbounds == $base[0].inbounds
	and .route.rule_set == $base[0].route.rule_set
	and .route.rules == $base[0].route.rules
	and .route.default_domain_resolver == $base[0].route.default_domain_resolver
	and all(.outbounds[] | select(.type == "vless");
		.domain_resolver.server as $resolver | any($base[0].dns.servers[]; .tag == $resolver and .type == "https"))
	and ([.outbounds[] | select(.type == "selector" or .type == "urltest") | .tag] | sort) == ["Авто","Ручной"]
	and ([.outbounds[] | select(.tag == "Ручной")] | length == 1)
	and ([.outbounds[] | select(.tag == "Ручной")][0] | .type == "selector" and .default == "Авто" and .outbounds == ["Авто","own-edge",$r])
	and ([.outbounds[] | select(.tag == "Авто")][0] | .type == "urltest" and .outbounds == ["own-edge",$r])
	and ([.outbounds[] | select(.type == "vless") | .tag] == [$r])
	and all(.outbounds[]; .tag != "FULL" and .tag != "UDP" and .tag != "SELECTIVE")
' "$test_root/singbox.json" >/dev/null
assert_unique_names
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
# Manual-only external nodes stay selectable but never join Auto.
"$jq_bin" -e --arg r "$reality_name" --arg x "$xhttp_name" '
	([."proxy-groups"[].name] == ["Ручной","GLOBAL"])
	and (."proxy-groups"[0] | .type == "select" and (.proxies | sort) == ([$r, $x] | sort))
	and (."proxy-groups"[1] | .type == "select" and .proxies == ["Ручной"])
	and all(."proxy-groups"[]; .type != "url-test" and (.proxies | index("DIRECT")) == null)
' "$test_root/mihomo.json" >/dev/null
"$jq_bin" -e --arg r "$reality_name" '
	([.outbounds[] | select(.tag == "Ручной")][0] | .outbounds == ["Авто","own-edge",$r])
	and ([.outbounds[] | select(.tag == "Авто")][0] | .type == "urltest" and .outbounds == ["own-edge"])
' "$test_root/singbox.json" >/dev/null
assert_unique_names
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
log_mark
run_lifecycle refresh
compose
assert_nodes 1 1
# Each skipped node is logged once with its index, target and fixed cause.
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=accepted mihomo=1 sing-box=1 skipped=1 service=2'
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=1 target=all reason=insecure-tls'
test "$(refresh_log | rg -c 'result=skipped')" == 1
"$jq_bin" '.[0].outbounds[0].streamSettings.sockopt = {mark: 123}' \
	"$VPN_SUBSCRIPTION_TEST_BODY" >"$test_root/unsupported.json"
cp "$test_root/unsupported.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_NOW=114400
log_mark
run_lifecycle refresh
compose
assert_nodes 0 0
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=0 target=all reason=unsupported-transport-field'
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=1 target=all reason=insecure-tls'
test "$(refresh_log | rg -c 'result=skipped')" == 2

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

# Composition after a failed, slow synthetic fetch prunes the expired sibling.
# The integrated publisher case below also checks exposure before fetch returns.
export VPN_SUBSCRIPTION_TEST_SECOND_SOURCE=1
generate_fixture
rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at"
run_lifecycle refresh
run_lifecycle refresh
compose
assert_nodes 4 2
assert_unique_names
rm -f "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/next-at"
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=28
export VPN_SUBSCRIPTION_TEST_NOW_FILE="$test_root/now"
export VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS=90
printf '%s\n' "$VPN_SUBSCRIPTION_TEST_NOW" >"$VPN_SUBSCRIPTION_TEST_NOW_FILE"
run_lifecycle refresh
compose
assert_nodes 2 1
"$jq_bin" -e 'all(.proxies[]; .name | test(" · Skala · (REALITY|XHTTP)$"))' "$test_root/mihomo.json" >/dev/null
assert_unique_names
unset VPN_SUBSCRIPTION_TEST_NOW_FILE VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS VPN_SUBSCRIPTION_TEST_SECOND_SOURCE
export VPN_SUBSCRIPTION_TEST_CURL_EXIT=0
generate_fixture

# Naming regression. The body mixes one server offering both transports, a
# second server with the same remark and transport, a node without a remark
# and a remark without flag or country. Names are resolved when composing.
"$jq_bin" '
	.[0] as $r | .[1] as $x
	| def moved($address): .outbounds[0].settings.vnext[0].address = $address;
	[
		$r,
		$x,
		($r | moved("node-b.example.invalid")),
		($r | del(.remarks) | moved("node-c.example.invalid")),
		($r | .remarks = "Plain text" | moved("node-d.example.invalid"))
	]' "$repository_root/checks/fixtures/external-subscriptions.json" >"$test_root/names-body.json"
cp "$test_root/names-body.json" "$VPN_SUBSCRIPTION_TEST_BODY"
export VPN_SUBSCRIPTION_TEST_HTTP=200 VPN_SUBSCRIPTION_TEST_CURL_EXIT=0 VPN_SUBSCRIPTION_TEST_NOW=222000
run_lifecycle refresh
compose
assert_nodes 5 4
"$jq_bin" -e '
	def named($name; $server): [.proxies[] | select(.name == $name) | .server] == [$server];
	([.proxies[].name] | sort) == ([
		"🇩🇪 Германия · Skala · REALITY",
		"🇩🇪 Германия · Skala · REALITY 2",
		"🇩🇪 Германия · Skala · XHTTP",
		"Plain text · Skala",
		"Skala"] | sort)
	and named("🇩🇪 Германия · Skala · XHTTP"; "node.example.invalid")
	and ([.proxies[] | select(.name | startswith("🇩🇪 Германия · Skala · REALITY")) | .server] | sort) == ["node-b.example.invalid","node.example.invalid"]
	and named("Skala"; "node-c.example.invalid")
	and named("Plain text · Skala"; "node-d.example.invalid")
	and ([."proxy-groups"[].name] == ["Ручной","Авто","GLOBAL"])
	and ."proxy-groups"[0].proxies == (["Авто"] + [.proxies[].name])
	and ."proxy-groups"[1].proxies == [.proxies[].name]
	and ."proxy-groups"[2].proxies == ["Ручной","Авто"]
' "$test_root/mihomo.json" >/dev/null
# sing-box lacks the XHTTP node; the others keep their Mihomo names.
"$jq_bin" -e --slurpfile mihomo "$test_root/mihomo.json" '
	([.outbounds[] | select(.type == "vless") | .tag] | sort)
		== ([$mihomo[0].proxies[] | select(.network == "tcp") | .name] | sort)
	and ([.outbounds[] | select(.type == "vless") | .tag] | length == 4)
' "$test_root/singbox.json" >/dev/null
assert_unique_names
"$jq_bin" '[.proxies[].name]' "$test_root/mihomo.json" >"$test_root/names-skala.json"
cp "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/accepted.json" "$test_root/accepted-before-label.json"
calls_before="$(wc -l <"$VPN_SUBSCRIPTION_TEST_CALLS" | tr -d ' ')"

# Changing only the source label renames nodes on the next composition; the
# cached download is neither refetched nor altered.
export VPN_SUBSCRIPTION_TEST_LABEL=Renamed
generate_fixture
compose
assert_nodes 5 4
"$jq_bin" -e --slurpfile before "$test_root/names-skala.json" '
	[.proxies[].name] == ($before[0] | map(gsub("Skala"; "Renamed")))
	and all(.proxies[].name; contains("Skala") | not)' "$test_root/mihomo.json" >/dev/null
assert_unique_names
test "$(wc -l <"$VPN_SUBSCRIPTION_TEST_CALLS" | tr -d ' ')" == "$calls_before"
cmp -s "$test_root/accepted-before-label.json" "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture/accepted.json"

# A null label falls back to the source identifier.
export VPN_SUBSCRIPTION_TEST_LABEL=-
generate_fixture
compose
assert_nodes 5 4
"$jq_bin" -e --slurpfile before "$test_root/names-skala.json" '
	[.proxies[].name] == ($before[0] | map(gsub("Skala"; "fixture")))' "$test_root/mihomo.json" >/dev/null
assert_unique_names
test "$(wc -l <"$VPN_SUBSCRIPTION_TEST_CALLS" | tr -d ' ')" == "$calls_before"
unset VPN_SUBSCRIPTION_TEST_LABEL
generate_fixture

# A cache written by the previous naming scheme is dropped so the source is
# refetched instead of being renamed twice.
cache_dir="$VPN_SUBSCRIPTION_TEST_ROOT/external-cache/fixture"
for cache_file in accepted.json accepted-at next-at; do cp -p "$cache_dir/$cache_file" "$test_root/legacy-saved-$cache_file"; done
"$jq_bin" 'map(. + {name: "external-fixture-legacy-0123456789abcdef"})' "$test_root/legacy-saved-accepted.json" >"$cache_dir/accepted.json"
run_lifecycle prepare
test ! -e "$cache_dir/accepted.json"
test ! -e "$cache_dir/accepted-at"
test ! -e "$cache_dir/next-at"
for cache_file in accepted.json accepted-at next-at; do cp -p "$test_root/legacy-saved-$cache_file" "$cache_dir/$cache_file"; done
run_lifecycle prepare
test -s "$cache_dir/accepted.json"

# Issue #10 shape: seven countries, each with a REALITY node on 443 and a
# "· Резерв" XHTTP/TLS packet-up node on 8443 whose xhttpSettings.host is
# empty, inside full Xray profiles with direct, block and dns-out outbounds.
"$jq_bin" '
	.[0].outbounds[0] as $r | .[1].outbounds[0] as $x
	| {log: {loglevel: "warning"}, routing: {rules: []}, dns: {servers: ["https://upstream-dns.example.invalid/dns-query"]},
		inbounds: [{protocol: "socks", port: 10808}]} as $shell
	| [{tag: "direct", protocol: "freedom"}, {tag: "block", protocol: "blackhole"}, {tag: "dns-out", protocol: "dns"}] as $service
	| [["🇸🇪", "Швеция"], ["🇫🇮", "Финляндия"], ["🇳🇱", "Нидерланды"], ["🇩🇪", "Германия"], ["🇵🇱", "Польша"], ["🇱🇻", "Латвия"], ["🇰🇿", "Казахстан"]]
	| to_entries | map(
		"country-\(.key).example.invalid" as $address | "\(.value[0]) \(.value[1])" as $remark
		| ($shell + {remarks: $remark, outbounds: ([$r | .settings.vnext[0].address = $address] + $service)}),
			($shell + {remarks: "\($remark) · Резерв", outbounds: ([$x
				| .settings.vnext[0].address = $address
				| .streamSettings.tlsSettings.serverName = $address
				| .streamSettings.xhttpSettings.host = ""] + $service)}))
	| flatten' "$repository_root/checks/fixtures/external-subscriptions.json" >"$test_root/pairs-body.json"
cp "$test_root/pairs-body.json" "$VPN_SUBSCRIPTION_TEST_BODY"
rm -f "$cache_dir/next-at"
export VPN_SUBSCRIPTION_TEST_NOW=225600
log_mark
run_lifecycle refresh
compose
assert_nodes 14 7
assert_unique_names
# Each REALITY/XHTTP pair is told apart by the preserved remark suffix, so no
# transport or ordinal suffix is needed; sing-box gets the REALITY names.
"$jq_bin" -e '
	[.proxies[] | select(.network == "tcp") | .name] as $reality
	| [.proxies[] | select(.network == "xhttp")] as $xhttp
	| ($reality | length) == 7 and ($xhttp | length) == 7
	and ([$xhttp[].name] | sort) == ($reality | map(sub(" · Skala$"; " · Резерв · Skala")) | sort)
	and all($reality[]; test("^\\S+ \\S+ · Skala$"))
	and all($xhttp[]; .port == 8443 and ."xhttp-opts" == {path: "/fixture-xhttp/", mode: "packet-up"}
		and .servername == .server and .alpn == ["h2", "http/1.1"])
	and ."proxy-groups"[0].proxies == (["Авто"] + [.proxies[].name])
' "$test_root/mihomo.json" >/dev/null
"$jq_bin" -e --slurpfile mihomo "$test_root/mihomo.json" '
	[.outbounds[] | select(.type == "vless") | .tag] == [$mihomo[0].proxies[] | select(.network == "tcp") | .name]' \
	"$test_root/singbox.json" >/dev/null
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=accepted mihomo=14 sing-box=7 skipped=0 service=42'
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=1 target=sing-box reason=unsupported-xhttp'
test "$(refresh_log | rg -c 'result=skipped index=[0-9]+ target=sing-box reason=unsupported-xhttp$')" == 7
test "$(refresh_log | rg -c 'result=skipped')" == 7
if refresh_log | rg -q 'country-[0-9]\.example\.invalid|fixture-xhttp|11111111-1111-4111-8111-111111111111'; then
	printf 'skip diagnostics leaked connection parameters\n' >&2
	exit 1
fi

# Same-country REALITY + REALITY: a duplicate remark on a second server gains
# the transport and an ordinal; an identical repeated outbound is imported once.
"$jq_bin" '.[0] as $first
	| [$first, ($first | .outbounds[0].settings.vnext[0].address = "country-7.example.invalid"), $first]' \
	"$test_root/pairs-body.json" >"$VPN_SUBSCRIPTION_TEST_BODY"
rm -f "$cache_dir/next-at"
log_mark
run_lifecycle refresh
compose
assert_nodes 2 2
assert_unique_names
"$jq_bin" -e '
	([.proxies[].name] | sort) == ["🇸🇪 Швеция · Skala · REALITY", "🇸🇪 Швеция · Skala · REALITY 2"]
	and ([.proxies[].server] | sort) == ["country-0.example.invalid", "country-7.example.invalid"]' "$test_root/mihomo.json" >/dev/null
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=accepted mihomo=2 sing-box=2 skipped=1 service=9'
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=2 target=all reason=duplicate'
# Remote remarks, including non-strings and log-injection text with NEL or
# line/paragraph separators, never enter diagnostics.
"$jq_bin" '.[0] | .outbounds[0] = {tag: "proxy", protocol: "vmess", settings: {vnext: [{address: "country-0.example.invalid", port: 443}]}}
	| [.remarks = 7, .remarks = ("A" + ([133] | implode) + "result=skipped" + ([8232] | implode) + "B" + ([8233] | implode) + "C")]' \
	"$test_root/pairs-body.json" >"$VPN_SUBSCRIPTION_TEST_BODY"
rm -f "$cache_dir/next-at"
log_mark
run_lifecycle refresh
compose
assert_nodes 0 0
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=0 target=all reason=unsupported-protocol'
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=1 target=all reason=unsupported-protocol'
test "$(refresh_log | wc -l | tr -d ' ')" == 3

# A remote remark may itself contain a credential or private URL. Keep its UI
# label and transport disambiguation, but omit it from every skip diagnostic.
secret_remark='token=synthetic-remark https://remark.example.invalid/s'
"$jq_bin" --arg remark "$secret_remark" '
	map(.remarks = $remark) | .[0] as $r | .[1] as $x
	| [$r, $x, ($r | .outbounds[0].streamSettings.sockopt = {mark: 123}), $r]' \
	"$repository_root/checks/fixtures/external-subscriptions.json" >"$test_root/private-remark-body.json"
cp "$test_root/private-remark-body.json" "$VPN_SUBSCRIPTION_TEST_BODY"
rm -f "$cache_dir/next-at"
log_mark
run_lifecycle refresh
compose
assert_nodes 2 1
assert_unique_names
"$jq_bin" -e --arg label "$secret_remark" '
	([.proxies[] | select(.type == "vless") | .name] | sort)
	== ([$label + " · Skala · REALITY", $label + " · Skala · XHTTP"] | sort)' \
	"$test_root/mihomo.json" >/dev/null
"$jq_bin" -e --arg label "$secret_remark" '
	[.outbounds[] | select(.type == "vless") | .tag] == [$label + " · Skala · REALITY"]' \
	"$test_root/singbox.json" >/dev/null
cp "$test_root/mihomo.json" "$test_root/private-remark-mihomo.json"
cp "$test_root/singbox.json" "$test_root/private-remark-singbox.json"
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=1 target=sing-box reason=unsupported-xhttp'
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=2 target=all reason=unsupported-transport-field'
refresh_log | rg -qxF 'VPN external refresh: source=fixture result=skipped index=3 target=all reason=duplicate'
test "$(refresh_log | rg -c 'result=skipped')" == 3
if rg -q 'synthetic-remark|remark\.example\.invalid|remark=' "$test_root/lifecycle.log"; then
	printf 'skip diagnostics leaked a remote remark\n' >&2
	exit 1
fi
cp "$test_root/names-body.json" "$VPN_SUBSCRIPTION_TEST_BODY"
rm -f "$cache_dir/next-at"
run_lifecycle refresh
compose
assert_nodes 5 4

# Composer edge cases use the production filter directly on converter output:
# reserved and own-provider names cannot be taken by a subscription node.
compose_direct() {
	"$jq_bin" --arg format "$1" --argjson own "$(cat "$test_root/own-names.json")" --slurpfile nodes "$2" -f "$test_root/composer.jq" "$3" >"$4"
}
converted_nodes() {
	"$jq_bin" --arg source "$1" --argjson auto "$2" -f "$test_root/converter.jq" "$names_body" |
		"$jq_bin" --arg source "$1" --argjson auto "$2" '.nodes | map(.auto = $auto | .source = $source)'
}
names_body="$test_root/names-body.json"
converted_nodes DIRECT true >"$test_root/nodes-direct.json"
compose_direct mihomo "$test_root/nodes-direct.json" "$test_root/base-mihomo.json" "$test_root/direct-mihomo.json"
"$jq_bin" -e '
	([.proxies[].name] | length) == ([.proxies[].name] | unique | length)
	and (.proxies | any(.name == "DIRECT · REALITY"))
	and (.proxies | any(.name == "DIRECT") | not)
	and all(."proxy-groups"[]; (.proxies | index("DIRECT")) == null)' "$test_root/direct-mihomo.json" >/dev/null
converted_nodes own-edge true >"$test_root/nodes-own.json"
compose_direct json "$test_root/nodes-own.json" "$test_root/base-singbox.json" "$test_root/own-singbox.json"
"$jq_bin" -e '
	([.outbounds[].tag] | length) == ([.outbounds[].tag] | unique | length)
	and ([.outbounds[] | select(.tag == "own-edge")] | length == 1)
	and ([.outbounds[] | select(.tag == "own-edge")][0].type == "naive")
	and ([.outbounds[] | select(.tag == "own-edge · REALITY")] | length == 1)' "$test_root/own-singbox.json" >/dev/null
# The own Naive name is absent from Mihomo but still reserved there, so the
# subscription node keeps the same name in both formats.
compose_direct mihomo "$test_root/nodes-own.json" "$test_root/base-mihomo.json" "$test_root/own-mihomo.json"
"$jq_bin" -e --slurpfile box "$test_root/own-singbox.json" '
	([.proxies[] | select(.network == "tcp") | .name]) == ([$box[0].outbounds[] | select(.type == "vless") | .tag])
	and (.proxies | any(.name == "own-edge · REALITY"))
	and (.proxies | any(.name == "own-edge") | not)' "$test_root/own-mihomo.json" >/dev/null

# A subscription at the 1024-outbound cap with one shared remark must name
# its nodes without rescanning earlier ordinals.
"$jq_bin" '.[0] as $node | [range(1024) as $i | $node | .mihomo.port = ($i + 1) | .source = "Perf"]' \
	"$test_root/nodes-direct.json" >"$test_root/nodes-perf.json"
# Bash's timer uses the real clock, independently of the synthetic TTL date.
TIMEFORMAT='%R'
{ time compose_direct mihomo "$test_root/nodes-perf.json" "$test_root/base-mihomo.json" "$test_root/perf-mihomo.json"; } 2>"$test_root/perf.time"
perf_seconds="$(tail -n 1 "$test_root/perf.time")"
printf 'subscription naming of 1024 identical nodes: %ss\n' "$perf_seconds"
"$jq_bin" -en --argjson seconds "$perf_seconds" '$seconds >= 0 and $seconds < 10' >/dev/null
"$jq_bin" -e --arg base "$("$jq_bin" -r '.[0] | (if .label == null then "Perf" else .label + " · Perf" end) + " · " + (if .mihomo.network == "xhttp" then "XHTTP" else "REALITY" end)' "$test_root/nodes-perf.json")" '
	([.proxies[].name] | length == 1024 and length == (unique | length))
	and .proxies[0].name == $base
	and .proxies[1].name == ($base + " 2")
	and .proxies[1023].name == ($base + " 1024")' "$test_root/perf-mihomo.json" >/dev/null

# sing-box without own Auto candidates: manual-only nodes create no Auto group
# and the manual selector defaults to its first connection.
"$jq_bin" '.outbounds |= map(select(.tag != "Авто"))
	| (.outbounds[] | select(.tag == "Ручной")) |= (.outbounds = ["own-edge"] | .default = "own-edge")' \
	"$test_root/base-singbox.json" >"$test_root/no-auto-singbox.json"
converted_nodes fixture false >"$test_root/nodes-manual.json"
compose_direct json "$test_root/nodes-manual.json" "$test_root/no-auto-singbox.json" "$test_root/manual-singbox.json"
"$jq_bin" -e '
	($ext | length == 4)
	and all(.outbounds[]; .type != "urltest" and .tag != "Авто")
	and ([.outbounds[] | select(.tag == "Ручной")] | length == 1)
	and ([.outbounds[] | select(.tag == "Ручной")][0] | .default == "own-edge"
		and .outbounds == (["own-edge"] + [$ext[] | .]))
' --argjson ext "$("$jq_bin" -c '[.outbounds[] | select(.type == "vless") | .tag]' "$test_root/manual-singbox.json")" \
	"$test_root/manual-singbox.json" >/dev/null
# Without own connections the placeholder is dropped and Auto leads.
"$jq_bin" '.outbounds |= map(select(.tag != "Авто" and .tag != "own-edge"))
	| (.outbounds[] | select(.tag == "Ручной")) |= (.outbounds = ["EXTERNAL-REJECT"] | .default = "EXTERNAL-REJECT")' \
	"$test_root/base-singbox.json" >"$test_root/rejecting-singbox.json"
converted_nodes fixture true >"$test_root/nodes-auto.json"
compose_direct json "$test_root/nodes-auto.json" "$test_root/rejecting-singbox.json" "$test_root/auto-singbox.json"
"$jq_bin" -e '
	([.outbounds[] | select(.type == "vless") | .tag]) as $ext
	| ([.outbounds[] | select(.tag == "Ручной")][0] | .default == "Авто" and .outbounds == (["Авто"] + $ext))
	and ([.outbounds[] | select(.tag == "Авто")][0] | .type == "urltest" and .outbounds == $ext)
	and all(.outbounds[]; .tag != "FULL" and .tag != "UDP")' "$test_root/auto-singbox.json" >/dev/null
# No connection at all: the composer returns null instead of an empty selector.
printf '[]\n' >"$test_root/nodes-empty.json"
compose_direct json "$test_root/nodes-empty.json" "$test_root/rejecting-singbox.json" "$test_root/empty-singbox.json"
"$jq_bin" -e '. == null' "$test_root/empty-singbox.json" >/dev/null
compose_direct mihomo "$test_root/nodes-empty.json" "$test_root/base-mihomo.json" "$test_root/empty-mihomo.json"
"$jq_bin" -e '. == null' "$test_root/empty-mihomo.json" >/dev/null
export VPN_SUBSCRIPTION_TEST_NOW=218160
cp "$repository_root/checks/fixtures/external-subscriptions.json" "$VPN_SUBSCRIPTION_TEST_BODY"
assert_no_leaks

# Execute the complete generated publication loop, first cold and then with
# two due cached sources. Own availability and sibling withdrawal are inspected
# inside fetch; a failed second generation must revoke the first in both cases.
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
export VPN_PUBLISHER_TEST_SECRET="$test_root/own-secret"
export VPN_PUBLISHER_TEST_TOKEN="$test_root/own-token"
printf '%s' 'synthetic-own-secret' >"$VPN_PUBLISHER_TEST_SECRET"
printf '%s' 'fixture_path_token_0123456789abcdef' >"$VPN_PUBLISHER_TEST_TOKEN"
for publication_case in cold sibling-expiry; do
	export VPN_PUBLISHER_TEST_ROOT="$test_root/publication-$publication_case"
	export VPN_SUBSCRIPTION_TEST_INSTALL_COUNT="$VPN_PUBLISHER_TEST_ROOT/install-count"
	export VPN_SUBSCRIPTION_TEST_OWN_READY="$VPN_PUBLISHER_TEST_ROOT/own-ready"
	export VPN_SUBSCRIPTION_TEST_PUBLISHED="$VPN_PUBLISHER_TEST_ROOT/runtime/published/current/profiles/fixture_path_token_0123456789abcdef/profile.json"
	mkdir -p "$VPN_PUBLISHER_TEST_ROOT/runtime/published" "$VPN_PUBLISHER_TEST_ROOT/runtime/generations"
	if [[ "$publication_case" == sibling-expiry ]]; then
		# Seed through the same generated source factory as the publisher uses.
		unset VPN_SUBSCRIPTION_TEST_PUBLISHED
		export VPN_SUBSCRIPTION_TEST_SECOND_SOURCE=1
		generate_fixture
		rm -rf -- "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache"
		run_lifecycle refresh
		run_lifecycle refresh
		compose
		assert_nodes 4 2
		"$jq_bin" -e '[.outbounds[] | select(.type == "vless") | .tag] | sort
			== (["🇩🇪 Германия · Skala · REALITY", "🇩🇪 Германия · Other · REALITY"] | sort)' "$test_root/singbox.json" >/dev/null
		cp "$test_root/singbox.json" "$VPN_PUBLISHER_TEST_ROOT/seeded-siblings.json"
		cp -R "$VPN_SUBSCRIPTION_TEST_ROOT/external-cache" "$VPN_PUBLISHER_TEST_ROOT/runtime/external-cache"
		export VPN_SUBSCRIPTION_TEST_PUBLISHED="$VPN_PUBLISHER_TEST_ROOT/runtime/published/current/profiles/fixture_path_token_0123456789abcdef/profile.json"
		export VPN_SUBSCRIPTION_TEST_NOW_FILE="$test_root/now"
		export VPN_SUBSCRIPTION_TEST_ADVANCE_SECONDS=90 VPN_SUBSCRIPTION_TEST_CURL_EXIT=28
		export VPN_SUBSCRIPTION_TEST_EXPIRY_PROOF="$VPN_PUBLISHER_TEST_ROOT/sibling-expiry-before-fetch-return"
		export VPN_SUBSCRIPTION_TEST_SIBLING_EXPIRES="$(($(cat "$VPN_PUBLISHER_TEST_ROOT/runtime/external-cache/other/accepted-at") + 60))"
		printf '%s\n' "$VPN_SUBSCRIPTION_TEST_NOW" >"$VPN_SUBSCRIPTION_TEST_NOW_FILE"
	fi
	"$nix_bin" eval --offline --max-jobs 0 --builders '' --impure --raw \
		--option allow-import-from-derivation false \
		--file "$repository_root/checks/publisher-runtime-fixture.nix" >"$VPN_PUBLISHER_TEST_ROOT/publisher.sh"
	if (cd "$test_root/cwd" && bash "$VPN_PUBLISHER_TEST_ROOT/publisher.sh") >"$VPN_PUBLISHER_TEST_ROOT/publication.log" 2>&1; then
		printf 'second publication unexpectedly survived injected installation failure\n' >&2
		exit 1
	fi
	test -f "$VPN_SUBSCRIPTION_TEST_OWN_READY"
	test "$(cat "$VPN_SUBSCRIPTION_TEST_INSTALL_COUNT")" == 2
	rg -q 'stage=file-installation reason=install-failed' "$VPN_PUBLISHER_TEST_ROOT/publication.log"
	if [[ "$publication_case" == sibling-expiry ]]; then
		test -f "$VPN_SUBSCRIPTION_TEST_EXPIRY_PROOF"
		cat "$VPN_SUBSCRIPTION_TEST_EXPIRY_PROOF"
	fi
	test ! -e "$VPN_PUBLISHER_TEST_ROOT/runtime/published/current"
	test -z "$(find "$VPN_PUBLISHER_TEST_ROOT/runtime/generations" -mindepth 1 -print -quit)"
	test -z "$(find "$VPN_PUBLISHER_TEST_ROOT/runtime" -name '.secret.*' -o -name '.artifact.*' -o -name '.nodes.*' -o -name '.composed.*' -o -name '.request.*')"
	if rg -q 'fixture-secret-url|synthetic-own-secret|11111111-1111-4111-8111-111111111111' "$VPN_PUBLISHER_TEST_ROOT/publication.log"; then
		printf 'generated publication leaked synthetic private material\n' >&2
		exit 1
	fi
done
assert_no_leaks
printf 'subscription runtime harness: PASS (conversion, empty XHTTP host, same-country REALITY+XHTTP and REALITY+REALITY pairs, per-node skip diagnostics, private-remark omission with UI names preserved, source-label naming and collisions, format-parity naming, 1024-node naming, legacy-cache refetch, rules untouched, composition, scope, manual selection, empty and unsupported, partial200 timeout, retry and TTL, auth, URL rotation, removal, interrupted timestamps, short TTL, sibling expiry during slow fetch, own before fetch, second-publication cleanup, private logs)\n'
