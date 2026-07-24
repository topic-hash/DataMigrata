#!/usr/bin/env python3
"""
setup.py - Bootstrap script for DataMigrata codespace tools.

Run this once per session to set up the environment:
  python3 setup.py --token ghp_xxx

It will:
  1. Ensure paramiko is installed
  2. Ensure the gh binary is executable
  3. Authenticate gh CLI
  4. Start the codespace if needed
  5. Print ready-to-use commands

The gh binary (v2.63.2) is a static x86_64 Linux binary — no system packages needed.
paramiko is installed via pip into the current Python environment.
SSH into the codespace is handled entirely through Python (paramiko) — no system ssh required.
"""
import subprocess
import os
import sys
import argparse
import json
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TOOLS_DIR = SCRIPT_DIR
BIN_DIR = os.path.join(TOOLS_DIR, "bin")
GH_BIN = os.path.join(BIN_DIR, "gh")
SSH_SCRIPT = os.path.join(TOOLS_DIR, "codespace_ssh.py")


def check_dependencies():
    """Check and install required dependencies."""
    print("=== Checking dependencies ===")

    # Check Python version
    py_ver = sys.version_info
    print(f"Python: {py_ver.major}.{py_ver.minor}.{py_ver.micro}")

    # Check paramiko
    try:
        import paramiko
        print(f"paramiko: {paramiko.__version__}")
    except ImportError:
        print("Installing paramiko...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "paramiko", "-q"])
        import paramiko
        print(f"paramiko: {paramiko.__version__} (installed)")

    # Check gh binary
    if os.path.isfile(GH_BIN):
        os.chmod(GH_BIN, 0o755)
        result = subprocess.run([GH_BIN, "--version"], capture_output=True, text=True)
        print(f"gh: {result.stdout.strip()}")
    else:
        print(f"WARNING: gh binary not found at {GH_BIN}")
        print("  Download it from: https://github.com/cli/cli/releases")

    # Check for system ssh (optional - not needed since we use paramiko)
    ssh_path = None
    for p in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(p, "ssh")
        if os.path.isfile(candidate):
            ssh_path = candidate
            break
    if ssh_path:
        print(f"system ssh: {ssh_path} (optional, not required)")
    else:
        print("system ssh: not found (fine — we use paramiko for SSH)")

    print()


def authenticate(token):
    """Authenticate gh CLI."""
    print("=== Authenticating gh CLI ===")
    env = {**os.environ, "GH_TOKEN": token}
    result = subprocess.run(
        [GH_BIN, "auth", "login", "--with-token"],
        input=token, capture_output=True, text=True, env=env
    )
    if result.returncode != 0:
        print(f"Auth warning: {result.stderr.strip()}")

    result = subprocess.run(
        [GH_BIN, "auth", "status"],
        capture_output=True, text=True, env=env
    )
    print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip())
    print()


def start_codespace(codespace_prefix="symmetrical-tribble"):
    """Ensure the codespace is running."""
    print(f"=== Checking codespace ===")
    token = os.environ.get("GH_TOKEN", "")
    env = {**os.environ, "GH_TOKEN": token}

    result = subprocess.run(
        [GH_BIN, "codespace", "list"],
        capture_output=True, text=True, env=env
    )

    full_name = None
    state = None
    for line in result.stdout.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 5 and codespace_prefix in parts[0]:
            full_name = parts[0]
            state = parts[4]
            break

    if not full_name:
        print(f"No codespace matching '{codespace_prefix}' found.")
        print("Available codespaces:")
        print(result.stdout)
        return None

    print(f"Codespace: {full_name} (state: {state})")

    if state in ("Shutdown", "ShuttingDown"):
        print("Starting codespace...")
        start_result = subprocess.run(
            [GH_BIN, "api", "-X", "POST",
             f"/user/codespaces/{full_name}/start"],
            capture_output=True, text=True, env=env
        )
        if start_result.returncode != 0:
            print(f"Start error: {start_result.stderr}")
            return None

        for i in range(40):
            time.sleep(5)
            cs = subprocess.run(
                [GH_BIN, "api", f"/user/codespaces/{full_name}"],
                capture_output=True, text=True, env=env
            )
            if cs.returncode == 0:
                data = json.loads(cs.stdout)
                s = data.get("state")
                if s == "Available":
                    print(f"Codespace is now Available!")
                    break
                print(f"  Waiting... state={s}")
        else:
            print("WARNING: Codespace did not start in time")

    print()
    return full_name


def print_usage(token, codespace_name):
    """Print ready-to-use commands."""
    print("=" * 60)
    print("SETUP COMPLETE - Ready to use")
    print("=" * 60)
    print()
    print("Run commands on the codespace:")
    print(f'  python3 {SSH_SCRIPT} \\')
    print(f'    --token {"<YOUR_TOKEN>" if token else "ghp_xxx"} \\')
    print(f'    --codespace {codespace_name or "<codespace>"} \\')
    print(f'    --command "cd /workspaces/DataMigrata/docker && docker compose up -d && docker compose ps"')
    print()
    print("Stop the codespace when done:")
    print(f'  GH_TOKEN={{"<YOUR_TOKEN>" if token else "ghp_xxx"}} {GH_BIN} api -X POST /user/codespaces/{codespace_name or "<name>"}/stop')
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Bootstrap the DataMigrata codespace tooling",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
This script sets up everything needed to SSH into a GitHub Codespace
without requiring any system packages (ssh, ssh-keygen, etc).

All SSH is handled via Python/paramiko through gh's --stdio transport.
        """
    )
    parser.add_argument("--token", required=True,
                        help="GitHub personal access token (needs 'codespace' scope)")
    parser.add_argument("--codespace", default="symmetrical-tribble",
                        help="Codespace name prefix to start (default: symmetrical-tribble)")
    parser.add_argument("--skip-auth", action="store_true",
                        help="Skip authentication (if already done)")
    parser.add_argument("--skip-start", action="store_true",
                        help="Skip codespace startup")

    args = parser.parse_args()

    # Set token in environment for all subsequent commands
    os.environ["GH_TOKEN"] = args.token

    print()
    check_dependencies()

    if not args.skip_auth:
        authenticate(args.token)

    cs_name = None
    if not args.skip_start:
        cs_name = start_codespace(args.codespace)

    print_usage(args.token, cs_name)


if __name__ == "__main__":
    main()
