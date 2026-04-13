import os
import sys
from sandbox_api import SandboxAccountAPI

# Configuration
BASE_URL = "https://csp.infoblox.com/v2"
TOKEN = os.environ.get('Infoblox_Token')
SANDBOX_ID_FILE = "sandbox_id.txt"

# Read sandbox ID from file
if not os.path.exists(SANDBOX_ID_FILE):
    print("⚠️ sandbox_id.txt not found, nothing to delete.")
    sys.exit(0)

with open(SANDBOX_ID_FILE, "r") as f:
    sandbox_id = f.read().strip()

if not sandbox_id:
    print("⚠️ sandbox_id.txt is empty, nothing to delete.")
    sys.exit(0)

if not TOKEN:
    print("❌ Infoblox_Token environment variable not set")
    sys.exit(1)

print(f"🗑️  Deleting sandbox: {sandbox_id}")

# API client initialization
api = SandboxAccountAPI(base_url=BASE_URL, token=TOKEN)
delete_response = api.delete_sandbox_account(sandbox_id)

if delete_response["status"] == "success":
    print(f"✅ Sandbox {sandbox_id} deleted successfully.")

    # Clean up local files
    for filename in ["sandbox_id.txt", "external_id.txt", "sfdc_account_id.txt", "sandbox_env.sh"]:
        if os.path.exists(filename):
            os.remove(filename)
            print(f"🧹 Removed {filename}")
else:
    print(f"❌ Sandbox deletion failed: {delete_response.get('error', 'unknown error')}")
    sys.exit(1)
