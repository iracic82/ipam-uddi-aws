#!/usr/bin/env python3
"""
Create a Federated Pool in Infoblox CSP.
Reads realm ID from federation_output.json (created by deploy_ipam.py)
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


class FederatedPoolCreator:
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

    def get_realm_id(self, output_file="federation_output.json"):
        """Read realm ID from federation_output.json"""
        if not os.path.exists(output_file):
            raise FileNotFoundError(f"❌ {output_file} not found. Run deploy_ipam.py first.")

        with open(output_file, "r") as f:
            data = json.load(f)

        realm_id = data.get("realm", {}).get("id")
        if not realm_id:
            raise ValueError("❌ Could not find realm.id in federation_output.json")

        print(f"📖 Found realm ID: {realm_id}")
        return realm_id

    def create_federated_pool(self, realm_id, pool_name="source-pool", protocol="ip4", provider="NIOS_X"):
        """Create a federated pool"""
        url = f"{self.base_url}/api/ddi/v1/federation/federated_pool"
        payload = {
            "federated_realm": realm_id,
            "name": pool_name,
            "protocol": protocol,
            "provider": provider
        }

        print(f"📤 Creating federated pool '{pool_name}'...")
        r = requests.post(url, headers=self.headers, json=payload)
        r.raise_for_status()

        result = r.json().get("result", {})
        pool_id = result.get("id")
        print(f"✅ Created federated pool: {pool_name} → ID: {pool_id}")

        # Save to output file
        output = {
            "federated_pool": result,
            "realm_id": realm_id
        }
        with open("federated_pool_output.json", "w") as f:
            json.dump(output, f, indent=2)
        print(f"📄 Output saved to federated_pool_output.json")

        return result


if __name__ == "__main__":
    creator = FederatedPoolCreator()
    creator.authenticate()
    creator.switch_account()
    realm_id = creator.get_realm_id()
    creator.create_federated_pool(realm_id, pool_name="source-pool")
