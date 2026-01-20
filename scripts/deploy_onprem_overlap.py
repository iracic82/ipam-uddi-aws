#!/usr/bin/env python3
"""
Deploy on-prem overlapping IP blocks to Infoblox CSP via Terraform.
Reads realm_id from federation_output.json (created by deploy_ipam.py)
"""

import os
import json
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TERRAFORM_DIR = os.path.join(SCRIPT_DIR, "..", "terraform", "infoblox-onprem")
FEDERATION_OUTPUT = os.path.join(SCRIPT_DIR, "federation_output.json")


def get_realm_id():
    """Read realm_id from federation_output.json"""
    if not os.path.exists(FEDERATION_OUTPUT):
        print(f"❌ {FEDERATION_OUTPUT} not found. Run deploy_ipam.py first.")
        sys.exit(1)

    with open(FEDERATION_OUTPUT, "r") as f:
        data = json.load(f)

    realm_id = data.get("realm", {}).get("id")
    if not realm_id:
        print("❌ Could not find realm.id in federation_output.json")
        sys.exit(1)

    print(f"✅ Found realm_id: {realm_id}")
    return realm_id


def run_terraform(realm_id):
    """Initialize and apply terraform"""
    os.chdir(TERRAFORM_DIR)

    # Check for API key
    api_key = os.environ.get("TF_VAR_ddi_api_key")
    if not api_key:
        print("❌ TF_VAR_ddi_api_key not set. Run deploy_api_key.py first.")
        print("   Or: source ~/.bashrc")
        sys.exit(1)

    print("🔧 Initializing Terraform...")
    subprocess.run(["terraform", "init"], check=True)

    print("🚀 Applying Terraform (creating on-prem overlapping blocks)...")
    subprocess.run([
        "terraform", "apply",
        "-auto-approve",
        f"-var=realm_id={realm_id}",
        f"-var=ddi_api_key={api_key}"
    ], check=True)

    print("✅ On-prem overlapping blocks created successfully!")


if __name__ == "__main__":
    realm_id = get_realm_id()
    run_terraform(realm_id)
