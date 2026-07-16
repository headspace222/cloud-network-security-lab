# Setup Guide

**Estimated time:** 40-50 minutes.

## Step 1 - Deploy the Network

```powershell
cd C:\cloud-network-security-lab
.\scripts\deploy-network.ps1 -ResourceGroupName "rg-network-security-lab" -Location "uksouth"
```

**Evidence to capture:**
- 01-network-deployed.png

## Step 2 - Verify NSG Rules in the Portal

1. Portal, Network security groups, nsg-data-subnet
2. Inbound security rules

**Evidence to capture:**
- 02-nsg-rules-portal-view.png

## Step 3 - Deploy the Private Endpoint

```powershell
.\scripts\deploy-private-endpoint.ps1 -ResourceGroupName "rg-network-security-lab" -VNetName "vnet-network-security-lab" -StorageAccountResourceGroup "rg-data-migration-lab" -StorageAccountName "stmigrationlabjane01" -Location "uksouth"
```

**Evidence to capture:**
- 03-private-endpoint-created.png

## Step 4 - Confirm Public Access Is Actually Blocked

Use an account key, not an unauthenticated or ambiguously-authenticated
request. This matters: a bare Invoke-WebRequest to the account root
returns a generic parameter error regardless of network settings, and even
Get-AzStorageContainer using your Az PowerShell session's default context
can fail with an identical 403 AuthorizationFailure due to a missing
data-plane RBAC role - completely independent of whether the network
block is actually working. Both of these looked like evidence during this
lab's build but weren't actually testing the right thing.

The clean test uses the storage account key directly - the most privileged
credential available, requiring no RBAC data role, so a rejection can only
be explained by the network control itself:

```powershell
$key = (Get-AzStorageAccountKey -ResourceGroupName "rg-data-migration-lab" -Name "stmigrationlabjane01")[0].Value
$ctxKey = New-AzStorageContext -StorageAccountName "stmigrationlabjane01" -StorageAccountKey $key
Get-AzStorageContainer -Context $ctxKey
```

Run this from your local machine (outside the VNet). A valid account key
being rejected with 403 AuthorizationFailure purely because of where the
request originated is the actual, unambiguous proof this lab set out to
demonstrate.

**Evidence to capture:**
- 04-public-access-blocked.png

## Step 5 - Confirm the Private Endpoint in the Portal

1. Portal, the storage account, Networking, Private endpoint connections
2. Confirm the connection shows as Approved

**Evidence to capture:**
- 05-private-endpoint-portal-view.png

## Step 6 - Push

```powershell
cd C:\cloud-network-security-lab
git init
git add -A
git commit -m "Initial build: segmented VNet, least-privilege NSGs, Private Endpoint"
git branch -M main
git remote add origin https://github.com/headspace222/cloud-network-security-lab.git
git push -u origin main
```