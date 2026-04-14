#!/usr/bin/env python3
"""Test GET next_available_federated_block on the APPS 10.10.0.0/16 block."""
import os
import re
import yaml
import requests

def load_config_with_env(file_path):
    with open(file_path, "r") as f:
        raw_yaml = f.read()
    def replace_env(match):
        return os.environ.get(match.group(1), "")
    return yaml.safe_load(re.sub(r'\$\{(\w+)\}', replace_env, raw_yaml))

config = load_config_with_env("config.yaml")
base = config["base_url"]

with open(config["sandbox_id_file"]) as f:
    sid = f.read().strip()

r = requests.post(f"{base}/v2/session/users/sign_in", json={"email": config["email"], "password": config["password"]})
jwt = r.json()["jwt"]
h = {"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"}
r = requests.post(f"{base}/v2/session/account_switch", headers=h, json={"id": f"identity/accounts/{sid}"})
jwt = r.json()["jwt"]
h["Authorization"] = f"Bearer {jwt}"

# Find the 10.10.0.0/16 block (APPS pool block)
r = requests.get(f"{base}/api/ddi/v1/federation/federated_block", headers=h)
apps_block = None
for b in r.json().get("results", []):
    if b.get("address") == "10.10.0.0" and b.get("cidr") == 16:
        apps_block = b
        break

if not apps_block:
    print("❌ 10.10.0.0/16 block not found")
    exit(1)

block_uuid = apps_block["id"].split("/")[-1]
print(f"Found 10.10.0.0/16 block: {block_uuid}")
print(f"  pool: {apps_block.get('federated_pool_id')}")
print()

# Test 1: GET next_available_federated_block
print("=== Test 1: GET next_available_federated_block ===")
r = requests.get(f"{base}/api/ddi/v1/federation/federated_block/{block_uuid}/next_available_federated_block", headers=h, params={"cidr": 24, "count": 1})
print(f"  Status: {r.status_code}")
if r.ok:
    print(f"  Result: {r.json()}")
else:
    print(f"  Error: {r.text[:300]}")

print()

# Test 2: GET next_available_reserved_block
print("=== Test 2: GET next_available_reserved_block ===")
r = requests.get(f"{base}/api/ddi/v1/federation/federated_block/{block_uuid}/next_available_reserved_block", headers=h, params={"cidr": 24, "count": 1})
print(f"  Status: {r.status_code}")
if r.ok:
    print(f"  Result: {r.json()}")
else:
    print(f"  Error: {r.text[:300]}")
