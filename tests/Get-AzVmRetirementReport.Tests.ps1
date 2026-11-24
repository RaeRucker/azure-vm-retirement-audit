#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
<#
    Resource Graph and the Az context are mocked, so these run without Azure access.
    Subscription and VM names are made up.
#>

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $root 'Get-AzVmRetirementReport.ps1')
    $script:map = Get-Content -Raw (Join-Path $root 'vm-retirement-map.json') | ConvertFrom-Json
}

Describe 'Retirement map' {
    It 'has a review date and a source link' {
        $script:map.lastReviewed | Should -Match '^\d{4}-\d{2}-\d{2}$'
        $script:map.source | Should -Match '^https://learn\.microsoft\.com/'
    }

    It 'every pattern is a valid regex' {
        foreach ($s in $script:map.series) { { [regex]::new($s.pattern) } | Should -Not -Throw -Because $s.series }
    }
}

Describe 'Get-VmSeriesStatus' {
    It 'maps <Size> to <Series>' -ForEach @(
        @{ Size = 'Standard_DS3_v2';        Series = 'Dsv2' }
        @{ Size = 'Standard_DS12_v2_Promo'; Series = 'Dsv2' }
        @{ Size = 'Standard_D2_v2';         Series = 'Dv2' }
        @{ Size = 'Standard_B2ms';          Series = 'B (v1)' }
        @{ Size = 'Standard_A4_v2';         Series = 'Av2' }
        @{ Size = 'Standard_F8s_v2';        Series = 'Fsv2' }
        @{ Size = 'Standard_GS4-8';         Series = 'Gs' }
        @{ Size = 'Standard_L8s_v2';        Series = 'Lsv2' }
        @{ Size = 'Standard_E16-4s_v3';     Series = 'Esv3' }
    ) {
        (Get-VmSeriesStatus -VmSize $Size -Map $script:map).Series | Should -Be $Series
    }

    It 'does not flag current-generation size <_>' -ForEach @('Standard_B2s_v2', 'Standard_D4s_v5', 'Standard_D4ds_v5', 'Standard_E4as_v6', 'Standard_L8s_v3') {
        Get-VmSeriesStatus -VmSize $_ -Map $script:map | Should -BeNullOrEmpty
    }

    It 'marks a series Retired once its date has passed' {
        $m = Get-VmSeriesStatus -VmSize 'Standard_DS3_v2' -Map $script:map -Today ([datetime]'2028-06-01')
        $m.Status | Should -Be 'Retired'
        $m.DaysUntilRetirement | Should -BeLessThan 0
    }
}

Describe 'Get-VmRetirementReport' {
    BeforeAll {
        Mock Invoke-ResourceGraph {
            [pscustomobject]@{ subscriptionName = 'Contoso-Prod'; resourceGroup = 'rg-app'; name = 'app-01'; type = 'microsoft.compute/virtualmachines'; location = 'eastus2'; vmSize = 'Standard_D4s_v3'; powerState = 'PowerState/running' }
            [pscustomobject]@{ subscriptionName = 'Contoso-Prod'; resourceGroup = 'rg-app'; name = 'app-02'; type = 'microsoft.compute/virtualmachines'; location = 'eastus2'; vmSize = 'Standard_DS3_v2'; powerState = 'PowerState/running' }
            [pscustomobject]@{ subscriptionName = 'Contoso-Prod'; resourceGroup = 'rg-app'; name = 'app-03'; type = 'microsoft.compute/virtualmachines'; location = 'eastus2'; vmSize = 'Standard_D4s_v5'; powerState = 'PowerState/running' }
        }
        $script:tenant = '00000000-0000-0000-0000-000000000001'
    }

    It 'excludes end-of-life series unless asked' {
        (Get-VmRetirementReport -Tenants $script:tenant -Map $script:map).Name | Should -Be @('app-02')
        (Get-VmRetirementReport -Tenants $script:tenant -Map $script:map -IncludeEndOfLife).Name | Should -Be @('app-01', 'app-02')
    }

    It 'keeps going when one tenant fails' {
        Mock Invoke-ResourceGraph { throw 'access denied' } -ParameterFilter { $Tenant -eq 'bad' }
        $rows = Get-VmRetirementReport -Tenants 'bad', $script:tenant -Map $script:map -WarningAction SilentlyContinue
        $rows.Name | Should -Be @('app-02')
    }
}

Describe 'Script' {
    It 'is read-only (no Set, New, Remove, Stop, Update or Restart calls against resources)' {
        $text = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Get-AzVmRetirementReport.ps1')
        # Set-AzContext only picks the tenant for this session.
        $text | Should -Not -Match '(Set|New|Remove|Stop|Update|Restart)-Az(?!Context)\w+'
    }
}
