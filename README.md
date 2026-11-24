# Azure VM Retirement Audit

A PowerShell script that finds every VM and scale set running on a VM series Microsoft is retiring, and suggests what to move each one to.

I built an audit like this to cover VM series retirements and price changes across multiple Azure environments, so each affected VM could get a specific upgrade recommendation. This version is a cleaned-up rewrite, not the script I used at work.

## What it does

1. Pulls every VM and scale set you can see, with its size and whether it's running.
2. Checks each size against [`vm-retirement-map.json`](vm-retirement-map.json). That file lists each older VM series, when it retires and what to move to.
3. Saves a CSV of the affected VMs, sorted by which ones retire soonest.

Newer VM sizes are skipped. A series past its retirement date shows as Retired.

It only reads. It never changes, stops or resizes anything.

Here's [sample output](examples/sample-output.csv) with made-up VMs.

## Permissions

| Who | Role | Where it's assigned | Why |
|---|---|---|---|
| Whoever runs the script | Reader | Each subscription you want checked | To list the VMs and their sizes |

That's all it needs. A subscription you don't have Reader on just won't show up in the report.

## Running it

The easiest way is Azure Cloud Shell, since it already has the Azure modules installed.

### Step 1. Open Cloud Shell

1. Sign in to the Azure portal.
2. Click the **Cloud Shell** icon in the top bar. It looks like `>_`.
3. Pick **PowerShell** if it asks.

### Step 2. Get the script

```powershell
git clone https://github.com/RaeRucker/azure-vm-retirement-audit
cd azure-vm-retirement-audit
```

### Step 3. Run it

```powershell
./Get-AzVmRetirementReport.ps1
```

It checks the tenant you're signed in to and prints how many VMs are affected.

### Step 4. Download the CSV

1. In Cloud Shell, click **Manage files → Download**.
2. Enter `azure-vm-retirement-audit/output/vm-retirements-<today's date>.csv`, for example `azure-vm-retirement-audit/output/vm-retirements-2026-11-24.csv`.
3. Open it in Excel.

## Options

| What you want | Add this |
|---|---|
| Also list series with no retirement date that are already end of life | `-IncludeEndOfLife` |
| Check more than one tenant | `-TenantId <tenant 1 ID>, <tenant 2 ID>` |
| Save the CSV somewhere else | `-OutputFolder <path>` |

For more than one tenant, sign in to each one first:

```powershell
Connect-AzAccount -Tenant <tenant 1 ID>
Connect-AzAccount -Tenant <tenant 2 ID>
./Get-AzVmRetirementReport.ps1 -TenantId <tenant 1 ID>, <tenant 2 ID>
```

A tenant ID is on **Microsoft Entra ID → Overview** in that tenant.

## Running it on your own PC instead

1. Install PowerShell 7 if you don't have it.
2. Open PowerShell and run `Install-Module Az.Accounts, Az.ResourceGraph -Scope CurrentUser`.
3. Run `Connect-AzAccount` and sign in.
4. Download this repo with **Code → Download ZIP** on GitHub, unzip it, and `cd` into the folder.
5. Run `./Get-AzVmRetirementReport.ps1`. The CSV lands in the `output` folder.

## Keeping the map current

Microsoft moves retirement dates around. The map has a `lastReviewed` date at the top.

1. Before sending recommendations to anyone, open Microsoft's [retired sizes list](https://learn.microsoft.com/azure/virtual-machines/sizes/retirement/retired-sizes-list).
2. Compare it to `vm-retirement-map.json` and update any dates or replacements that changed.
3. Change `lastReviewed` to today's date.

The script itself never needs editing for this.

## If something goes wrong

| What you see | What to check |
|---|---|
| "No Azure context. Run Connect-AzAccount first." | You're not signed in. Run `Connect-AzAccount`. |
| A tenant shows a warning and is skipped | You're not signed in to that tenant, or you don't have access there. The other tenants still run. |
| A subscription you expected is missing | You don't have Reader on it. |
| 0 affected VMs | Either nothing is on an old series, or the map is out of date. Check `lastReviewed`. |

## Tests

CI runs these on Windows and Linux on every push. Azure is mocked, so they run without signing in.

```powershell
Invoke-Pester ./tests -Output Detailed
```

They check:

- that each VM size maps to the right series
- that newer sizes aren't flagged
- that a series past its date shows as Retired
- that one failing tenant doesn't stop the rest
- that the script never calls anything that changes a resource
