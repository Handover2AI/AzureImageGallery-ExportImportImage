<#
.SYNOPSIS
    Copies an Azure Shared Image Gallery image version from one tenant/subscription
    to another as a new image version, using a temporary managed disk and AzCopy.

.DESCRIPTION
    This script:
    1. Connects to a source subscription and retrieves an existing image version.
    2. Creates a temporary managed disk from that image version.
    3. Generates a SAS URL and downloads the disk locally using AzCopy.
    4. Switches to a target subscription and creates an empty managed disk.
    5. Uploads the VHD to the target disk using AzCopy.
    6. Updates disk properties (e.g., accelerated networking).
    7. Creates a new image version in the target Shared Image Gallery.

    AzCopy must be installed and available in PATH.

.NOTES
    Author:        <Your Name>
    Created:       <Date>
    Requirements:  Az PowerShell modules, AzCopy, appropriate RBAC permissions in both tenants.

#>

[CmdletBinding()]
param(
    # Source
    [Parameter(Mandatory = $true)]
    [string]$SourceSubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$SourceResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$SourceGalleryName,

    [Parameter(Mandatory = $true)]
    [string]$SourceImageDefinitionName,

    [Parameter(Mandatory = $true)]
    [string]$SourceImageVersionName,

    [Parameter(Mandatory = $true)]
    [string]$SourceLocation,

    # Target
    [Parameter(Mandatory = $true)]
    [string]$TargetSubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$TargetResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$TargetGalleryName,

    [Parameter(Mandatory = $true)]
    [string]$TargetImageDefinitionName,

    [Parameter(Mandatory = $true)]
    [string]$TargetLocation,

    # New version name in target gallery
    [Parameter(Mandatory = $true)]
    [string]$TargetImageVersionName,

    # Local path for temporary VHD
    [Parameter(Mandatory = $false)]
    [string]$LocalVhdPath = "C:\temp\tempexportdisk.vhd",

    # Temporary disk names
    [Parameter(Mandatory = $false)]
    [string]$SourceTempDiskName = "TempExportDisk",

    [Parameter(Mandatory = $false)]
    [string]$TargetTempDiskName = "TempImportDisk",

    # SAS validity in seconds
    [Parameter(Mandatory = $false)]
    [int]$SasDurationInSeconds = 3600
)

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $dir)) {
        Write-Verbose "Creating directory: $dir"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

Write-Host "Connecting to source subscription..." -ForegroundColor Cyan
Connect-AzAccount | Out-Null
Select-AzSubscription -SubscriptionId $SourceSubscriptionId | Out-Null

Write-Host "Retrieving source image version..." -ForegroundColor Cyan
$sourceImgVer = Get-AzGalleryImageVersion `
    -ResourceGroupName $SourceResourceGroup `
    -GalleryName $SourceGalleryName `
    -GalleryImageDefinitionName $SourceImageDefinitionName `
    -Name $SourceImageVersionName

if (-not $sourceImgVer) {
    throw "Source image version not found."
}

Write-Host "Creating temporary managed disk from source image version..." -ForegroundColor Cyan
$diskConfig = New-AzDiskConfig `
    -Location $SourceLocation `
    -CreateOption FromImage `
    -GalleryImageReference @{ Id = $sourceImgVer.Id }

$tempDisk = New-AzDisk `
    -ResourceGroupName $SourceResourceGroup `
    -DiskName $SourceTempDiskName `
    -Disk $diskConfig

Write-Host "Granting read access (SAS) to source disk..." -ForegroundColor Cyan
$sas = Grant-AzDiskAccess `
    -ResourceGroupName $SourceResourceGroup `
    -DiskName $SourceTempDiskName `
    -DurationInSecond $SasDurationInSeconds `
    -Access Read

if (-not $sas.AccessSAS) {
    throw "Failed to obtain SAS URL for source disk."
}

Ensure-Directory -Path $LocalVhdPath

Write-Host "Downloading VHD using AzCopy..." -ForegroundColor Cyan
$azCopyDownloadCmd = "azcopy.exe copy `"$($sas.AccessSAS)`" `"$LocalVhdPath`""
Write-Host $azCopyDownloadCmd -ForegroundColor DarkGray
& azcopy.exe copy "$($sas.AccessSAS)" "$LocalVhdPath"
if ($LASTEXITCODE -ne 0) {
    throw "AzCopy download failed with exit code $LASTEXITCODE."
}

Write-Host "Revoking access to source disk..." -ForegroundColor Cyan
Revoke-AzDiskAccess -ResourceGroupName $SourceResourceGroup -DiskName $SourceTempDiskName | Out-Null

Write-Host "Switching to target subscription..." -ForegroundColor Cyan
Select-AzSubscription -SubscriptionId $TargetSubscriptionId | Out-Null

if (-not (Test-Path $LocalVhdPath)) {
    throw "Local VHD not found at $LocalVhdPath."
}

$vhdSize = (Get-Item $LocalVhdPath).Length

Write-Host "Creating empty managed disk in target subscription..." -ForegroundColor Cyan
$diskConfig = New-AzDiskConfig `
    -Location $TargetLocation `
    -CreateOption Upload `
    -UploadSizeInBytes $vhdSize `
    -SkuName Premium_LRS

$targetDisk = New-AzDisk `
    -ResourceGroupName $TargetResourceGroup `
    -DiskName $TargetTempDiskName `
    -Disk $diskConfig

Write-Host "Granting write access (SAS) to target disk..." -ForegroundColor Cyan
$sas = Grant-AzDiskAccess `
    -ResourceGroupName $TargetResourceGroup `
    -DiskName $TargetTempDiskName `
    -DurationInSecond $SasDurationInSeconds `
    -Access Write

if (-not $sas.AccessSAS) {
    throw "Failed to obtain SAS URL for target disk."
}

Write-Host "Uploading VHD to target disk using AzCopy..." -ForegroundColor Cyan
$azCopyUploadCmd = "azcopy.exe copy `"$LocalVhdPath`" `"$($sas.AccessSAS)`" --blob-type PageBlob"
Write-Host $azCopyUploadCmd -ForegroundColor DarkGray
& azcopy.exe copy "$LocalVhdPath" "$($sas.AccessSAS)" --blob-type PageBlob
if ($LASTEXITCODE -ne 0) {
    throw "AzCopy upload failed with exit code $LASTEXITCODE."
}

Write-Host "Revoking access to target disk..." -ForegroundColor Cyan
Revoke-AzDiskAccess -ResourceGroupName $TargetResourceGroup -DiskName $TargetTempDiskName | Out-Null

Write-Host "Updating target disk properties (e.g., accelerated networking)..." -ForegroundColor Cyan
$diskUpdateConfig = New-AzDiskUpdateConfig -AcceleratedNetwork $true
Update-AzDisk -ResourceGroupName $TargetResourceGroup -Name $TargetTempDiskName -DiskUpdate $diskUpdateConfig | Out-Null

Write-Host "Creating new image version in target gallery..." -ForegroundColor Cyan
$osDisk = @{
    Source = @{
        Id = $targetDisk.Id
    }
}

New-AzGalleryImageVersion `
    -ResourceGroupName $TargetResourceGroup `
    -GalleryName $TargetGalleryName `
    -GalleryImageDefinitionName $TargetImageDefinitionName `
    -Name $TargetImageVersionName `
    -Location $TargetLocation `
    -OSDiskImage $osDisk `
    -TargetRegion @{ Name = $TargetLocation } | Out-Null

Write-Host "Done. New image version '$TargetImageVersionName' created in target gallery." -ForegroundColor Green
