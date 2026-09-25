#!/usr/bin/env python3
"""One-shot Wayland capture broker for Darling's Screenshot.app launcher."""

import atexit
import fcntl
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time


def run() -> int:
    if len(sys.argv) != 1:
        print("usage: darling-screenshot-broker", file=sys.stderr)
        return 2

    socket_path = Path(f"/tmp/darling-screenshot-{os.getuid()}.sock")
    if len(os.fsencode(socket_path)) >= 104:
        print("Screenshot socket path is too long", file=sys.stderr)
        return 2
    lock_dir = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
    lock_fd = os.open(lock_dir / "darling-screenshot.lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("Screenshot broker is already running for this user", file=sys.stderr)
        return 2
    socket_path.unlink(missing_ok=True)

    output_dir = Path(os.environ.get("DARLING_SCREENSHOT_OUTPUT_DIR", "")).expanduser()
    if not str(output_dir) or str(output_dir) == ".":
        output_dir = Path.home() / "Pictures" / "Darling Screenshots"
    output_dir.mkdir(parents=True, exist_ok=True)

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(socket_path))
        os.chmod(socket_path, 0o600)
        atexit.register(socket_path.unlink, missing_ok=True)
        server.listen(1)
        server.settimeout(60)
        try:
            connection, _ = server.accept()
        except socket.timeout:
            print("Screenshot.app did not contact the capture broker", file=sys.stderr)
            return 1

        with connection:
            peer = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            _, uid, _ = struct.unpack("3i", peer)
            if uid != os.getuid():
                connection.sendall(b"ERR unauthorized\n")
                return 1
            connection.settimeout(10)
            try:
                request = connection.recv(64)
            except socket.timeout:
                return 1
            if request not in (b"CAPTURE\n", b"CAPTURE_INTERACTIVE\n"):
                connection.sendall(b"ERR request\n")
                return 1

            interactive = (request == b"CAPTURE_INTERACTIVE\n" and
                           os.environ.get("DARLING_SCREENSHOT_NONINTERACTIVE") != "1")
            command = ["grim"]
            if interactive:
                try:
                    selection = subprocess.run(
                        ["slurp", "-f", "%x,%y %wx%h"],
                        capture_output=True, text=True, timeout=300, check=False,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    connection.sendall(b"ERR selection\n")
                    return 1
                if selection.returncode or not selection.stdout.strip():
                    connection.sendall(b"ERR selection\n")
                    return 1
                command.extend(["-g", selection.stdout.strip()])

            output = output_dir / f"Screenshot-{int(time.time() * 1000)}-{os.getpid()}.png"
            command.append(str(output))
            try:
                result = subprocess.run(
                    command, capture_output=True, text=True, timeout=30, check=False,
                )
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"Capture failed: {error}", file=sys.stderr)
                connection.sendall(b"ERR capture\n")
                return 1
            if result.returncode or not output.is_file():
                print(f"Capture failed: {result.stderr.strip()}", file=sys.stderr)
                connection.sendall(b"ERR capture\n")
                return 1
            with output.open("rb") as image:
                if image.read(8) != b"\x89PNG\r\n\x1a\n":
                    output.unlink()
                    connection.sendall(b"ERR invalid-image\n")
                    return 1
            print(f"Saved {output}")
            connection.sendall(f"OK {output}\n".encode())
            return 0


if __name__ == "__main__":
    try:
        sys.exit(run())
    except KeyboardInterrupt:
        sys.exit(130)
