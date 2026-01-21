#!/usr/bin/env python3
"""
Register AWS Cloud Provider with Infoblox for Discovery.
Uses IAM Role assumption (not AWS access keys).
"""

import os
import re
import json
import yaml
import requests
import time

def load_config_with_env(file_path):
    with open(file_path, "r") as f:
        raw_yaml = f.read()

    def replace_env(match):
        env_var = match.group(1)
        return os.environ.get(env_var, f"<MISSING:{env_var}>")

    interpolated_yaml = re.sub(r'\$\{(\w+)\}', replace_env, raw_yaml)
    return yaml.safe_load(interpolated_yaml)


class AWSCloudProviderRegistrar:
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
        """Switch to sandbox account"""
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
        time.sleep(5)

    def get_role_arn(self, role_arn_file="infoblox_role_arn.txt"):
        """Get role ARN from file or construct from env var"""
        # 1. From file
        if os.path.isfile(role_arn_file):
            with open(role_arn_file, "r") as f:
                return f.read().strip()

        # 2. Construct from env var
        aws_account_id = os.environ.get("INSTRUQT_AWS_ACCOUNT_INFOBLOX_DEMO_ACCOUNT_ID")
        if aws_account_id:
            return f"arn:aws:iam::{aws_account_id}:role/infoblox_discovery"

        raise EnvironmentError("No role ARN. Create infoblox_role_arn.txt or set INSTRUQT_AWS_ACCOUNT_INFOBLOX_DEMO_ACCOUNT_ID")

    def register_provider(self, role_arn, provider_name, view_name=None):
        """Register AWS cloud provider with Infoblox"""
        url = f"{self.base_url}/api/cloud_discovery/v2/providers"

        if not view_name:
            view_name = f"{provider_name}_view"

        payload = {
            "name": provider_name,
            "provider_type": "Amazon Web Services",
            "account_preference": "single",
            "sync_interval": "15",
            "desired_state": "enabled",
            "credential_preference": {
                "credential_type": "dynamic",
                "access_identifier_type": "role_arn"
            },
            "destination_types_enabled": ["DNS"],
            "source_configs": [
                {
                    "credential_config": {
                        "access_identifier": role_arn
                    }
                }
            ],
            "additional_config": {
                "excluded_accounts": [],
                "forward_zone_enabled": False,
                "internal_ranges_enabled": False,
                "object_type": {
                    "version": 1,
                    "discover_new": True,
                    "objects": [
                        {
                            "category": {"id": "security", "excluded": False},
                            "resource_set": [{"id": "security_groups", "excluded": False}]
                        },
                        {
                            "category": {"id": "networking-basics", "excluded": False},
                            "resource_set": [
                                {"id": "internet-gateways", "excluded": False},
                                {"id": "nat-gateways", "excluded": False},
                                {"id": "transit-gateways", "excluded": False},
                                {"id": "eips", "excluded": False},
                                {"id": "route-tables", "excluded": False},
                                {"id": "network-interfaces", "excluded": False},
                                {"id": "vpn-connection", "excluded": False},
                                {"id": "vpn-gateway", "excluded": False},
                                {"id": "customer-gateways", "excluded": False},
                                {"id": "ebs-volumes", "excluded": False},
                                {"id": "directconnect-gateway", "excluded": False},
                                {"id": "s3-buckets", "excluded": False},
                                {"id": "s3-bucket-public-access-blocks", "excluded": False},
                                {"id": "s3-bucket-policies", "excluded": False}
                            ]
                        },
                        {
                            "category": {"id": "lbs", "excluded": False},
                            "resource_set": [
                                {"id": "elbs", "excluded": False},
                                {"id": "listeners", "excluded": False},
                                {"id": "target-groups", "excluded": False}
                            ]
                        },
                        {
                            "category": {"id": "compute", "excluded": False},
                            "resource_set": [{"id": "metrics", "excluded": False}]
                        },
                        {
                            "category": {"id": "ipam", "excluded": False},
                            "resource_set": [
                                {"id": "ipams", "excluded": False},
                                {"id": "scopes", "excluded": False},
                                {"id": "pools", "excluded": False}
                            ]
                        }
                    ]
                }
            },
            "destinations": [
                {
                    "destination_type": "DNS",
                    "config": {
                        "dns": {
                            "consolidated_zone_data_enabled": False,
                            "view_name": view_name,
                            "sync_type": "read_write",
                            "resolver_endpoints_sync_enabled": False
                        }
                    }
                }
            ]
        }

        print(f"Registering AWS cloud provider '{provider_name}'...")
        print(f"  Role ARN: {role_arn}")

        r = requests.post(url, headers=self.headers, json=payload)

        if r.status_code == 201:
            print("AWS cloud provider registered successfully.")
            return r.json()
        elif r.status_code == 409:
            print("Provider already exists (409 Conflict).")
            return None
        else:
            print(f"Error: {r.status_code}")
            print(f"Response: {r.text}")
            r.raise_for_status()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Register AWS Cloud Provider with Infoblox")
    parser.add_argument("--config", default="config.yaml", help="Config file path")
    parser.add_argument("--role-arn-file", default="infoblox_role_arn.txt", help="File containing role ARN")
    parser.add_argument("--name", default="AWS_Discovery", help="Provider name (alphanumeric and underscores only)")
    parser.add_argument("--sandbox", action="store_true", help="Switch to sandbox account")
    args = parser.parse_args()

    registrar = AWSCloudProviderRegistrar(args.config)
    registrar.authenticate()

    if args.sandbox:
        registrar.switch_account()

    role_arn = registrar.get_role_arn(args.role_arn_file)
    registrar.register_provider(role_arn, args.name)
