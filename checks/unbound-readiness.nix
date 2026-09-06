{ pkgs, self }:
pkgs.runCommand "vpn-unbound-readiness"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    UNBOUND_EXE = "${self.packages.${pkgs.system}.unbound}/bin/unbound";
  }
  ''
    set -euo pipefail
    python3 <<'PY'
    import os
    import pathlib
    import socket
    import subprocess

    workdir = pathlib.Path(os.environ["TMPDIR"])
    notify_path = workdir / "notify.sock"
    receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    receiver.bind(str(notify_path))
    receiver.settimeout(10)

    port_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    port_socket.bind(("127.0.0.1", 0))
    port = port_socket.getsockname()[1]
    port_socket.close()

    config_path = workdir / "unbound.conf"
    config_path.write_text(
        "server:\n"
        "  interface: 127.0.0.1\n"
        "  port: %d\n"
        "  do-daemonize: no\n"
        "  use-syslog: no\n"
        '  username: ""\n'
        '  chroot: ""\n'
        '  directory: "%s"\n'
        '  pidfile: ""\n'
        '  logfile: ""\n' % (port, workdir)
    )

    environment = os.environ.copy()
    environment["NOTIFY_SOCKET"] = str(notify_path)
    process = subprocess.Popen(
        [os.environ["UNBOUND_EXE"], "-d", "-c", str(config_path)],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        message = receiver.recv(4096).decode("utf-8", errors="replace")
        if "READY=1" not in message.splitlines():
            raise RuntimeError("unexpected sd_notify message: %r" % message)
        pathlib.Path(os.environ["out"]).touch()
    except Exception:
        process.terminate()
        output, _ = process.communicate(timeout=5)
        if output:
            print(output, end="", file=os.sys.stderr)
        raise
    finally:
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        receiver.close()
    PY
  ''
