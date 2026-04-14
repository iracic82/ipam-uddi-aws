#!/usr/bin/env python3
"""
Deploy AWS VPC using CIDR allocated from Infoblox Federated IPAM.

Flow (per ENG guidance):
  1. GET next available /24 from APPS pool
  2. Create AWS VPC with that /24
  3. GET next available /25 for subnet
  4. POST reserved_block with the /24 → custom-allocation in AWS IPAM
  5. Create AWS subnet with /25
  6. Create IGW + Route Table

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

    def get_realm_id(self, output_file="federation_output.json"):
        with open(output_file, "r") as f:
            data = json.load(f)
        realm_id = data.get("realm", {}).get("id")
        if not realm_id:
            raise ValueError("❌ Could not find realm.id in federation_output.json")
        return realm_id

    def find_federated_pool(self, pool_name):
        """Find federated pool by name (substring match)."""
        url = f"{self.base_url}/api/ddi/v1/federation/federated_pool"
        r = requests.get(url, headers=self.headers)
        r.raise_for_status()
        for p in r.json().get("results", []):
            pname = p.get("name", "")
            if pname.startswith(pool_name) or pool_name in pname:
                pool_id = p.get("id")
                pool_uuid = pool_id.split("/")[-1]
                print(f"📖 Found pool '{pname}' (UUID: {pool_uuid})")
                return pool_id, pool_uuid
        available = [p.get("name") for p in r.json().get("results", [])]
        raise ValueError(f"❌ Pool '{pool_name}' not found. Available: {available}")

    def get_next_available_from_pool(self, pool_uuid, cidr, count=1):
        """GET next available federated block from a pool (read-only preview)."""
        url = f"{self.base_url}/api/ddi/v1/federation/federated_pool/{pool_uuid}/next_available_federated_block"
        params = {"cidr": cidr, "count": count}
        print(f"🔍 GET next available /{cidr} from pool {pool_uuid}...")
        r = requests.get(url, headers=self.headers, params=params)
        r.raise_for_status()
        results = r.json().get("results", [])
        if not results:
            raise RuntimeError(f"❌ No available /{cidr} blocks in pool")
        block = results[0]
        address = block.get("address")
        block_cidr = block.get("cidr")
        print(f"✅ Next available: {address}/{block_cidr}")
        return address, block_cidr

    def create_reserved_block(self, address, cidr, realm_id, name, comment=""):
        """POST reserved_block → creates custom-allocation in AWS IPAM."""
        url = f"{self.base_url}/api/ddi/v1/federation/reserved_block"
        payload = {
            "address": address,
            "cidr": cidr,
            "federated_realm": realm_id,
            "name": name,
            "comment": comment
        }
        print(f"📤 POST reserved_block {address}/{cidr}...")
        r = requests.post(url, headers=self.headers, json=payload)
        r.raise_for_status()
        result = r.json().get("result", {})
        print(f"✅ Reserved block created: {address}/{cidr} → {result.get('id')}")
        print("   ↳ Custom-allocation will appear in AWS IPAM")
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
        ec2.create_route(RouteTableId=rt_id, DestinationCidrBlock='0.0.0.0/0', GatewayId=igw_id)
        print(f"✅ Route Table created: {rt_id} (0.0.0.0/0 → {igw_id})")
        ec2.associate_route_table(RouteTableId=rt_id, SubnetId=subnet_id)
        print(f"✅ Route Table associated with subnet {subnet_id}")
        return rt_id


def main():
    parser = argparse.ArgumentParser(description="Deploy AWS VPC from Infoblox Federated IPAM")
    parser.add_argument("--vpc-cidr", type=int, default=24, help="CIDR prefix for VPC (default: 24)")
    parser.add_argument("--subnet-cidr", type=int, default=25, help="CIDR prefix for subnet (default: 25)")
    parser.add_argument("--pool-name", default="APPS", help="Federated pool name (default: APPS)")
    parser.add_argument("--vpc-name", default="apps-vpc-from-ipam", help="Name tag for the VPC")
    parser.add_argument("--dry-run", action="store_true", help="Preview without creating resources")
    args = parser.parse_args()

    deployer = InfobloxVPCDeployer()
    deployer.authenticate()
    deployer.switch_account()

    # Find APPS pool and realm
    pool_id, pool_uuid = deployer.find_federated_pool(args.pool_name)
    realm_id = deployer.get_realm_id()

    print(f"\n{'='*60}")
    print(f"📋 Plan: /{args.vpc_cidr} VPC + /{args.subnet_cidr} Subnet from {args.pool_name} pool")
    print(f"{'='*60}\n")

    # Step 1: GET next available /24 from APPS pool
    vpc_addr, vpc_cidr = deployer.get_next_available_from_pool(pool_uuid, args.vpc_cidr)
    vpc_cidr_block = f"{vpc_addr}/{vpc_cidr}"

    if args.dry_run:
        print(f"\n🔍 DRY RUN — Would allocate:")
        print(f"   VPC:    {vpc_cidr_block}")
        print(f"   Subnet: {vpc_addr}/{args.subnet_cidr}")
        print(f"   + Reserved Block, IGW, Route Table")
        return

    # Step 2: Create VPC
    vpc_id = deployer.create_aws_vpc(vpc_cidr_block, name=args.vpc_name)

    # Step 3: Subnet is /25 from the /24
    subnet_cidr_block = f"{vpc_addr}/{args.subnet_cidr}"

    # Step 4: POST reserved_block → custom-allocation in AWS IPAM
    reserved = deployer.create_reserved_block(
        vpc_addr, vpc_cidr, realm_id,
        name=f"{args.vpc_name}-reserved",
        comment=f"Reserved for {args.vpc_name} - custom allocation in AWS IPAM"
    )

    # Step 5: Create Subnet
    subnet_id = deployer.create_aws_subnet(vpc_id, subnet_cidr_block, name=f"{args.vpc_name}-subnet")

    # Step 6: Create IGW + Route Table
    igw_id = deployer.create_aws_igw(vpc_id, name=f"{args.vpc_name}-igw")
    rt_id = deployer.create_aws_route_table(vpc_id, subnet_id, igw_id, name=f"{args.vpc_name}-rt")

    # Save output
    output = {
        "vpc": {"id": vpc_id, "cidr": vpc_cidr_block, "name": args.vpc_name},
        "subnet": {"id": subnet_id, "cidr": subnet_cidr_block},
        "igw": {"id": igw_id},
        "route_table": {"id": rt_id},
        "infoblox": {
            "reserved_block_id": reserved.get("id"),
            "pool_id": pool_id,
            "realm_id": realm_id
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
    print(f"   Reserved:     {reserved.get('id')} → custom-allocation in APPS pool")
    print(f"\n   📄 Output → vpc_deployment_output.json")
    print(f"{'='*60}")
    print("\n🔍 Next steps:")
    print("   1. AWS Console → IPAM → Pools → APPS → Check for custom-allocation")
    print("   2. Infoblox Portal → Federated IPAM → ACME Corporation realm")
    print("   3. After discovery sync (~15 min), VPC appears in Infoblox IPAM view")


if __name__ == "__main__":
    main()
