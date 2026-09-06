#!/usr/bin/env bash
set -euo pipefail

if [[ "${VPN_VERIFY_IN_DEV_SHELL:-0}" != 1 ]]; then
	export VPN_VERIFY_IN_DEV_SHELL=1
	exec nix develop --no-write-lock-file --command bash "$0" "$@"
fi

if [[ $# -ne 0 ]]; then
	printf 'Usage: %s\n' "$0" >&2
	exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_dir="$repo_root/.work/verification/$run_id"
mkdir -p "$artifact_dir"
summary="$artifact_dir/summary.tsv"
printf 'stage\tstatus\tduration_seconds\tlog\n' >"$summary"
whole_started="$(date +%s)"

finalize() {
	local status="$?"
	local whole_finished whole_status
	trap - EXIT
	whole_finished="$(date +%s)"
	if [[ $status -eq 0 ]]; then
		whole_status=pass
	else
		whole_status=fail
	fi
	printf 'whole\t%s\t%s\t%s\n' "$whole_status" "$((whole_finished - whole_started))" "$summary" >>"$summary"
	printf 'Verification %s. Summary: %s\n' "$whole_status" "$summary"
	exit "$status"
}
trap finalize EXIT

run_stage() {
	local stage="$1"
	shift
	local log="$artifact_dir/$stage.log"
	local started finished status
	started="$(date +%s)"
	printf '== %s ==\n' "$stage"
	set +e
	"$@" > >(tee "$log") 2>&1
	status=$?
	set -e
	finished="$(date +%s)"
	if [[ $status -eq 0 ]]; then
		printf '%s\tpass\t%s\t%s\n' "$stage" "$((finished - started))" "$log" >>"$summary"
	else
		printf '%s\tfail\t%s\t%s\n' "$stage" "$((finished - started))" "$log" >>"$summary"
		printf 'Verification failed in %s; log: %s\n' "$stage" "$log" >&2
		return "$status"
	fi
}

static_checks() {
	local nix_files=()
	while IFS= read -r -d '' file; do
		if [[ -f "$file" ]]; then
			nix_files+=("$file")
		fi
	done < <(git ls-files -z --cached --others --exclude-standard -- '*.nix')

	git diff --check \
		&& git diff --cached --check \
		&& nixfmt --check "${nix_files[@]}" \
		&& statix check . \
		&& deadnix --fail "${nix_files[@]}" \
		&& gitleaks dir . --redact --no-banner
}

flake_eval() {
	nix flake check --no-build --no-write-lock-file --system x86_64-linux --option allow-import-from-derivation false \
		&& nix eval --json --no-write-lock-file --option allow-import-from-derivation false .#clan.modules --apply builtins.attrNames >/dev/null \
		&& nix eval --json --no-write-lock-file --option allow-import-from-derivation false .#checks.x86_64-linux --apply builtins.attrNames >/dev/null \
		&& nix eval --json --no-write-lock-file --option allow-import-from-derivation false .#packages.x86_64-linux --apply builtins.attrNames >/dev/null
}

linux_checks() {
	nix build --no-link --no-write-lock-file --option allow-import-from-derivation false \
		.#checks.x86_64-linux.domain-contracts \
		.#checks.x86_64-linux.combined-clan-fixture \
		.#checks.x86_64-linux.client-render-smoke \
		.#checks.x86_64-linux.amneziawg-key-consistency \
		.#checks.x86_64-linux.unbound-readiness
}

owned_packages() {
	nix build --no-link --no-write-lock-file --option allow-import-from-derivation false \
		.#packages.x86_64-linux.mihomo \
		.#packages.x86_64-linux.mihomo-keygen \
		.#packages.x86_64-linux.sing-box \
		.#packages.x86_64-linux.naiveproxy \
		.#packages.x86_64-linux.amneziawg-go \
		.#packages.x86_64-linux.amneziawg-tools \
		.#packages.x86_64-linux.adguardhome \
		.#packages.x86_64-linux.unbound
}

run_stage static static_checks
run_stage flake-eval flake_eval
run_stage linux-checks linux_checks
run_stage owned-packages owned_packages
