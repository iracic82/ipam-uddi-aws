#!/usr/bin/env python3
"""
Deploy AWS VPC using CIDR allocated from Infoblox Federated IPAM.

Flow:
  1. Authenticate to CSP and switch to sandbox account
  2. Find the "AWS" federated block (parent 10.0.0.0/8)
  3. Allocate next available /24 from the AWS block
  4. Create AWS VPC with that /24
  5. Get next available /25 from the /24 for subnet
  6. Create a Reserved Block for the /24 → triggers custom-allocation in AWS IPAM
  7. Create AWS subnet with the /25
  8. Create Internet Gateway, Route Table, and associate

Prerequisites:
  - federation_output.json must exist (created by deploy_ipam.py)
  - AWS credentials configured (env vars or ~/.aws/credentials)
  - INFOBLOX_EMAIL / INFOBLOX_PASSWORD env vars set

Usage:
  python3 deploy_vpc_from_ipam.py
  python3 deploy_vpc_from_ipam.py --vpc-cidr 24 --subnet-cidr 25
  python3 deploy_vpc_from_ipam.py --dry-run
"""

import os
import re
import sys
import json
import argparse
import yaml
import requests
import boto3


def load_config_with_env(file_path):
    with open(file_path, "r") as f:
        raw_yaml = f.read()

    def replace_env(match):
        env_var = match.group(1)
        return os.environ.get(env_var, f"<MISSING:{env_var}>")

    interpolated_yaml = re.sub(r'\$\{(\w+)\}', replace_env, raw_yaml)
    return yaml.safe_load(interpolated_yaml)


