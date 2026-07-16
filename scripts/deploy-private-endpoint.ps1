<#
.SYNOPSIS
    Creates a Private Endpoint for an existing storage account inside the
    data subnet, wires up Private DNS resolution, then disables public
    network access on the storage account entirely.

.PARAMETER ResourceGroupName
    Resource group containing the VNet.

.PARAMETER VNetName
    Name of the VNet.

.PARAMETER StorageAccountResourceGroup
    Resource group containing the target storage account.

.PARAMETER StorageAccountName
    Name of the storage account to lock down.

.PARAMETER DataSubnetName
    Name of the subnet the Private Endpoint should live in.

.PARAMETER Location
    Azure region.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$VNetName,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [string]$DataSubnetName = "snet-data",

    [string]$Location = "uksouth"
)

$tags = @{CostCenter="LAB001"; Owner="jane"; Environment="NonProduction"}

Write-Host "Step 1: Retrieving VNet and data subnet ..." -ForegroundColor Cyan
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName
$dataSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $DataSubnetName }
if (-not $dataSubnet) {
    Write-Host "  [FAILED] Subnet '$DataSubnetName' not found in VNet '$VNetName'. Run deploy-network.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "  [OK]" -ForegroundColor Green

Write-Host "`nStep 2: Retrieving target storage account ..." -ForegroundColor Cyan
try {
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName -ErrorAction Stop
    Write-Host "  [OK] Found: $($storageAccount.StorageAccountName)" -ForegroundColor Green
} catch {
    Write-Host "  [FAILED] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`nStep 3: Creating the Private Endpoint connection ..." -ForegroundColor Cyan
try {
    $plsConnection = New-AzPrivateLinkServiceConnection `
        -Name "pe-connection-$StorageAccountName" `
        -PrivateLinkServiceId $storageAccount.Id `
        -GroupId "blob" `
        -ErrorAction Stop

    $pe = New-AzPrivateEndpoint `
        -ResourceGroupName $ResourceGroupName `
        -Name "pe-$StorageAccountName" `
        -Location $Location `
        -Subnet $dataSubnet `
        -PrivateLinkServiceConnection $plsConnection `
        -Tag $tags `
        -ErrorAction Stop
    Write-Host "  [OK] Private Endpoint created: pe-$StorageAccountName" -ForegroundColor Green
} catch {
    Write-Host "  [FAILED] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Fallback: Portal -> the storage account -> Networking -> Private endpoint connections -> + Private endpoint." -ForegroundColor Yellow
    throw
}

Write-Host "`nStep 4: Creating and linking the Private DNS zone (required for name resolution) ..." -ForegroundColor Cyan
try {
    $zoneName = "privatelink.blob.core.windows.net"
    $zone = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $zoneName -ErrorAction SilentlyContinue
    if (-not $zone) {
        $zone = New-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $zoneName -ErrorAction Stop
        Write-Host "  [OK] Private DNS zone created." -ForegroundColor Green
    } else {
        Write-Host "  [OK] Private DNS zone already exists." -ForegroundColor Green
    }

    New-AzPrivateDnsVirtualNetworkLink `
        -ResourceGroupName $ResourceGroupName `
        -ZoneName $zoneName `
        -Name "link-to-$VNetName" `
        -VirtualNetworkId $vnet.Id `
        -ErrorAction Stop | Out-Null
    Write-Host "  [OK] DNS zone linked to VNet." -ForegroundColor Green

    $dnsConfig = New-AzPrivateDnsZoneConfig -Name "config1" -PrivateDnsZoneId $zone.ResourceId
    New-AzPrivateDnsZoneGroup `
        -ResourceGroupName $ResourceGroupName `
        -PrivateEndpointName $pe.Name `
        -Name "default" `
        -PrivateDnsZoneConfig $dnsConfig `
        -ErrorAction Stop | Out-Null
    Write-Host "  [OK] DNS zone group created - the Private Endpoint's IP will auto-register in DNS." -ForegroundColor Green
} catch {
    Write-Host "  [FAILED] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Fallback: Portal -> the Private Endpoint -> DNS configuration -> Add configuration." -ForegroundColor Yellow
    Write-Host "  The Private Endpoint itself (Step 3) still succeeded even if DNS setup fails here." -ForegroundColor Yellow
}

Write-Host "`nStep 5: Disabling public network access on the storage account ..." -ForegroundColor Cyan
try {
    Set-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName -PublicNetworkAccess Disabled -ErrorAction Stop | Out-Null
    Write-Host "  [OK] Public network access disabled - the storage account is now reachable only via the Private Endpoint." -ForegroundColor Green
} catch {
    Write-Host "  [FAILED] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Fallback: Portal -> the storage account -> Networking -> Public network access -> Disabled -> Save." -ForegroundColor Yellow
    throw
}

Write-Host "`nSetup complete. Verifying final state ..." -ForegroundColor Cyan
Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName | Select-Object StorageAccountName, PublicNetworkAccess