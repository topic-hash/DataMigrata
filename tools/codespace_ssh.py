#!/usr/bin/env python3
"""
codespace_ssh.py - SSH into a GitHub Codespace via gh cs ssh --stdio + paramiko.

This script handles the full lifecycle:
1. Authenticates gh CLI with a provided token
2. Starts the codespace if it's shut down
3. Connects via SSH using paramiko through gh's stdio transport
4. Executes commands and returns output

Requirements:
  - Python 3.8+
  - paramiko (pip install paramiko)

Usage:
  python3 codespace_ssh.py --token ghp_xxx --codespace <name> [--command "docker compose up -d"]
  python3 codespace_ssh.py --token ghp_xxx --codespace <name> --interactive
"""
import subprocess
import os
import sys
import tempfile
import argparse
import time
import json


def find_gh_bin():
    """Locate the gh binary - check tools/bin first, then PATH."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    local_gh = os.path.join(script_dir, "bin", "gh")
    if os.path.isfile(local_gh):
        os.chmod(local_gh, 0o755)
        return local_gh
    # Fallback to PATH
    for path_dir in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(path_dir, "gh")
        if os.path.isfile(candidate):
            return candidate
    return None


def ensure_paramiko():
    """Ensure paramiko is installed."""
    try:
        import paramiko
        return paramiko
    except ImportError:
        print("Installing paramiko...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"])
        import paramiko
        return paramiko


def auth_gh(gh_bin, token):
    """Authenticate gh CLI with a token."""
    proc = subprocess.run(
        [gh_bin, "auth", "login", "--with-token"],
        input=token, capture_output=True, text=True
    )
    if proc.returncode != 0:
        print(f"Auth warning: {proc.stderr.strip()}")
    # Set token as env var for subsequent calls
    os.environ["GH_TOKEN"] = token
    return proc.returncode == 0 or os.environ.get("GH_TOKEN") == token


def ensure_codespace_running(gh_bin, codespace_name):
    """Ensure the codespace is in 'Available' state. Returns the full codespace name."""
    token = os.environ.get("GH_TOKEN", "")
    result = subprocess.run(
        [gh_bin, "codespace", "list"],
        capture_output=True, text=True
    )
    # Find the codespace by display name prefix
    for line in result.stdout.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 5:
            full_name = parts[0]
            display = parts[1]
            state = parts[4]
            if codespace_name in full_name or codespace_name == full_name:
                if state == "Shutdown" or state == "ShuttingDown":
                    print(f"Codespace {full_name} is {state}. Starting...")
                    subprocess.run(
                        [gh_bin, "api", "-X", "POST",
                         f"/user/codespaces/{full_name}/start"],
                        capture_output=True, text=True
                    )
                    # Poll until ready
                    for i in range(40):
                        time.sleep(5)
                        cs = subprocess.run(
                            [gh_bin, "api", f"/user/codespaces/{full_name}"],
                            capture_output=True, text=True
                        )
                        if cs.returncode == 0:
                            data = json.loads(cs.stdout)
                            if data.get("state") == "Available":
                                print(f"Codespace is now Available!")
                                return full_name
                            print(f"  Waiting... state={data.get('state')}")
                        else:
                            print(f"  Waiting... (API error)")
                    print("WARNING: Codespace did not start in time")
                return full_name
    print(f"ERROR: Codespace '{codespace_name}' not found")
    return None


def create_fake_ssh_keygen(d):
    """Create a fake ssh-keygen that generates ECDSA keys via paramiko."""
    fk = os.path.join(d, "ssh-keygen")
    with open(fk, "w") as f:
        f.write(f'''#!/bin/bash
if [[ "$1" == "-t" ]]; then
  shift; KTYPE=$1; shift
  KFILE=""
  while [[ $# -gt 0 ]]; do
    [[ "$1" == "-f" ]] && {{ shift; KFILE="$1"; }}
    [[ "$1" == "-N" ]] && {{ shift; }}
    [[ "$1" == "-q" ]] && :
    [[ "$1" == "-C" ]] && {{ shift; }}
    shift
  done
  python3 -c "
import paramiko, sys
key = paramiko.ECDSAKey.generate(bits=256)
key.write_private_key_file(sys.argv[1])
print(key.get_name() + ' ' + key.get_base64())
" "$KFILE" 2>&1 | head -1
fi
exit 0
''')
    os.chmod(fk, 0o755)
    return fk


def ensure_keyfile():
    """Ensure the codespace auto SSH key exists."""
    keyfile = os.path.expanduser("~/.ssh/codespaces.auto")
    if os.path.isfile(keyfile):
        return keyfile
    os.makedirs(os.path.dirname(keyfile), exist_ok=True)
    paramiko = ensure_paramiko()
    key = paramiko.ECDSAKey.generate(bits=256)
    key.write_private_key_file(keyfile)
    pub = key.get_name() + " " + key.get_base64()
    with open(keyfile + ".pub", "w") as f:
        f.write(pub + "\n")
    os.chmod(keyfile, 0o600)
    print(f"Generated SSH key: {keyfile}")
    return keyfile


class SubprocessSocket:
    """Socket-like interface wrapping a subprocess stdin/stdout for paramiko."""

    def __init__(self, proc):
        self.proc = proc
        self._closed = False

    def send(self, data):
        try:
            return self.proc.stdin.write(data)
        except BrokenPipeError:
            return 0

    def recv(self, size):
        data = self.proc.stdout.read(size)
        if not data:
            raise EOFError("Subprocess closed")
        return data

    def close(self):
        self._closed = True
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.stdout.close()
        except Exception:
            pass
        try:
            self.proc.kill()
        except Exception:
            pass

    def settimeout(self, timeout):
        pass

    def fileno(self):
        return self.proc.stdout.fileno()


def ssh_exec(gh_bin, codespace_full_name, command, timeout=300):
    """
    SSH into the codespace and execute a command.
    Returns (stdout, stderr, exit_code).
    """
    paramiko = ensure_paramiko()

    keyfile = ensure_keyfile()

    # Create fake ssh-keygen temp dir
    d = tempfile.mkdtemp()
    create_fake_ssh_keygen(d)

    env = {**os.environ, "PATH": d + ":" + os.environ.get("PATH", "")}

    # Start gh cs ssh --stdio (raw SSH transport)
    proxy_cmd = [gh_bin, "cs", "ssh", "-c", codespace_full_name, "--stdio"]
    proc = subprocess.Popen(
        proxy_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
        env=env,
    )

    # Load private key
    pkey = None
    for cls in [paramiko.ECDSAKey, paramiko.RSAKey]:
        try:
            pkey = cls.from_private_key_file(keyfile)
            break
        except Exception:
            continue

    if not pkey:
        proc.kill()
        raise RuntimeError("Could not load SSH key")

    sock = SubprocessSocket(proc)
    transport = paramiko.Transport(sock)
    transport.use_compression(True)

    stdout_text = ""
    stderr_text = ""
    exit_code = -1

    try:
        transport.start_client()

        transport.auth_publickey("codespace", pkey)

        channel = transport.open_session()
        channel.settimeout(timeout)

        channel.exec_command(command)

        output = b""
        while True:
            try:
                chunk = channel.recv(4096)
                if not chunk:
                    break
                output += chunk
            except Exception:
                break

        stdout_text = output.decode(errors="replace")
        exit_code = channel.recv_exit_status()

    finally:
        try:
            transport.close()
        except Exception:
            pass
        try:
            proc.kill()
        except Exception:
            pass

    return stdout_text, stderr_text, exit_code


def main():
    parser = argparse.ArgumentParser(
        description="SSH into a GitHub Codespace and execute commands",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Authenticate and run docker commands
  python3 codespace_ssh.py --token ghp_xxx --codespace symmetrical-tribble \\
    --command "cd /workspaces/DataMigrata/docker && docker compose up -d && docker compose ps"

  # Run a single command
  python3 codespace_ssh.py --token ghp_xxx --codespace symmetrical-tribble-pjvp5rjg5w5v299jq \\
    --command "ls /workspaces/DataMigrata"

  # Just ensure codespace is running (no command)
  python3 codespace_ssh.py --token ghp_xxx --codespace symmetrical-tribble
"""
    )
    parser.add_argument("--token", required=True, help="GitHub personal access token")
    parser.add_argument("--codespace", required=True,
                        help="Codespace name (full or partial match)")
    parser.add_argument("--command", default=None,
                        help="Command to execute (omit to just ensure codespace is running)")
    parser.add_argument("--timeout", type=int, default=300,
                        help="Command timeout in seconds (default: 300)")
    parser.add_argument("--gh-bin", default=None,
                        help="Path to gh binary (auto-detected if omitted)")

    args = parser.parse_args()

    # Locate gh binary
    gh_bin = args.gh_bin or find_gh_bin()
    if not gh_bin:
        print("ERROR: gh binary not found. Place it in tools/bin/gh or add to PATH")
        sys.exit(1)
    print(f"Using gh: {gh_bin} ({subprocess.check_output([gh_bin, '--version']).decode().strip()})")

    # Authenticate
    print("Authenticating...")
    auth_gh(gh_bin, args.token)

    # Ensure codespace is running
    print("Checking codespace...")
    full_name = ensure_codespace_running(gh_bin, args.codespace)
    if not full_name:
        print("ERROR: Could not find or start codespace")
        sys.exit(1)

    if args.command:
        print(f"\nExecuting: {args.command}")
        stdout, stderr, exit_code = ssh_exec(
            gh_bin, full_name, args.command, timeout=args.timeout
        )
        print(stdout)
        if stderr:
            print(f"STDERR: {stderr}")
        print(f"\nExit code: {exit_code}")
        sys.exit(exit_code)
    else:
        print(f"\nCodespace {full_name} is ready. No command to execute.")


if __name__ == "__main__":
    main()
