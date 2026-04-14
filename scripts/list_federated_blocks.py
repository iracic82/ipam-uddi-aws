#!/usr/bin/env python3
"""List all federated blocks in the sandbox."""
import os
import re
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

print("=== Federated Blocks ===")
r = requests.get(f"{base}/api/ddi/v1/federation/federated_block", headers=h)
for b in r.json().get("results", []):
    print(f"  {b.get('name','(no name)')}: {b.get('address')}/{b.get('cidr')}  parent={b.get('parent','none')}  pool={b.get('federated_pool_id','none')}")

print("\n=== Federated Pools ===")
r = requests.get(f"{base}/api/ddi/v1/federation/federated_pool", headers=h)
for p in r.json().get("results", []):
    print(f"  {p.get('name','(no name)')}: id={p.get('id')}  provider={p.get('provider','?')}  region={p.get('region','?')}")

print("\n=== Reserved Blocks ===")
r = requests.get(f"{base}/api/ddi/v1/federation/reserved_block", headers=h)
for rb in r.json().get("results", []):
    print(f"  {rb.get('name','(no name)')}: {rb.get('address')}/{rb.get('cidr')}  pool={rb.get('federated_pool_id','none')}")
