<#
.SYNOPSIS
    Finds Azure VMs and scale sets running on retiring or end-of-life VM series. Read-only.

.DESCRIPTION
    Runs one Azure Resource Graph query per tenant, matches every VM size against
    vm-retirement-map.json, and writes a CSV with the retirement date and a suggested
    replacement series for each affected VM.

    Retirement dates change. Check the map's lastReviewed date against Microsoft's
    retired sizes list before sending recommendations to anyone.

.EXAMPLE
    ./Get-AzVmRetirementReport.ps1

    Audits the tenant you're signed in to and writes the CSV to ./output.

.EXAMPLE
    ./Get-AzVmRetirementReport.ps1 -TenantId 00000000-0000-0000-0000-000000000001, 00000000-0000-0000-0000-000000000002 -IncludeEndOfLife

    Audits two tenants. Sign in to each one first with Connect-AzAccount -Tenant <id>.

.NOTES
    Requires Az.Accounts, Az.ResourceGraph 0.13 or later, and Reader on the subscriptions.
#>
[CmdletBinding()]
param(
    # ---- Settings ----------------------------------------------------------
    # Tenants to audit. Leave empty to use the tenant you're signed in to.
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string[]] $TenantId,

    # Also list series the map marks EndOfLife (Dv3, Dsv3, Ev3, Esv3). They retire later than the rest.
    [switch] $IncludeEndOfLife,

    # Where the CSV goes.
    [string] $OutputFolder = (Join-Path $PSScriptRoot 'output'),

    # The series map. Update this file when Microsoft changes a retirement date.
    [string] $MapPath = (Join-Path $PSScriptRoot 'vm-retirement-map.json')
    # ------------------------------------------------------------------------
)

$query = @'
resources
| where type in~ ('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets')
| extend vmSize = iff(type =~ 'microsoft.compute/virtualmachines', tostring(properties.hardwareProfile.vmSize), tostring(sku.name))
| extend powerState = tostring(properties.extended.instanceView.powerState.code)
| join kind=leftouter (resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, subscriptionName = name) on subscriptionId
| project tenantId, subscriptionName, subscriptionId, resourceGroup, name, type, location, vmSize, powerState
'@

function Get-VmSeriesStatus {
    <# Matches a VM size to the map. Returns nothing for current-generation sizes. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $VmSize,
        [Parameter(Mandatory)] [object] $Map,
        [datetime] $Today = (Get-Date).Date
    )
    foreach ($s in $Map.series) {
        if ($VmSize -match "(?i)$($s.pattern)") {
            $date = if ($s.retirementDate) { [datetime]$s.retirementDate } else { $null }
            return [pscustomobject]@{
                Series               = $s.series
                Status               = if ($date -and $date -le $Today) { 'Retired' } else { $s.status }
                RetirementDate       = $date
                DaysUntilRetirement  = if ($date) { ($date - $Today).Days } else { $null }
                SuggestedReplacement = $s.suggestedReplacement
            }
        }
    }
}

function Get-CurrentTenantId {
    [CmdletBinding()]
    param()
    $ctx = Get-AzContext
    if (-not $ctx) { throw 'No Azure context. Run Connect-AzAccount first.' }
    $ctx.Tenant.Id
}

function Invoke-ResourceGraph {
    <# Runs a Resource Graph query against one tenant and follows the paging token. #>
    [CmdletBinding()]
    param([string] $Query, [string] $Tenant)
    $null = Set-AzContext -Tenant $Tenant -WarningAction SilentlyContinue -ErrorAction Stop
    $skip = $null
    do {
        $p = @{ Query = $Query; First = 1000; UseTenantScope = $true }
        if ($skip) { $p.SkipToken = $skip }
        $page = Search-AzGraph @p
        $page.Data
        $skip = $page.SkipToken
    } while ($skip)
}

function Get-VmRetirementReport {
    [CmdletBinding()]
    param([string[]] $Tenants, [object] $Map, [switch] $IncludeEndOfLife)

    $inventory = foreach ($t in $Tenants) {
        try { Invoke-ResourceGraph -Query $query -Tenant $t }
        catch { Write-Warning "Tenant ${t}: $($_.Exception.Message)" }
    }

    foreach ($vm in $inventory) {
        $match = Get-VmSeriesStatus -VmSize $vm.vmSize -Map $Map
        if (-not $match) { continue }
        if ($match.Status -eq 'EndOfLife' -and -not $IncludeEndOfLife) { continue }

        [pscustomobject]@{
            Subscription         = $vm.subscriptionName
            ResourceGroup        = $vm.resourceGroup
            Name                 = $vm.name
            ResourceType         = if ($vm.type -match 'scalesets') { 'VM Scale Set' } else { 'VM' }
            Location             = $vm.location
            PowerState           = ($vm.powerState -replace '^PowerState/', '')
            VmSize               = $vm.vmSize
            Series               = $match.Series
            Status               = $match.Status
            RetirementDate       = if ($match.RetirementDate) { $match.RetirementDate.ToString('yyyy-MM-dd') } else { '' }
            DaysUntilRetirement  = $match.DaysUntilRetirement
            SuggestedReplacement = $match.SuggestedReplacement
        }
    }
}

# Dot-sourcing (the tests do this) loads the functions without running the audit.
if ($MyInvocation.InvocationName -eq '.') { return }

$map = Get-Content -Raw -Path $MapPath | ConvertFrom-Json
$tenants = @(if ($TenantId) { $TenantId } else { Get-CurrentTenantId })

$rows = @(Get-VmRetirementReport -Tenants $tenants -Map $map -IncludeEndOfLife:$IncludeEndOfLife |
    Sort-Object DaysUntilRetirement, Subscription, Name)

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder | Out-Null }
$csv = Join-Path $OutputFolder ("vm-retirements-{0:yyyy-MM-dd}.csv" -f (Get-Date))
$rows | Export-Csv -Path $csv -NoTypeInformation -Encoding utf8

Write-Information -InformationAction Continue "$($rows.Count) affected VMs. Map last reviewed $($map.lastReviewed). Report: $csv"
$rows
