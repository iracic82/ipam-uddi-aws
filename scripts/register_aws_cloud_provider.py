import os
import json
import requests

# === Configuration ===
API_URL = "https://csp.infoblox.com/api/cloud_discovery/v2/providers"
TOKEN = os.environ.get("Infoblox_Token")
ROLE_ARN_FILE = "infoblox_role_arn.txt"
PARTICIPANT_ID = os.environ.get("INSTRUQT_PARTICIPANT_ID")

# === Validate Required Inputs ===
if not TOKEN:
    raise EnvironmentError("❌ 'Infoblox_Token' environment variable is not set.")
if not PARTICIPANT_ID:
    raise EnvironmentError("❌ 'INSTRUQT_PARTICIPANT_ID' environment variable is not set.")
if not os.path.isfile(ROLE_ARN_FILE):
    raise FileNotFoundError(f"❌ IAM Role ARN file not found: {ROLE_ARN_FILE}")

# === Load Role ARN from file ===
with open(ROLE_ARN_FILE, "r") as f:
    role_arn = f.read().strip()

print(f"🔐 Using IAM Role ARN: {role_arn}")
print(f"👤 Participant ID: {PARTICIPANT_ID}")

# === Construct the payload ===
provider_name = f"AWS_Demo_{PARTICIPANT_ID}"
view_name = f"AWS_Demo_Lab_{PARTICIPANT_ID}"

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

# === HTTP Headers ===
headers = {
    "Authorization": f"Token {TOKEN}",
    "Content-Type": "application/json"
}

# === Send the POST request ===
print("🚀 Sending API request to register AWS cloud provider with Infoblox...")

response = requests.post(API_URL, headers=headers, data=json.dumps(payload))

# === Handle Response ===
try:
    response_data = response.json()
except Exception:
    response_data = {"raw": response.text}

print(f"📦 Status Code: {response.status_code}")
print("📥 Response:")
print(json.dumps(response_data, indent=2))

if response.status_code == 201:
    print("✅ AWS cloud provider registered successfully.")
elif response.status_code == 409:
    print("⚠️ Provider already exists (409 Conflict).")
else:
    print("❌ Failed to register AWS cloud provider.")
