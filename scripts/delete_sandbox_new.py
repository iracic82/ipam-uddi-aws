import os
import sys
import requests
from sandbox_api import SandboxAccountAPI

BASE_URL = "https://csp.infoblox.com/v2"
TOKEN = os.environ.get('Infoblox_Token')
SANDBOX_ID_FILE = "sandbox_id.txt"

# Read sandbox ID from file
try:
    with open(SANDBOX_ID_FILE, "r") as f:
        sandbox_id = f.read().strip()
except FileNotFoundError:
    print(f"⚠️ {SANDBOX_ID_FILE} not found, nothing to delete.")
    sys.exit(0)

if not sandbox_id:
    print("⚠️ sandbox_id.txt is empty, nothing to delete.")
    sys.exit(0)

if not TOKEN:
    print("❌ Infoblox_Token environment variable not set")
    sys.exit(1)


def delete_sandbox(api, sandbox_id):
    endpoint = f"{api.base_url}/sandbox/accounts/{sandbox_id}"
    try:
        print(f"🔗 Sending DELETE request to: {endpoint}")
        response = requests.delete(endpoint, headers=api._headers())

        if response.status_code in [200, 204]:
            print(f"🗑️ Sandbox {sandbox_id} deleted successfully.")
            return True
        else:
            print(f"❌ Failed to delete sandbox. Status: {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Error deleting sandbox: {e}")
        return False


# Run delete
api = SandboxAccountAPI(base_url=BASE_URL, token=TOKEN)
deleted = delete_sandbox(api, sandbox_id)

if deleted:
    # Clean up local files
    for filename in ["sandbox_id.txt", "external_id.txt", "sfdc_account_id.txt", "sandbox_name.txt", "sandbox_env.sh"]:
        try:
            os.remove(filename)
            print(f"🧹 Removed {filename}")
        except OSError:
            pass
else:
    print(f"⚠️ Sandbox {sandbox_id} may still exist. Please verify manually.")
    sys.exit(1)
