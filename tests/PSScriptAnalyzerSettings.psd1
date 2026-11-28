# Settings for tests/ only. The main script is analyzed with the default rule set.
@{
    ExcludeRules = @(
        # Pester sets variables in BeforeAll that are read in It blocks. The analyzer
        # can't see across those script blocks.
        'PSUseDeclaredVarsMoreThanAssignments'
        # Kept in case a test passes a made-up computer name as a fixture.
        'PSAvoidUsingComputerNameHardcoded'
        # Kept in case a test helper builds fixture objects. Those change nothing.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
