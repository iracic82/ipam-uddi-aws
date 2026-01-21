#!/usr/bin/env python3
"""
Create AWS Discovery Job using IAM Role (Principal + External ID).

This script creates a discovery job that uses AWS IAM role assumption
instead of AWS access keys. More secure for production use.

Prerequisites:
1. Run get_infoblox_identity.py to get the external_id
2. Create AWS IAM role with trust policy allowing Infoblox to assume it
3. Configure the role ARN in this script or config

AWS IAM Role Trust Policy should look like:
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::418668170506:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "<external_id from get_infoblox_identity.py>"
                }
            }
        }
    ]
}
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


class DiscoveryJobCreator:
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

    def get_external_id(self):
        """Get external ID from current user for IAM trust policy"""
        url = f"{self.base_url}/v2/current_user"
        r = requests.get(url, headers=self.headers)
        r.raise_for_status()
        user = r.json().get("result", {})
        external_id = user.get("id")
        print(f"External ID for IAM trust: {external_id}")
        return external_id

    def create_discovery_job(self, role_arn, regions, job_name="AWS-Discovery-IAM"):
        """
        Create AWS discovery job using IAM role assumption.

        Args:
            role_arn: AWS IAM role ARN that Infoblox will assume
            regions: List of AWS regions to discover (e.g., ["eu-west-1", "eu-west-2"])
            job_name: Name for the discovery job
        """
        url = f"{self.base_url}/api/infra/v1/csp_job"

        # Build region configs
        region_configs = [{"region": r} for r in regions]

        payload = {
            "name": job_name,
            "description": "AWS Discovery using IAM Role assumption",
            "cloud_type": "aws",
            "cloud_credential_id": None,  # Not using stored credentials
            "connection_type": "assume_role",
            "cloud_connection_parameters": {
                "role_arn": role_arn,
                "region_configs": region_configs
            },
            "job_type": "discovery",
            "schedule": {
                "frequency": "DAILY",
                "time": "02:00"
            },
            "enabled": True
        }

        print(f"Creating discovery job '{job_name}'...")
        print(f"  Role ARN: {role_arn}")
        print(f"  Regions: {regions}")

        r = requests.post(url, headers=self.headers, json=payload)

        if not r.ok:
            print(f"Error: {r.status_code}")
            print(f"Response: {r.text}")
            r.raise_for_status()

        result = r.json().get("result", {})
        job_id = result.get("id")
        print(f"Created discovery job: {job_name} -> ID: {job_id}")

        return result

    def list_discovery_jobs(self):
        """List existing discovery jobs"""
        url = f"{self.base_url}/api/infra/v1/csp_job"
        r = requests.get(url, headers=self.headers)
        r.raise_for_status()
        jobs = r.json().get("results", [])
        return jobs


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Create AWS Discovery Job using IAM Role")
    parser.add_argument("--config", default="config.yaml", help="Config file path")
    parser.add_argument("--role-arn", required=True, help="AWS IAM Role ARN for Infoblox to assume")
    parser.add_argument("--regions", default="eu-west-1", help="Comma-separated AWS regions (default: eu-west-1)")
    parser.add_argument("--name", default="AWS-Discovery-IAM", help="Discovery job name")
    parser.add_argument("--sandbox", action="store_true", help="Switch to sandbox account")
    parser.add_argument("--show-external-id", action="store_true", help="Show external ID for IAM trust policy")
    args = parser.parse_args()

    creator = DiscoveryJobCreator(args.config)
    creator.authenticate()

    if args.sandbox:
        creator.switch_account()

    if args.show_external_id:
        external_id = creator.get_external_id()
        print("\n" + "="*60)
        print("Use this External ID in your AWS IAM Role trust policy:")
        print("="*60)
        print(f"\n  {external_id}\n")
        print("="*60)
    else:
        regions = [r.strip() for r in args.regions.split(",")]
        creator.create_discovery_job(
            role_arn=args.role_arn,
            regions=regions,
            job_name=args.name
        )
