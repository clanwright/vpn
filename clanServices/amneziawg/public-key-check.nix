{ pkgs }:
pkgs.writeShellApplication {
  name = "amneziawg-public-key-check";
  runtimeInputs = [ pkgs.amneziawg-tools ];
  text = ''
    set -euo pipefail

    if [ "$#" -ne 3 ]; then
      printf 'amneziawg: expected secret owner, private key path, and public key\n' >&2
      exit 2
    fi

    secret_owner="$1"
    private_key_path="$2"
    expected_public_key="$3"

    derived_public_key="$("${pkgs.amneziawg-tools}/bin/awg" pubkey < "$private_key_path" 2>/dev/null)" || {
      printf 'amneziawg: failed to derive public key for secret %s\n' "$secret_owner" >&2
      exit 1
    }
    if [ "$derived_public_key" != "$expected_public_key" ]; then
      printf 'amneziawg: public key mismatch for secret %s\n' "$secret_owner" >&2
      exit 1
    fi
  '';
}
