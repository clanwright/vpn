#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'Usage: %s [--network-candidate /nix/store/<hash>-<name>] [evaluation-test-name]\n' "$0" >&2
	exit 2
}
requested_test=""
network_candidate=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--network-candidate)
		[[ $# -ge 2 && -z "$network_candidate" ]] || usage
		network_candidate="$2"
		[[ "$network_candidate" =~ ^/nix/store/[a-z0-9]{32}-[a-zA-Z0-9+._-]+$ ]] || usage
		[[ -d "$network_candidate" && ! -L "$network_candidate" ]] || usage
		shift 2
		;;
	*)
		[[ -z "$requested_test" && "$1" =~ ^[a-z0-9-]+$ && "$1" != -* ]] || usage
		requested_test="$1"
		shift
		;;
	esac
done
flake_override_args=(--no-write-lock-file)
input_mode=root-pin
if [[ -n "$network_candidate" ]]; then
	input_mode=network-candidate
	flake_override_args+=(--override-input network "path:$network_candidate")
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
verification_root="$repo_root/.work/verification"
mkdir -p "$verification_root"
artifact_dir="$(mktemp -d "$verification_root/$run_id.XXXXXX")"
eval_source=""
eval_manifest=""
verification_scope="${requested_test:+test:$requested_test}"
verification_scope="${verification_scope:-full}"
summary="$artifact_dir/summary.tsv"
input_metadata="$artifact_dir/input-metadata.tsv"
printf '%s\n' "$verification_scope" >"$artifact_dir/scope.txt"
printf 'stage\tstatus\tduration_seconds\tlog\n' >"$summary"
printf 'key\tvalue\ninput_mode\t%s\nflake_lock_hash_scope\troot-source-snapshot\n' "$input_mode" >"$input_metadata"
printf '%q\n' "${flake_override_args[@]}" >"$artifact_dir/flake-override-arguments.txt"
if [[ -n "$network_candidate" ]]; then
	printf 'network_candidate_path\t%s\n' "$network_candidate" >>"$input_metadata"
fi
whole_started="$(date +%s)"

finalize() {
	local status="$?"
	local whole_finished whole_status
	trap - EXIT
	if [[ -n "$eval_source" && -d "$eval_source" ]]; then
		rm -rf "$eval_source" || true
	fi
	if [[ -n "$eval_manifest" && -f "$eval_manifest" ]]; then
		rm -f "$eval_manifest" || true
	fi
	whole_finished="$(date +%s)"
	if [[ $status -eq 0 ]]; then
		whole_status=pass
	else
		whole_status=fail
	fi
	printf 'whole\t%s\t%s\t%s\n' "$whole_status" "$((whole_finished - whole_started))" "$summary" >>"$summary"
	printf 'Verification %s for %s (%s). Summary: %s; input metadata: %s\n' "$whole_status" "$verification_scope" "$input_mode" "$summary" "$input_metadata"
	exit "$status"
}
trap finalize EXIT

# The worktree can include intended edits. Identify it without retaining a diff
# or file contents; the evaluation snapshot below receives its own content hash.
git rev-parse HEAD >"$artifact_dir/revision.txt"
git status --short --untracked-files=all >"$artifact_dir/worktree-status.txt"

run_stage() {
	local stage="$1"
	shift
	local log="$artifact_dir/$stage.log"
	local started finished status tee_status
	local pipeline_status=()
	started="$(date +%s)"
	printf '== %s ==\n' "$stage"
	set +e
	"$@" 2>&1 | tee "$log"
	pipeline_status=("${PIPESTATUS[@]}")
	status="${pipeline_status[0]}"
	tee_status="${pipeline_status[1]}"
	set -e
	if [[ $status -eq 0 && $tee_status -ne 0 ]]; then
		status="$tee_status"
	fi
	finished="$(date +%s)"
	if [[ $status -eq 0 ]]; then
		printf '%s\tpass\t%s\t%s\n' "$stage" "$((finished - started))" "$log" >>"$summary"
	else
		printf '%s\tfail\t%s\t%s\n' "$stage" "$((finished - started))" "$log" >>"$summary"
		printf 'Verification failed in %s; log: %s\n' "$stage" "$log" >&2
		return "$status"
	fi
}

source_path_allowed() {
	case "$1" in
	.git/* | .work/* | .env | */.env | .env.* | */.env.* | .envrc | */.envrc | *.age | *.key | *.pem | *.p12 | *.pfx | *.secret | *.private | *.token | credentials.* | */credentials.* | id_* | */id_*)
		return 1
		;;
	*)
		return 0
		;;
	esac
}

