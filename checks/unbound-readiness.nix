{ pkgs, self }:
pkgs.runCommand "vpn-unbound-readiness"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.socat
    ];
    UNBOUND_EXE = "${self.packages.x86_64-linux.unbound}/bin/unbound";
  }
  ''
        set -euo pipefail
        mkdir -p "$out"
        exec > >(tee "$out/test.log") 2>&1

        workdir="$TMPDIR/readiness"
        mkdir -p "$workdir"
        notify_socket="$workdir/notify.sock"
        notify_log="$workdir/notify.log"
        unbound_log="$workdir/unbound.log"
        receiver_pid=""
        unbound_pid=""

        cleanup() {
          if [ -n "$unbound_pid" ]; then
            kill "$unbound_pid" 2>/dev/null || true
            wait "$unbound_pid" 2>/dev/null || true
          fi
          if [ -n "$receiver_pid" ]; then
            kill "$receiver_pid" 2>/dev/null || true
            wait "$receiver_pid" 2>/dev/null || true
          fi
        }
        trap cleanup EXIT

        port=$((20000 + $(od -An -N2 -tu2 /dev/urandom) % 20000))
        cat > "$workdir/unbound.conf" <<EOF
    server:
      interface: 127.0.0.1
      port: $port
      do-daemonize: no
      use-syslog: no
      username: ""
      chroot: ""
      directory: "$workdir"
      pidfile: ""
      logfile: ""
    EOF

        timeout 10s socat -u "UNIX-RECVFROM:$notify_socket" - > "$notify_log" &
        receiver_pid=$!
        for attempt in $(seq 1 100); do
          [ -S "$notify_socket" ] && break
          kill -0 "$receiver_pid" 2>/dev/null
          sleep 0.02
        done
        test -S "$notify_socket"

        NOTIFY_SOCKET="$notify_socket" "$UNBOUND_EXE" -d -c "$workdir/unbound.conf" > "$unbound_log" 2>&1 &
        unbound_pid=$!
        if ! wait "$receiver_pid"; then
          cat "$unbound_log"
          exit 1
        fi
        receiver_pid=""
        grep -Fx 'READY=1' "$notify_log"
        kill -0 "$unbound_pid"
        echo 'PASS exact exported Unbound emitted READY=1 over a real NOTIFY_SOCKET'
  ''
