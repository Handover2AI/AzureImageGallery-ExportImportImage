# Copy Azure Shared Image Gallery Image Version Across Tenants

This script copies an existing image version from an Azure Shared Image Gallery in one tenant/subscription to another gallery in a different tenant/subscription. It uses a temporary managed disk and AzCopy to move the underlying VHD and then creates a new image version in the target gallery.

## Features

- Uses **SAS URLs** and **AzCopy** for efficient disk transfer.
- Supports **cross-tenant** and **cross-subscription** scenarios.
- Creates a **new image version** in an existing target image definition.
- Updates disk properties (e.g., accelerated networking) to match image requirements.

## Prerequisites

- PowerShell with the **Az** modules installed.
- **AzCopy** installed and available in your `PATH`.
- Permissions in both source and target subscriptions to:
  - Read Shared Image Gallery image versions.
  - Create and manage managed disks.
  - Create image versions in the target gallery.
- Network access to Azure Storage endpoints used by managed disks.

## Parameters

The script is parameterized. Key parameters:

- `SourceSubscriptionId`, `SourceResourceGroup`, `SourceGalleryName`, `SourceImageDefinitionName`, `SourceImageVersionName`, `SourceLocation`
- `TargetSubscriptionId`, `TargetResourceGroup`, `TargetGalleryName`, `TargetImageDefinitionName`, `TargetImageVersionName`, `TargetLocation`
- Optional: `LocalVhdPath`, `SourceTempDiskName`, `TargetTempDiskName`, `SasDurationInSeconds`

## Usage

```powershell
.\Copy-AzGalleryImageVersionAcrossTenants.ps1 `
    -SourceSubscriptionId "00000000-0000-0000-0000-000000000000" `
    -SourceResourceGroup "rg-source-gallery" `
    -SourceGalleryName "sig-source" `
    -SourceImageDefinitionName "win2022-base" `
    -SourceImageVersionName "1.0.0" `
    -SourceLocation "westeurope" `
    -TargetSubscriptionId "11111111-1111-1111-1111-111111111111" `
    -TargetResourceGroup "rg-target-gallery" `
    -TargetGalleryName "sig-target" `
    -TargetImageDefinitionName "win2022-base" `
    -TargetImageVersionName "1.0.1" `
    -TargetLocation "westeurope"
