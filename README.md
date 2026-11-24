# Azure VM Retirement Audit

A PowerShell script that finds every VM and scale set running on a VM series Microsoft is retiring, and suggests what to move each one to.

I built an audit like this to cover VM series retirements and price changes across multiple Azure environments, so each affected VM could get a specific upgrade recommendation. This version is a cleaned-up rewrite. It isn't the script I used at work.

## How it works

1. Runs one Azure Resource Graph query per tenant to pull every VM and scale set with its size and power state.
2. Matches each size against [`vm-retirement-map.json`](vm-retirement-map.json), which lists each older series, its retirement date and a suggested replacement.
3. Writes a CSV sorted by how soon each VM's series retires.

Current-generation sizes are skipped. A series past its retirement date shows as Retired.

## Run it

```powershell
Install-Module Az.Accounts, Az.ResourceGraph -Scope CurrentUser
Connect-AzAccount

./Get-AzVmRetirementReport.ps1
```

For more than one tenant, sign in to each one first and pass the IDs:

```powershell
Connect-AzAccount -Tenant <tenant-1>
Connect-AzAccount -Tenant <tenant-2>
./Get-AzVmRetirementReport.ps1 -TenantId <tenant-1>, <tenant-2>
```

Add `-IncludeEndOfLife` to also list series that have no retirement date but are already end of life.

Settings like the output folder and map path are at the top of the script. You only need Reader on the subscriptions. The script never changes anything.

Here's [sample output](examples/sample-output.csv) with made-up VMs.

## Keeping the map current

Microsoft moves retirement dates around, so the map has a `lastReviewed` date. Check it against Microsoft's [retired sizes list](https://learn.microsoft.com/azure/virtual-machines/sizes/retirement/retired-sizes-list) before you send recommendations to anyone, and update the JSON if something changed. Nothing in the script needs editing.

## Tests

```powershell
Invoke-Pester ./tests -Output Detailed
```

Resource Graph is mocked, so the tests run anywhere without Azure access. They check:

- size matching for each series, and that current-gen sizes aren't flagged
- that a series past its date shows as Retired
- that one failing tenant doesn't stop the rest
- that the script never calls anything that changes a resource

CI runs them on Windows and Linux.
