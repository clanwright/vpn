{ pkgs, self }:
pkgs.runCommand "vpn-unbound-runtime"
  {
    nativeBuildInputs = [
      pkgs.bind.dnsutils
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.ldns
      pkgs.sed
      pkgs.socat
    ];
    UNBOUND_EXE = "${self.packages.x86_64-linux.unbound}/bin/unbound";
  }
  ''
        set -euo pipefail
        mkdir -p "$out"
        exec > >(tee "$out/test.log") 2>&1

        workdir="$TMPDIR/runtime"
        mkdir -p "$workdir"
        cd "$workdir"
        authority_pid=""
        blackhole_pid=""
        resolver_pid=""

        stop_process() {
          local pid="$1"
          kill "$pid" 2>/dev/null || true
          wait "$pid" 2>/dev/null || true
        }
        cleanup() {
          [ -z "$resolver_pid" ] || stop_process "$resolver_pid"
          [ -z "$authority_pid" ] || stop_process "$authority_pid"
          [ -z "$blackhole_pid" ] || stop_process "$blackhole_pid"
        }
        trap cleanup EXIT

        pick_port() {
          echo $((20000 + $(od -An -N2 -tu2 /dev/urandom) % 20000))
        }
        authority_port="$(pick_port)"
        resolver_port="$(pick_port)"
        while [ "$resolver_port" = "$authority_port" ]; do
          resolver_port="$(pick_port)"
        done

        write_zone() {
          local path="$1"
          local address="$2"
          local serial="$3"
          cat > "$path" <<EOF
    \$ORIGIN runtime.test.
    \$TTL 1
    @ 1 IN SOA ns hostmaster $serial 5 5 30 1
    @ 1 IN NS ns
    ns 1 IN A 127.0.0.1
    valid 1 IN A 192.0.2.42
    fresh 1 IN A $address
    bogus 1 IN A 192.0.2.66
    EOF
        }
        write_zone old.zone 192.0.2.10 1
        write_zone new.zone 192.0.2.20 2

        key_name="$(ldns-keygen -k -a ECDSAP256SHA256 runtime.test)"
        test -s "$key_name.key"
        test -s "$key_name.private"
        ldns-signzone -f old.zone.signed old.zone "$key_name" >/dev/null
        ldns-signzone -f new.zone.signed new.zone "$key_name" >/dev/null
        cp old.zone.signed bogus.zone.signed
        test "$(grep -c '192\.0\.2\.66' bogus.zone.signed)" -eq 1
        sed -i 's/192\.0\.2\.66/192.0.2.67/' bogus.zone.signed

        write_authority_config() {
          local zonefile="$1"
          cat > authority.conf <<EOF
    server:
      interface: 127.0.0.1
      port: $authority_port
      do-daemonize: no
      use-syslog: no
      username: ""
      chroot: ""
      directory: "$workdir"
      pidfile: ""
      logfile: ""
      access-control: 127.0.0.0/8 allow
      do-ip6: no
    auth-zone:
      name: "runtime.test."
      zonefile: "$workdir/$zonefile"
      for-downstream: yes
      for-upstream: yes
    EOF
        }

        cat > resolver.conf <<EOF
    server:
      interface: 127.0.0.1
      port: $resolver_port
      do-daemonize: no
      use-syslog: no
      username: ""
      chroot: ""
      directory: "$workdir"
      pidfile: ""
      logfile: ""
      access-control: 127.0.0.0/8 allow
      do-ip6: no
      trust-anchor-file: "$workdir/$key_name.key"
      do-not-query-localhost: no
      do-udp: yes
      do-tcp: yes
      prefetch: yes
      cache-min-ttl: 0
      qname-minimisation: yes
      qname-minimisation-strict: no
      edns-buffer-size: 1232
      max-udp-size: 1232
      serve-expired: yes
      serve-expired-ttl: 3
      serve-expired-ttl-reset: no
      serve-expired-client-timeout: 150
      serve-expired-reply-ttl: 1
    forward-zone:
      name: "runtime.test."
      forward-addr: 127.0.0.1@$authority_port
      forward-first: no
    EOF

        dns_query() {
          local port="$1"
          local name="$2"
          shift 2
          dig @127.0.0.1 -p "$port" "$name" A +dnssec +time=2 +tries=1 "$@"
        }
        address_from() {
          awk '$4 == "A" { print $5 }' "$1"
        }
        assert_status() {
          grep -Eq "status: $2," "$1"
        }
        assert_ad() {
          grep -Eq 'flags: [^;]*\bad\b' "$1"
        }
        assert_no_ad() {
          ! grep -Eq 'flags: [^;]*\bad\b' "$1"
        }
        wait_for_address() {
          local port="$1"
          local name="$2"
          local expected="$3"
          local path="$4"
          shift 4
          for attempt in $(seq 1 50); do
            if dns_query "$port" "$name" "$@" > "$path" 2>&1 \
              && [ "$(address_from "$path")" = "$expected" ]; then
              return 0
            fi
            sleep 0.1
          done
          cat "$path"
          return 1
        }
        start_authority() {
          "$UNBOUND_EXE" -d -c "$workdir/authority.conf" > authority.log 2>&1 &
          authority_pid=$!
        }
        start_resolver() {
          "$UNBOUND_EXE" -d -c "$workdir/resolver.conf" > resolver.log 2>&1 &
          resolver_pid=$!
        }

        write_authority_config bogus.zone.signed
        start_authority
        wait_for_address "$authority_port" valid.runtime.test. 192.0.2.42 authority-udp.txt
        wait_for_address "$authority_port" valid.runtime.test. 192.0.2.42 authority-tcp.txt +tcp
        echo 'PASS authoritative fixture exact answer over UDP and TCP'

        start_resolver
        wait_for_address "$resolver_port" valid.runtime.test. 192.0.2.42 valid-udp.txt
        assert_status valid-udp.txt NOERROR
        assert_ad valid-udp.txt
        wait_for_address "$resolver_port" valid.runtime.test. 192.0.2.42 valid-tcp.txt +tcp
        assert_status valid-tcp.txt NOERROR
        assert_ad valid-tcp.txt
        dns_query "$resolver_port" missing.runtime.test. > negative.txt
        assert_status negative.txt NXDOMAIN
        assert_ad negative.txt
        dns_query "$resolver_port" bogus.runtime.test. > bogus.txt
        assert_status bogus.txt SERVFAIL
        assert_no_ad bogus.txt
        test -z "$(address_from bogus.txt)"
        echo 'PASS DNSSEC valid UDP/TCP, authenticated NXDOMAIN, and bogus SERVFAIL'

        wait_for_address "$resolver_port" fresh.runtime.test. 192.0.2.10 fresh-old.txt
        assert_ad fresh-old.txt
        stop_process "$authority_pid"
        authority_pid=""
        write_authority_config new.zone.signed
        start_authority
        wait_for_address "$authority_port" fresh.runtime.test. 192.0.2.20 authority-new.txt
        sleep 1.2
        dns_query "$resolver_port" fresh.runtime.test. > fresh-new.txt
        assert_status fresh-new.txt NOERROR
        assert_ad fresh-new.txt
        test "$(address_from fresh-new.txt)" = 192.0.2.20
        echo 'PASS fresh-first refresh replaced the expired cached RR'

        stop_process "$authority_pid"
        authority_pid=""
        socat -u "UDP4-RECVFROM:$authority_port,reuseaddr,fork" OPEN:/dev/null > blackhole.log 2>&1 &
        blackhole_pid=$!
        sleep 0.1
        kill -0 "$blackhole_pid"
        sleep 1.2
        stale_started="$(date +%s%3N)"
        dns_query "$resolver_port" fresh.runtime.test. > stale.txt
        stale_finished="$(date +%s%3N)"
        assert_status stale.txt NOERROR
        assert_ad stale.txt
        test "$(address_from stale.txt)" = 192.0.2.20
        test "$((stale_finished - stale_started))" -ge 100
        test "$((stale_finished - stale_started))" -lt 1000
        stop_process "$blackhole_pid"
        blackhole_pid=""
        sleep 3.2
        dns_query "$resolver_port" fresh.runtime.test. > expired.txt
        assert_status expired.txt SERVFAIL
        assert_no_ad expired.txt
        test -z "$(address_from expired.txt)"
        echo 'PASS stale response waited for refresh and stopped after the test expiry bound'

        write_authority_config old.zone.signed
        start_authority
        wait_for_address "$authority_port" fresh.runtime.test. 192.0.2.10 authority-recovered.txt
        wait_for_address "$resolver_port" fresh.runtime.test. 192.0.2.10 recovered.txt
        assert_status recovered.txt NOERROR
        assert_ad recovered.txt
        echo 'PASS recovery returned changed, freshly validated RR data'
        cp ./*.txt "$out/"
        echo 'PASS native Unbound runtime integration'
  ''
