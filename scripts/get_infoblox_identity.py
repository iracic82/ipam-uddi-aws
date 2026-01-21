#!/usr/bin/env python3
"""
Fetch Infoblox Identity Information for AWS Integration.

Returns:
- account_infoblox_id (Blox-ID): Used for AWS IPAM scope external authority
- user id (External-ID): Used for AWS IAM role trust policy
- account_csp_id: CSP account ID

These values are needed for:
1. Setting up AWS IPAM scope with Infoblox as external authority
2. Creating AWS IAM role for discovery job (trust policy)
"""

import os
import re
import json
import yaml
import requests

def load_config_with_env(file_path):
    with open(file_path, "r") as f:
        raw_yaml = f.read()

    def replace_env(match):
        env_var = match.group(1)
        return os.environ.get(env_var, f"<MISSING:{env_var}>")

    interpolated_yaml = re.sub(r'\$\{(\w+)\}', replace_env, raw_yaml)
    return yaml.safe_load(interpolated_yaml)


class InfobloxIdentity:
    def __init__(self, config_file="config.yaml"):
        config = load_config_with_env(config_file)

        self.base_url = config['base_url']
        self.email = config['email']
        self.password = config['password']
        self.sandbox_id_file = config.get('sandbox_id_file')
        self.jwt = None
        self.headers = {}

    def authenticate(self):
        """Login and get JWT token"""
        url = f"{self.base_url}/v2/session/users/sign_in"
        payload = {"email": self.email, "password": self.password}
        r = requests.post(url, json=payload)
        r.raise_for_status()
        self.jwt = r.json()["jwt"]
        self.headers = {
            "Authorization": f"Bearer {self.jwt}",
            "Content-Type": "application/json"
        }
        print("Logged in and JWT obtained.")

    def switch_account(self):
        """Switch to sandbox account if configured"""
        if not self.sandbox_id_file or not os.path.exists(self.sandbox_id_file):
            print("No sandbox configured, using main account.")
            return

        with open(self.sandbox_id_file, "r") as f:
            sandbox_id = f.read().strip()
        url = f"{self.base_url}/v2/session/account_switch"
        payload = {"id": f"identity/accounts/{sandbox_id}"}
        r = requests.post(url, headers=self.headers, json=payload)
        r.raise_for_status()
        self.jwt = r.json()["jwt"]
        self.headers["Authorization"] = f"Bearer {self.jwt}"
        print(f"Switched to sandbox account {sandbox_id}")

    def get_current_user(self):
        """Fetch current user info including Blox-ID and External-ID"""
        url = f"{self.base_url}/v2/current_user"
        r = requests.get(url, headers=self.headers)
        r.raise_for_status()
        return r.json().get("result", {})

    def get_identity_info(self):
        """Extract AWS integration relevant identity info"""
        user = self.get_current_user()

        identity = {
            "blox_id": user.get("account_infoblox_id"),
            "external_id": user.get("id"),
            "account_id": user.get("account_id"),
            "account_csp_id": user.get("account_csp_id"),
            "csp_id": user.get("csp_id")
        }

        return identity

    def save_output(self, identity, filename="identity_output.json"):
        """Save identity info to JSON file"""
        with open(filename, "w") as f:
            json.dump(identity, f, indent=2)
        print(f"Output saved to {filename}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Fetch Infoblox identity for AWS integration")
    parser.add_argument("--config", default="config.yaml", help="Config file path")
    parser.add_argument("--output", default="identity_output.json", help="Output file path")
    parser.add_argument("--sandbox", action="store_true", help="Switch to sandbox account")
    args = parser.parse_args()

    client = InfobloxIdentity(args.config)
    client.authenticate()

    if args.sandbox:
        client.switch_account()

    identity = client.get_identity_info()

    print("\n" + "="*60)
    print("Infoblox Identity for AWS Integration")
    print("="*60)
    print(f"\nBlox-ID (for AWS IPAM scope):")
    print(f"  {identity['blox_id']}")
    print(f"\nExternal-ID (for AWS IAM trust policy):")
    print(f"  {identity['external_id']}")
    print(f"\nAccount CSP ID:")
    print(f"  {identity['account_csp_id']}")
    print()

    client.save_output(identity, args.output)
