# Azure VM Retirement Audit

A PowerShell script that finds every VM and scale set running on a VM series Microsoft is retiring, and suggests what to move each one to.

It only reads. It never changes, stops or resizes anything.

## What it does

1. Pulls every VM and scale set you can see, with its size and whether it's running.
2. Checks each size against [`vm-retirement-map.json`](vm-retirement-map.json). That file lists each older VM series, when it retires and what to move to.
3. Saves a CSV of the affected VMs, sorted by which ones retire soonest.

Current VM sizes are skipped. A series past its retirement date shows as Retired.

Here's [sample output](examples/sample-output.csv) with made-up VMs.

| Column | What it shows |
|---|---|
| `Series` | The VM series the size belongs to, like Dsv2 |
| `Status` | Retiring, Retired, or EndOfLife |
| `RetirementDate` | The date Microsoft retires the series |
| `DaysUntilRetirement` | Days from today. Negative means it's already retired. |
| `SuggestedReplacement` | Series to move to |

Microsoft puts Dv3, Dsv3, Ev3 and Esv3 in a separate End of Life stage. They retire later than the rest, on November 15, 2029. The map marks them EndOfLife, and they're left out unless you add `-IncludeEndOfLife`.

## Permissions

| Who | Role | Where it's assigned | Why |
|---|---|---|---|
| Whoever runs the script | Reader | Each subscription you want checked | To list the VMs and their sizes |

That's all it needs. A subscription you don't have Reader on won't show up in the report.

## What to change for your environment

Nothing has to be changed. It checks the tenant you're signed in to by default. These are optional, and you add them to the command when you run it. They're also listed in the settings block at the top of `Get-AzVmRetirementReport.ps1`.

| Setting | What to put in |
|---|---|
| `-TenantId` | Tenant IDs to check, separated by commas, like `00000000-0000-0000-0000-000000000000`. Leave it off to use the tenant you're signed in to. A tenant ID is on Microsoft Entra ID → Overview in that tenant. |
| `-IncludeEndOfLife` | Add it to also list Dv3, Dsv3, Ev3 and Esv3 VMs. |
| `-OutputFolder` | Folder for the CSV. Default is `output` next to the script. |
| `-MapPath` | Path to a different series map. Default is `vm-retirement-map.json` next to the script. |

## Setup

Azure Cloud Shell is the easiest way to run it. It already has the Azure modules, so nothing needs installing.

### Step 1. Open Cloud Shell

1. Sign in to the Azure portal.
2. Click the Cloud Shell icon in the top bar. It looks like `>_`.
3. Pick PowerShell if it asks.
4. If it asks about storage, pick No storage account required, choose a subscription, and click Apply.

You should see a `PS /home/<your name>>` prompt.

### Step 2. Get the script

```powershell
git clone https://github.com/RaeRucker/azure-vm-retirement-audit
cd azure-vm-retirement-audit
```

### Step 3. Run it

```powershell
./Get-AzVmRetirementReport.ps1
```

When it finishes it prints a line like `3 affected VMs. Map last reviewed 2026-11-27.` followed by the path to the CSV.

### Step 4. Download the CSV

1. In Cloud Shell, click Manage files → Download.
2. Enter `azure-vm-retirement-audit/output/vm-retirements-<today's date>.csv`, for example `azure-vm-retirement-audit/output/vm-retirements-2026-11-27.csv`.
3. Click Download and open the file in Excel.

Without a storage account, Cloud Shell files are deleted when the session ends. Download the CSV before you close it.

## Checking more than one tenant

Sign in to each tenant first, then pass all the IDs:

```powershell
Connect-AzAccount -Tenant <tenant 1 ID>
Connect-AzAccount -Tenant <tenant 2 ID>
./Get-AzVmRetirementReport.ps1 -TenantId <tenant 1 ID>, <tenant 2 ID>
```

If one tenant fails, it shows a warning and the rest still run.

## Running it on your own PC instead

1. Install PowerShell 7 if you don't have it.
2. Open PowerShell and run `Install-Module Az.Accounts, Az.ResourceGraph -Scope CurrentUser`.
3. Run `Connect-AzAccount` and sign in.
4. Download this repo with Code → Download ZIP on GitHub, unzip it, and `cd` into the folder.
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
| Dv3 or Esv3 VMs aren't in the CSV | They're left out by default. Add `-IncludeEndOfLife`. |
| The download in step 4 says the file isn't found | Check the date in the file name. It's the day the script ran, in `yyyy-MM-dd` format. |

## How it's built

```text
For each tenant
  └─ Resource Graph query, 1,000 rows per page
       └─ each VM size → match against vm-retirement-map.json
            └─ affected VMs → sort by days left → CSV
```

A few choices worth explaining:

- Resource Graph returns every VM in every subscription in one query, so there's no loop through subscriptions with `Get-AzVM`.
- The series list lives in a JSON file so dates can change without touching the script.
- Each series is matched with a regular expression on the size name, like `Standard_DS3_v2`. Sizes that match nothing are current and get skipped.
- `Set-AzContext` is the only `Set-` command in the script. It picks which tenant to query and changes nothing in Azure.

## Files

| File | What it is |
|---|---|
| `Get-AzVmRetirementReport.ps1` | The script. Settings are at the top. |
| `vm-retirement-map.json` | Each retiring series, its date, its size pattern and what to move to. Edit this when Microsoft changes a date. |
| `examples/sample-output.csv` | Sample report with made-up VMs. |
| `tests/Get-AzVmRetirementReport.Tests.ps1` | Pester tests. |
| `tests/PSScriptAnalyzerSettings.psd1` | Analyzer rules turned off for the tests folder only. |
| `.github/workflows/ci.yml` | The CI checks below. |

## Tests

CI runs on every push to main and on every pull request. It fails if any of these happen:

- PSScriptAnalyzer finds a warning or error in the script or the tests
- a Pester test fails on Windows or Linux
- gitleaks finds a secret

Azure is mocked in the tests, so they run without signing in. To run them yourself:

```powershell
Invoke-Pester ./tests -Output Detailed
```

They check:

- that the map has a review date, a source link and valid patterns
- that each VM size maps to the right series
- that current sizes aren't flagged
- that a series past its date shows as Retired
- that end-of-life series are left out unless asked for
- that one failing tenant doesn't stop the rest
- that the script never calls anything that changes a resource

## Known gaps

- The map is kept up to date by hand. If `lastReviewed` is old, the dates may be wrong.
- A retiring series that isn't in the map won't be flagged.
- The dates are for global Azure. Microsoft says the Dv3, Dsv3, Ev3 and Esv3 retirement doesn't apply to Azure Government or Azure operated by 21Vianet.
- Scale sets show as one row with no power state. The CSV doesn't say how many instances each one has.