static_checks() {
	local nix_files=()
	local nix_manifest
	nix_manifest="$(mktemp "${TMPDIR:-/tmp}/vpn-verification-nix-files.XXXXXX")" || return
	git ls-files -z --cached --others --exclude-standard -- '*.nix' >"$nix_manifest" || {
		rm -f "$nix_manifest" || true
		return 1
	}
	while IFS= read -r -d '' file; do
		if [[ -f "$file" ]]; then
			nix_files+=("$file")
		fi
	done <"$nix_manifest"
	rm -f "$nix_manifest" || return

	git diff --check \
		&& git diff --cached --check \
		&& nixfmt --check "${nix_files[@]}" \
		&& statix check . \
		&& deadnix --fail "${nix_files[@]}" \
		&& gitleaks dir . --redact --no-banner
}

evaluation_checks() {
	local cleanup_status=0
	local eval_status
	local evaluation_apply
	local source_file
	local physical_tmp
	physical_tmp="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || return
	eval_source="$(mktemp -d "$physical_tmp/vpn-verification-source.XXXXXX")" || return
	eval_manifest="$(mktemp "$physical_tmp/vpn-verification-manifest.XXXXXX")" || {
		rm -rf "$eval_source" || true
		return 1
	}
	cleanup_evaluation_source() {
		local cleanup_status=0
		rm -rf "$eval_source" || cleanup_status=1
		rm -f "$eval_manifest" || cleanup_status=1
		return "$cleanup_status"
	}
	git ls-files -z --cached --others --exclude-standard >"$eval_manifest" || {
		cleanup_evaluation_source
		return 1
	}

	: >"$artifact_dir/source-files.txt" || {
		cleanup_evaluation_source
		return 1
	}
	while IFS= read -r -d '' source_file; do
		if ! source_path_allowed "$source_file"; then
			continue
		fi
		if [[ ! -e "$source_file" && ! -L "$source_file" ]]; then
			continue
		fi
		mkdir -p "$eval_source/$(dirname "$source_file")" || {
			cleanup_evaluation_source
			return 1
		}
		cp -P "$source_file" "$eval_source/$source_file" || {
			cleanup_evaluation_source
			return 1
		}
		# Shell quoting keeps unusual file names on one unambiguous line.
		printf '%q\n' "$source_file" >>"$artifact_dir/source-files.txt" || {
			cleanup_evaluation_source
			return 1
		}
	done <"$eval_manifest"
	LC_ALL=C sort -u -o "$artifact_dir/source-files.txt" "$artifact_dir/source-files.txt" || {
		cleanup_evaluation_source
		return 1
	}

	local nix_eval=(
		nix
		--offline
		--option builders ''
		--max-jobs 0
		--option allow-import-from-derivation false
		--option eval-cache false
	)
	local flake_ref="path:$eval_source"
	if [[ -n "$network_candidate" ]]; then
		"${nix_eval[@]}" hash path --type sha256 "$network_candidate" >"$artifact_dir/network-candidate.nar-hash" || {
			cleanup_evaluation_source
			return 1
		}
		printf 'network_candidate_nar_hash\t%s\n' "$(cat "$artifact_dir/network-candidate.nar-hash")" >>"$input_metadata" || {
			cleanup_evaluation_source
			return 1
		}
	fi
	# NAR hashing includes file contents, executable bits and symlink targets.
	# Hash the filtered copy actually evaluated, rather than only the Git commit.
	"${nix_eval[@]}" hash path --type sha256 "$eval_source" >"$artifact_dir/source.nar-hash" || {
		cleanup_evaluation_source
		return 1
	}
	"${nix_eval[@]}" hash path --mode flat --type sha256 "$eval_source/flake.lock" >"$artifact_dir/flake-lock.hash" || {
		cleanup_evaluation_source
		return 1
	}
	if [[ -n "$requested_test" ]]; then
		evaluation_apply="tests: { inherit (tests) moduleNames packageNames; results = tests.results.$requested_test; }"
	else
		evaluation_apply='tests: tests'
	fi

	# Keep flake schema validation, which also covers formatter/devShell shapes.
	# Inventories and contracts share one evaluator rather than three processes.
	"${nix_eval[@]}" flake check --no-build "${flake_override_args[@]}" --system x86_64-linux "$flake_ref" \
		&& "${nix_eval[@]}" eval --json "${flake_override_args[@]}" "$flake_ref#evaluationTests.x86_64-linux" --apply "$evaluation_apply" >"$artifact_dir/evaluation.json"
	eval_status="$?"
	if [[ $eval_status -eq 0 ]]; then
		cat "$artifact_dir/evaluation.json" || eval_status="$?"
	fi
	cleanup_evaluation_source || cleanup_status="$?"
	if [[ $eval_status -ne 0 ]]; then
		return "$eval_status"
	fi
	return "$cleanup_status"
}

run_stage static static_checks
run_stage evaluation evaluation_checks
