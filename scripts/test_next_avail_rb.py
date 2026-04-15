#!/usr/bin/env python3
"""Test next_available_reserved_block on various blocks."""
import os
import re
import yaml
import json
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

# Auth
r = requests.post(f"{base}/v2/session/users/sign_in", json={"email": config["email"], "password": config["password"]})
jwt = r.json()["jwt"]
h = {"Authorization": f"Bearer {jwt}", "Content-Type": "application/json"}
r = requests.post(f"{base}/v2/session/account_switch", headers=h, json={"id": f"identity/accounts/{sid}"})
jwt = r.json()["jwt"]
h["Authorization"] = f"Bearer {jwt}"

# Get all blocks
r = requests.get(f"{base}/api/ddi/v1/federation/federated_block", headers=h)
blocks = r.json().get("results", [])

print("=== All Federated Blocks ===")
for b in blocks:
    name = b.get("name") or "(unnamed)"
    uuid = b["id"].split("/")[-1]
    print(f"  {name}: {b.get('address')}/{b.get('cidr')} UUID={uuid} pool={b.get('federated_pool_id','none')}")

# Test next_available_reserved_block on each block
print("\n=== Testing GET next_available_reserved_block (cidr=24) ===")
for b in blocks:
    name = b.get("name") or "(unnamed)"
    uuid = b["id"].split("/")[-1]
    url = f"{base}/api/ddi/v1/federation/federated_block/{uuid}/next_available_reserved_block"
    r = requests.get(url, headers=h, params={"cidr": 24, "count": 1})
    print(f"\n  Block: {name} ({b.get('address')}/{b.get('cidr')})")
    print(f"  GET Status: {r.status_code}")
    if r.ok:
        results = r.json().get("results", [])
        if results:
            print(f"  Result: {results[0].get('address')}/{results[0].get('cidr')}")
        else:
            print(f"  Result: empty")
    else:
        print(f"  Error: {r.text[:200]}")

# Test POST next_available_reserved_block on each block
print("\n=== Testing POST next_available_reserved_block (cidr=24) - DRY RUN listing only ===")
for b in blocks:
    name = b.get("name") or "(unnamed)"
    uuid = b["id"].split("/")[-1]

    # Only try POST on blocks with a pool (APPS-related)
    if not b.get("federated_pool_id"):
        print(f"\n  Block: {name} - skipping (no pool)")
        continue

    url = f"{base}/api/ddi/v1/federation/federated_block/{uuid}/next_available_reserved_block"
    # POST with cidr to allocate
    payload = {"cidr": 24, "count": 1, "name": "test-rb-from-api", "comment": "testing next_available_reserved_block"}
    r = requests.post(url, headers=h, json=payload)
    print(f"\n  Block: {name} ({b.get('address')}/{b.get('cidr')})")
    print(f"  POST Status: {r.status_code}")
    if r.ok:
        results = r.json().get("results", [])
        if results:
            rb = results[0]
            print(f"  Created: {rb.get('address')}/{rb.get('cidr')} ID={rb.get('id')}")
            # Clean up - delete the test reserved block
            rb_uuid = rb["id"].split("/")[-1]
            del_r = requests.delete(f"{base}/api/ddi/v1/federation/reserved_block/{rb_uuid}", headers=h)
            print(f"  Cleanup: DELETE {del_r.status_code}")
        else:
            print(f"  Result: empty")
    else:
        print(f"  Error: {r.text[:200]}")
