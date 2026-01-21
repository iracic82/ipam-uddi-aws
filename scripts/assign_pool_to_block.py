#!/usr/bin/env python3
"""
Assign a Federated Pool to a Federated Block in Infoblox CSP.
Reads block ID from federation_output.json and pool ID from federated_pool_output.json
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


class BlockPoolAssigner:
    def __init__(self, config_file="config.yaml"):
        config = load_config_with_env(config_file)

        self.base_url = config['base_url']
        self.email = config['email']
        self.password = config['password']
        self.sandbox_id_file = config['sandbox_id_file']
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
        print("✅ Logged in and JWT obtained.")

    def switch_account(self):
        """Switch to sandbox account"""
        with open(self.sandbox_id_file, "r") as f:
            sandbox_id = f.read().strip()
        url = f"{self.base_url}/v2/session/account_switch"
        payload = {"id": f"identity/accounts/{sandbox_id}"}
        r = requests.post(url, headers=self.headers, json=payload)
        r.raise_for_status()
        self.jwt = r.json()["jwt"]
        self.headers["Authorization"] = f"Bearer {self.jwt}"
        print(f"🔁 Switched to sandbox account {sandbox_id}")

    def get_block_info(self, block_name="AWS", output_file="federation_output.json"):
        """Read block info from federation_output.json"""
        if not os.path.exists(output_file):
            raise FileNotFoundError(f"❌ {output_file} not found. Run deploy_ipam.py first.")

        with open(output_file, "r") as f:
            data = json.load(f)

        # Find the block by name
        blocks = data.get("blocks", [])
        for block in blocks:
            if block.get("name") == block_name:
                print(f"📖 Found block '{block_name}': {block.get('id')}")
                return block

        raise ValueError(f"❌ Could not find block '{block_name}' in federation_output.json")

    def get_pool_id(self, output_file="federated_pool_output.json"):
        """Read pool ID from federated_pool_output.json"""
        if not os.path.exists(output_file):
            raise FileNotFoundError(f"❌ {output_file} not found. Run create_federated_pool.py first.")

        with open(output_file, "r") as f:
            data = json.load(f)

        pool_id = data.get("federated_pool", {}).get("id")
        if not pool_id:
            raise ValueError("❌ Could not find federated_pool.id in federated_pool_output.json")

        print(f"📖 Found pool ID: {pool_id}")
        return pool_id

    def assign_pool_to_block(self, block, pool_id):
        """PATCH the federated block to assign the pool"""
        block_id = block.get("id")
        # Extract just the UUID from the full ID path
        block_uuid = block_id.split("/")[-1]

        url = f"{self.base_url}/api/ddi/v1/federation/federated_block/{block_uuid}"

        payload = {
            "cidr": block.get("cidr"),
            "name": block.get("name"),
            "comment": block.get("comment", ""),
            "federated_realm": block.get("federated_realm"),
            "tags": block.get("tags", {}),
            "federated_pool_id": pool_id
        }

        print(f"📤 Assigning pool to block '{block.get('name')}'...")
        print(f"   Block ID: {block_uuid}")
        print(f"   Pool ID: {pool_id}")

        r = requests.patch(url, headers=self.headers, json=payload)

        if not r.ok:
            print(f"❌ Error: {r.status_code}")
            print(f"   Response: {r.text}")
            r.raise_for_status()

        result = r.json().get("result", {})
        print(f"✅ Successfully assigned pool to block '{block.get('name')}'")

        return result


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Assign federated pool to federated block")
    parser.add_argument("--block", default="AWS", help="Name of the federated block (default: AWS)")
    args = parser.parse_args()

    assigner = BlockPoolAssigner()
    assigner.authenticate()
    assigner.switch_account()

    block = assigner.get_block_info(block_name=args.block)
    pool_id = assigner.get_pool_id()
    assigner.assign_pool_to_block(block, pool_id)
