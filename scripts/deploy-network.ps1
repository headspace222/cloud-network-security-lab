<#
.SYNOPSIS
    Deploys a segmented VNet with two subnets, each protected by its own
    Network Security Group implementing least-privilege traffic rules.

.PARAMETER ResourceGroupName
    Resource group for all network resources.

.PARAMETER Location
    Azure region.

.PARAMETER VNetName
    Name of the virtual network.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [string]$Location = "uksouth",

    [string]$VNetName = "vnet-network-security-lab",

    [string]$VNetAddressPrefix = "10.20.0.0/16",

    [string]$AppSubnetPrefix = "10.20.1.0/24",

    [string]$DataSubnetPrefix = "10.20.2.0/24"
)

$tags = @{CostCenter="LAB001"; Owner="jane"; Environment="NonProduction"}

Write-Host "Step 1: Creating resource group ..." -ForegroundColor Cyan
New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $tags -Force | Out-Null
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "`nStep 2: Creating NSG for the app subnet (allow HTTPS inbound from Internet only) ..." -ForegroundColor Cyan
$nsgApp = New-AzNetworkSecurityGroup -Name "nsg-app-subnet" -ResourceGroupName $ResourceGroupName -Location $Location -Tag $tags

$nsgApp | Add-AzNetworkSecurityRuleConfig `
    -Name "Allow-HTTPS-Inbound" `
    -Priority 100 `
    -Direction Inbound `
    -Access Allow `
    -Protocol Tcp `
    -SourcePortRange "*" `
    -DestinationPortRange 443 `
    -SourceAddressPrefix Internet `
    -DestinationAddressPrefix "*" | Set-AzNetworkSecurityGroup | Out-Null
Write-Host "  [OK] nsg-app-subnet created with HTTPS-only inbound rule." -ForegroundColor Green

Write-Host "`nStep 3: Creating NSG for the data subnet (allow from app subnet only, explicit deny from Internet) ..." -ForegroundColor Cyan
$nsgData = New-AzNetworkSecurityGroup -Name "nsg-data-subnet" -ResourceGroupName $ResourceGroupName -Location $Location -Tag $tags

$nsgData | Add-AzNetworkSecurityRuleConfig `
    -Name "Allow-From-AppSubnet" `
    -Priority 100 `
    -Direction Inbound `
    -Access Allow `
    -Protocol Tcp `
    -SourcePortRange "*" `
    -DestinationPortRange "*" `
    -SourceAddressPrefix $AppSubnetPrefix `
    -DestinationAddressPrefix "*" | Out-Null

$nsgData | Add-AzNetworkSecurityRuleConfig `
    -Name "Deny-Internet-Inbound" `
    -Priority 200 `
    -Direction Inbound `
    -Access Deny `
    -Protocol "*" `
    -SourcePortRange "*" `
    -DestinationPortRange "*" `
    -SourceAddressPrefix Internet `
    -DestinationAddressPrefix "*" | Set-AzNetworkSecurityGroup | Out-Null
Write-Host "  [OK] nsg-data-subnet created: allow from app subnet, explicit deny from Internet." -ForegroundColor Green

Write-Host "`nStep 4: Creating subnets and associating NSGs ..." -ForegroundColor Cyan
$appSubnet = New-AzVirtualNetworkSubnetConfig -Name "snet-app" -AddressPrefix $AppSubnetPrefix -NetworkSecurityGroup $nsgApp
$dataSubnet = New-AzVirtualNetworkSubnetConfig -Name "snet-data" -AddressPrefix $DataSubnetPrefix -NetworkSecurityGroup $nsgData

Write-Host "`nStep 5: Creating the VNet ..." -ForegroundColor Cyan
$vnet = New-AzVirtualNetwork `
    -Name $VNetName `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix $VNetAddressPrefix `
    -Subnet $appSubnet, $dataSubnet `
    -Tag $tags

Write-Host "`nVerifying ..." -ForegroundColor Green
$vnet.Subnets | Select-Object Name, AddressPrefix, @{Name="NSG"; Expression={($_.NetworkSecurityGroup.Id -split '/')[-1]}}

Write-Host "`nNetwork deployed. Next: run deploy-private-endpoint.ps1 to lock down a storage account behind this network." -ForegroundColor Cyan