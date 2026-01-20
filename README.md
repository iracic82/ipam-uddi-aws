# IPAM UDDI AWS

Scripts and Terraform for the "Federated IPAM for the Hybrid Multi-Cloud Era" Instruqt lab.

## Structure

```
├── scripts/
│   ├── config.yaml              # Lab configuration (realms, blocks)
│   ├── create_sandbox.py        # Creates Infoblox sandbox
│   ├── create_user.py           # Creates lab user account
│   ├── deploy_ipam.py           # Deploys federated realm and blocks
│   └── register_aws_cloud_provider.py  # Registers AWS cloud provider
├── terraform/
│   ├── main.tf                  # AWS IPAM with Infoblox scope authority
│   ├── variables.tf             # Terraform variables
│   └── outputs.tf               # Output values
```

## AWS IPAM Integration

This lab demonstrates the AWS VPC IPAM + Infoblox Universal DDI integration using the new scope authority feature.

### Key Features
- AWS IPAM Advanced Tier with Infoblox as external authority
- Federated IPAM visibility across hybrid environments
- IP overlap detection and prevention