class InfobloxVPCDeployer:
    def __init__(self, config_file="config.yaml"):
        config = load_config_with_env(config_file)
        self.base_url = config['base_url']
        self.email = config['email']
        self.password = config['password']
        self.sandbox_id_file = config['sandbox_id_file']
        self.jwt = None
        self.headers = {}

    # --- Auth ---

    def authenticate(self):
        url = f"{self.base_url}/v2/session/users/sign_in"
        r = requests.post(url, json={"email": self.email, "password": self.password})
        r.raise_for_status()
        self.jwt = r.json()["jwt"]
        self.headers = {
            "Authorization": f"Bearer {self.jwt}",
            "Content-Type": "application/json"
        }
        print("✅ Logged in and JWT obtained.")

    def switch_account(self):
        with open(self.sandbox_id_file, "r") as f:
            sandbox_id = f.read().strip()
        url = f"{self.base_url}/v2/session/account_switch"
        r = requests.post(url, headers=self.headers, json={"id": f"identity/accounts/{sandbox_id}"})
        r.raise_for_status()
        self.jwt = r.json()["jwt"]
        self.headers["Authorization"] = f"Bearer {self.jwt}"
        print(f"🔁 Switched to sandbox account {sandbox_id}")

    # --- Infoblox Federation API ---

    def get_aws_block(self, block_name="AWS", output_file="federation_output.json"):
        if not os.path.exists(output_file):
            raise FileNotFoundError(f"❌ {output_file} not found. Run deploy_ipam.py first.")
        with open(output_file, "r") as f:
            data = json.load(f)
        for block in data.get("blocks", []):
            if block.get("name") == block_name:
                block_uuid = block["id"].split("/")[-1]
                print(f"📖 Found '{block_name}' block: {block.get('address')}/{block.get('cidr')} (ID: {block_uuid})")
                return block, block_uuid
        raise ValueError(f"❌ Block '{block_name}' not found in {output_file}")

    def get_realm_id(self, output_file="federation_output.json"):
        with open(output_file, "r") as f:
            data = json.load(f)
        realm_id = data.get("realm", {}).get("id")
        if not realm_id:
            raise ValueError("❌ Could not find realm.id in federation_output.json")
        return realm_id

    def find_child_block_by_name(self, name):
        """Find a federated block by name via API (e.g. 'APPS' sub-block)."""
        url = f"{self.base_url}/api/ddi/v1/federation/federated_block"
        params = {"_filter": f'name=="{name}"'}
        r = requests.get(url, headers=self.headers, params=params)
        r.raise_for_status()
        results = r.json().get("results", [])
        if not results:
            raise ValueError(f"❌ Federated block '{name}' not found via API")
        block = results[0]
        block_uuid = block["id"].split("/")[-1]
        print(f"📖 Found '{name}' block: {block.get('address')}/{block.get('cidr')} (ID: {block_uuid})")
        return block, block_uuid

    def find_federated_pool(self, pool_name=None):
        """Find federated pool by name, or return the first one."""
        url = f"{self.base_url}/api/ddi/v1/federation/federated_pool"
        params = {}
        if pool_name:
            params["_filter"] = f'name=="{pool_name}"'
        r = requests.get(url, headers=self.headers, params=params)
        r.raise_for_status()
        results = r.json().get("results", [])
        if not results:
            print("⚠️  No federated pool found, reserved block will not be linked to a pool")
            return None
        pool = results[0]
        pool_id = pool.get("id")
        print(f"📖 Found federated pool: {pool.get('name')} (ID: {pool_id})")
        return pool_id

    def list_next_available_block(self, parent_block_uuid, cidr, count=1):
        """Read-only: preview next available block without allocating."""
        url = f"{self.base_url}/api/ddi/v1/federation/federated_block/{parent_block_uuid}/next_available_federated_block"
        params = {"cidr": cidr, "count": count}
        print(f"🔍 Listing next available /{cidr} from block {parent_block_uuid}...")
        r = requests.get(url, headers=self.headers, params=params)
        r.raise_for_status()
        results = r.json().get("results", [])
        if not results:
            raise RuntimeError(f"❌ No available /{cidr} blocks found")
        block = results[0]
        print(f"✅ Next available: {block.get('address')}/{block.get('cidr')}")
        return block.get("address"), block.get("cidr")

    def allocate_federated_block(self, parent_block_uuid, cidr, name, comment=""):
        """Allocate (create) next available federated block."""
        url = f"{self.base_url}/api/ddi/v1/federation/federated_block/{parent_block_uuid}/next_available_federated_block"
        payload = {"cidr": cidr, "count": 1, "name": name, "comment": comment}
        print(f"📤 Allocating next available /{cidr} as '{name}'...")
        r = requests.post(url, headers=self.headers, json=payload)
        r.raise_for_status()
        results = r.json().get("results", [])
        if not results:
            raise RuntimeError("❌ Allocation returned no results")
        block = results[0]
        block_uuid = block["id"].split("/")[-1]
        print(f"✅ Allocated: {block.get('address')}/{block.get('cidr')} (ID: {block_uuid})")
        return block.get("address"), block.get("cidr"), block_uuid, block

    def create_reserved_block(self, address, cidr, realm_id, name, comment="", federated_pool_id=None):
        """Create reserved block → triggers custom-allocation in AWS IPAM."""
        url = f"{self.base_url}/api/ddi/v1/federation/reserved_block"
        payload = {
            "address": address,
            "cidr": cidr,
            "federated_realm": realm_id,
            "name": name,
            "comment": comment
        }
        if federated_pool_id:
            payload["federated_pool_id"] = federated_pool_id
        print(f"📤 Creating reserved block {address}/{cidr}...")
        r = requests.post(url, headers=self.headers, json=payload)
        r.raise_for_status()
        result = r.json().get("result", {})
        print(f"✅ Reserved block created: {address}/{cidr} → ID: {result.get('id')}")
        print("   ↳ Custom-allocation will appear in AWS IPAM under APPS pool")
        return result

    # --- AWS ---

    def create_aws_vpc(self, cidr_block, name):
        ec2 = boto3.client('ec2', region_name=os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1'))
        print(f"\n☁️  Creating AWS VPC with CIDR {cidr_block}...")
        resp = ec2.create_vpc(CidrBlock=cidr_block)
        vpc_id = resp['Vpc']['VpcId']
        ec2.create_tags(Resources=[vpc_id], Tags=[
            {'Key': 'Name', 'Value': name},
            {'Key': 'ManagedBy', 'Value': 'infoblox-ipam'},
            {'Key': 'Source', 'Value': 'federated-ipam-lab'}
        ])
        ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsSupport={'Value': True})
        ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsHostnames={'Value': True})
        print(f"✅ VPC created: {vpc_id} ({cidr_block})")
        return vpc_id

    def create_aws_subnet(self, vpc_id, cidr_block, name):
        ec2 = boto3.client('ec2', region_name=os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1'))
        az = os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1') + 'a'
        print(f"☁️  Creating AWS Subnet {cidr_block} in {vpc_id}...")
        resp = ec2.create_subnet(VpcId=vpc_id, CidrBlock=cidr_block, AvailabilityZone=az)
        subnet_id = resp['Subnet']['SubnetId']
        ec2.create_tags(Resources=[subnet_id], Tags=[
            {'Key': 'Name', 'Value': name},
            {'Key': 'ManagedBy', 'Value': 'infoblox-ipam'},
            {'Key': 'Source', 'Value': 'federated-ipam-lab'}
        ])
        print(f"✅ Subnet created: {subnet_id} ({cidr_block})")
        return subnet_id

    def create_aws_igw(self, vpc_id, name):
        ec2 = boto3.client('ec2', region_name=os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1'))
        print(f"☁️  Creating Internet Gateway for {vpc_id}...")
        resp = ec2.create_internet_gateway()
        igw_id = resp['InternetGateway']['InternetGatewayId']
        ec2.attach_internet_gateway(InternetGatewayId=igw_id, VpcId=vpc_id)
        ec2.create_tags(Resources=[igw_id], Tags=[
            {'Key': 'Name', 'Value': name},
            {'Key': 'ManagedBy', 'Value': 'infoblox-ipam'}
        ])
        print(f"✅ Internet Gateway created and attached: {igw_id}")
        return igw_id

    def create_aws_route_table(self, vpc_id, subnet_id, igw_id, name):
        ec2 = boto3.client('ec2', region_name=os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1'))
        print(f"☁️  Creating Route Table for {vpc_id}...")
        resp = ec2.create_route_table(VpcId=vpc_id)
        rt_id = resp['RouteTable']['RouteTableId']
        ec2.create_tags(Resources=[rt_id], Tags=[
            {'Key': 'Name', 'Value': name},
            {'Key': 'ManagedBy', 'Value': 'infoblox-ipam'}
        ])
        # Default route to IGW
        ec2.create_route(RouteTableId=rt_id, DestinationCidrBlock='0.0.0.0/0', GatewayId=igw_id)
        print(f"✅ Route Table created: {rt_id} (0.0.0.0/0 → {igw_id})")
        # Associate with subnet
        ec2.associate_route_table(RouteTableId=rt_id, SubnetId=subnet_id)
        print(f"✅ Route Table associated with subnet {subnet_id}")
        return rt_id


def main():
    parser = argparse.ArgumentParser(description="Deploy AWS VPC from Infoblox Federated IPAM")
    parser.add_argument("--vpc-cidr", type=int, default=24, help="CIDR prefix for VPC (default: 24)")
    parser.add_argument("--subnet-cidr", type=int, default=25, help="CIDR prefix for subnet (default: 25)")
    parser.add_argument("--block-name", default="AWS", help="Federated block to allocate from (default: AWS)")
    parser.add_argument("--pool-name", default=None, help="Federated pool name (auto-detected if not set)")
    parser.add_argument("--vpc-name", default="apps-vpc-from-ipam", help="Name tag for the VPC")
    parser.add_argument("--dry-run", action="store_true", help="Preview allocations without creating resources")
    args = parser.parse_args()

    deployer = InfobloxVPCDeployer()
    deployer.authenticate()
    deployer.switch_account()

    # Find the target block — try API first, fall back to federation_output.json
    try:
        block, block_uuid = deployer.find_child_block_by_name(args.block_name)
    except ValueError:
        print(f"⚠️  Block '{args.block_name}' not found via API, checking federation_output.json...")
        block, block_uuid = deployer.get_aws_block(block_name=args.block_name)
    realm_id = deployer.get_realm_id()
    pool_id = deployer.find_federated_pool(pool_name=args.pool_name)

    print(f"\n{'='*60}")
    print(f"📋 Plan: /{args.vpc_cidr} VPC + /{args.subnet_cidr} Subnet")
    print(f"   From block: {block.get('name')} ({block.get('address')}/{block.get('cidr')})")
    print(f"{'='*60}\n")

    # Step 1: Preview
    vpc_address, vpc_cidr = deployer.list_next_available_block(block_uuid, args.vpc_cidr)

    if args.dry_run:
        print(f"\n🔍 DRY RUN — Would allocate:")
        print(f"   VPC:    {vpc_address}/{vpc_cidr}")
        print(f"   Subnet: next available /{args.subnet_cidr} from above")
        print(f"   + Reserved Block (pool: {pool_id}), IGW, Route Table")
        return

    # Step 2: Allocate /24 in Infoblox from the APPS block
    alloc_addr, alloc_cidr, alloc_uuid, alloc_block = deployer.allocate_federated_block(
        block_uuid, args.vpc_cidr,
        name=f"{args.vpc_name}-block",
        comment=f"VPC block for {args.vpc_name}"
    )
    vpc_cidr_block = f"{alloc_addr}/{alloc_cidr}"

    # Step 3: Create VPC
    vpc_id = deployer.create_aws_vpc(vpc_cidr_block, name=args.vpc_name)

    # Step 4: Get next available /25 for subnet
    subnet_addr, subnet_cidr = deployer.list_next_available_block(alloc_uuid, args.subnet_cidr)
    subnet_cidr_block = f"{subnet_addr}/{subnet_cidr}"

    # Step 5: Create Reserved Block → custom-allocation in AWS IPAM APPS pool
    deployer.create_reserved_block(
        alloc_addr, alloc_cidr, realm_id,
        name=f"{args.vpc_name}-reserved",
        comment=f"Reserved for {args.vpc_name}",
        federated_pool_id=pool_id
    )

    # Step 6: Create Subnet
    subnet_id = deployer.create_aws_subnet(vpc_id, subnet_cidr_block, name=f"{args.vpc_name}-subnet")

    # Step 7: Create IGW + Route Table
    igw_id = deployer.create_aws_igw(vpc_id, name=f"{args.vpc_name}-igw")
    rt_id = deployer.create_aws_route_table(vpc_id, subnet_id, igw_id, name=f"{args.vpc_name}-rt")

    # Save output
    output = {
        "vpc": {"id": vpc_id, "cidr": vpc_cidr_block, "name": args.vpc_name},
        "subnet": {"id": subnet_id, "cidr": subnet_cidr_block},
        "igw": {"id": igw_id},
        "route_table": {"id": rt_id},
        "infoblox": {
            "federated_block_id": alloc_block.get("id"),
            "federated_block_uuid": alloc_uuid,
            "parent_block": args.block_name,
            "realm_id": realm_id,
            "federated_pool_id": pool_id
        }
    }
    with open("vpc_deployment_output.json", "w") as f:
        json.dump(output, f, indent=2)

    print(f"\n{'='*60}")
    print("🎉 VPC Deployment Complete!")
    print(f"   VPC:          {vpc_id} ({vpc_cidr_block})")
    print(f"   Subnet:       {subnet_id} ({subnet_cidr_block})")
    print(f"   IGW:          {igw_id}")
    print(f"   Route Table:  {rt_id} (0.0.0.0/0 → IGW)")
    print(f"   IPAM Block:   {alloc_block.get('id')}")
    print(f"   Reserved:     ✅ Custom-allocation in AWS IPAM")
    print(f"\n   📄 Output → vpc_deployment_output.json")
    print(f"{'='*60}")
    print("\n🔍 Next steps:")
    print("   1. AWS Console → IPAM → Pools → Check for custom-allocation")
    print("   2. Infoblox Portal → Federated IPAM → ACME Corporation realm")
    print("   3. After discovery sync (~15 min), VPC appears in Infoblox IPAM view")


if __name__ == "__main__":
    main()
