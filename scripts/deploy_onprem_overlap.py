#!/usr/bin/env python3
"""
Deploy on-prem IP spaces to Infoblox CSP via Terraform.
Uses data sources to lookup realm - no need to pass realm_id.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TERRAFORM_DIR = os.path.join(SCRIPT_DIR, "..", "terraform", "infoblox-onprem")


def run_terraform():
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

    print("🚀 Applying Terraform (creating on-prem IP spaces)...")
    subprocess.run([
        "terraform", "apply",
        "-auto-approve",
        f"-var=ddi_api_key={api_key}"
    ], check=True)

    print("✅ On-prem IP spaces created successfully!")


if __name__ == "__main__":
    run_terraform()
