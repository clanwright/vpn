{
  lib,
  pkgs,
  self,
}:
let
  publicKeyCheck = self.lib.awgPublicKeyCheck { inherit pkgs; };
in
pkgs.runCommand "vpn-amneziawg-key-consistency"
  {
    nativeBuildInputs = [
      self.packages.${pkgs.system}.amneziawg-tools
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT
    umask 077

    awg genkey >"$workdir/private.key"
    awg genkey >"$workdir/other.key"
    printf 'not-a-wireguard-key\n' >"$workdir/malformed.key"
    expected_public_key="$(awg pubkey <"$workdir/private.key")"
    other_public_key="$(awg pubkey <"$workdir/other.key")"

    ${lib.getExe publicKeyCheck} fixture/match "$workdir/private.key" "$expected_public_key"

    if ${lib.getExe publicKeyCheck} fixture/mismatch "$workdir/private.key" "$other_public_key" 2>"$workdir/stderr"; then
      echo 'mismatched AWG public key was accepted' >&2
      exit 1
    fi
    ! grep -Fq "$expected_public_key" "$workdir/stderr"
    ! grep -Fq "$other_public_key" "$workdir/stderr"

    if ${lib.getExe publicKeyCheck} fixture/malformed "$workdir/malformed.key" "$expected_public_key" 2>"$workdir/stderr"; then
      echo 'malformed AWG private key was accepted' >&2
      exit 1
    fi
    ! grep -Fq "$expected_public_key" "$workdir/stderr"
    ! grep -Fq 'not-a-wireguard-key' "$workdir/stderr"

    touch "$out"
  ''
