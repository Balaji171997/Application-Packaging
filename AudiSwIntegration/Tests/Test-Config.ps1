# ==============================================================================
#  Test harness for increment 1. Runs anywhere - no SCCM, no network, no rights.
#    .\Test-AudiSwIntegration.ps1
# ==============================================================================

[CmdletBinding()]
param([switch]$Quiet)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Server\Engine\AudiSwIntegration.ps1')

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:Pass++; if (-not $Quiet) { Write-Host ("  PASS  " + $Name) -ForegroundColor Green } }
    else            { $script:Fail++; Write-Host ("  FAIL  " + $Name + $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor Red }
}

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    Assert-True -Name $Name -Condition ($Expected -eq $Actual) -Detail "expected '$Expected', got '$Actual'"
}

Write-Host ''
Write-Host 'Audi SCCM Integration Tool - configuration tests' -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------- schema
Write-Host 'Schema validation' -ForegroundColor Cyan
$codes = Get-AudiEnvironmentCode
# Audi's three, plus any test site dropped in alongside them. Asserting a fixed
# count would mean editing a test to add an environment, which is the one thing
# this design promises never to need.
foreach ($required in 'ICZ', 'INA', 'PCZ') {
    Assert-True "$required is present" ($codes -contains $required) ("found: " + ($codes -join ', '))
}

foreach ($code in $codes) {
    $r = Test-AudiConfigFile -Path (Join-Path (Get-AudiEnvironmentRoot) "$code.xml")
    Assert-True "$code validates against the schema" $r.Ok ($r.Errors -join '; ')
}
$r = Test-AudiConfigFile -Path (Join-Path (Get-AudiConfigRoot) 'Defaults.xml')
Assert-True 'Defaults validates against the schema' $r.Ok ($r.Errors -join '; ')

# A validator that never rejects anything is worthless, so prove it rejects.
$broken = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiBroken_{0}.xml" -f ([guid]::NewGuid().ToString('N')))
@'
<?xml version="1.0" encoding="utf-8"?>
<Environment code="TOOLONG" description="" schemaVersion="1.0" verified="maybe">
  <Site code="XX" server=""/>
</Environment>
'@ | Set-Content -LiteralPath $broken -Encoding UTF8
try {
    $bad = Test-AudiConfigFile -Path $broken -SchemaPath (Join-Path (Get-AudiConfigRoot) 'Environment.xsd')
    Assert-True 'a deliberately broken file is rejected' (-not $bad.Ok) 'the validator accepted an invalid file'
}
finally { Remove-Item -LiteralPath $broken -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------- content
Write-Host ''
Write-Host 'Environment content' -ForegroundColor Cyan
$icz = Get-AudiEnvironment -Code 'ICZ'
$ina = Get-AudiEnvironment -Code 'INA'
$pcz = Get-AudiEnvironment -Code 'PCZ'

Assert-Equal 'ICZ collection count'  4 $icz.Collections.Count
Assert-Equal 'INA collection count'  9 $ina.Collections.Count
Assert-Equal 'PCZ collection count' 10 $pcz.Collections.Count

foreach ($e in @($icz, $ina, $pcz)) {
    $uninstall = @($e.Collections | Where-Object { $_.DeploymentAction -eq 'Uninstall' })
    Assert-True "$($e.Code) has exactly one Uninstall deployment" ($uninstall.Count -eq 1)
    Assert-True "$($e.Code) Uninstall is the _RemoveComputer collection" ($uninstall[0].Suffix -eq '_RemoveComputer')
}

Assert-Equal 'ICZ security scope count' 4 $icz.SecurityScopes.Count
Assert-Equal 'INA security scope'       'INA00003' $ina.SecurityScopes[0]
Assert-Equal 'ICZ application folder'   'ICZ-Applications' $icz.ApplicationFolder
Assert-Equal 'PCZ has two domain names' 2 $pcz.DomainNames.Count

# Regression guard for the defect this whole model exists to prevent: no
# environment may silently share another one's identifying values.
# NOTE: while testing, all three point at the same physical folder. The real
# shares differ, and this check comes back when they are restored.
Assert-True 'every environment has a content share' ($icz.ContentShare -and $ina.ContentShare -and $pcz.ContentShare)
Assert-True 'ICZ and INA do not share a security scope' (-not (Compare-Object $icz.SecurityScopes $ina.SecurityScopes -IncludeEqual -ExcludeDifferent))
Assert-True 'PCZ is flagged unverified'                 (-not $pcz.Verified) 'PCZ still holds values copied from INA'
Assert-True 'ICZ and INA are flagged verified'          ($icz.Verified -and $ina.Verified)

# ---------------------------------------------------------------- name parsing
Write-Host ''
Write-Host 'Package name parsing' -ForegroundColor Cyan
$p = Split-AudiPackageName -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL'
Assert-Equal 'site'         'INA'       $p.Site
Assert-Equal 'publisher'    'AUDI'      $p.Publisher
Assert-Equal 'product'      'DummyTest' $p.Product
Assert-Equal 'architecture' 'x86'       $p.Architecture
Assert-Equal 'version'      '1.0'       $p.Version
Assert-Equal 'revision'     '0001'      $p.Revision
Assert-Equal 'language'     'MUL'       $p.Language

# The bug in the tool being replaced: a text replacement turned
# ADO_ADOBE_Reader_x64_... into INA_INABE_Reader_x64_...
$p2 = Split-AudiPackageName -PackageName 'ADO_ADOBE_Reader_x64_2024.1_0003_MUL'
Assert-Equal 'non-INA site survives'      'ADO'    $p2.Site
Assert-Equal 'publisher is not corrupted' 'ADOBE'  $p2.Publisher
Assert-Equal 'product is not corrupted'   'Reader' $p2.Product

# A product name containing the separator must still parse.
$p3 = Split-AudiPackageName -PackageName 'INA_MSFT_Visual_Studio_Code_x64_1.90_0002_EN'
Assert-Equal 'multi-part product name' 'Visual_Studio_Code' $p3.Product
Assert-Equal 'architecture after a multi-part name' 'x64' $p3.Architecture

# The form a real Audi package folder actually uses: version and revision joined
# by a hyphen, so the name is the site code followed by the branding key.
# Checked against C:\temp\INA_ETAS_INCA_x64_7.5.7-0001_MUL.
$real = Split-AudiPackageName -PackageName 'INA_ETAS_INCA_x64_7.5.7-0001_MUL'
Assert-Equal 'real form: site'         'INA'   $real.Site
Assert-Equal 'real form: publisher'    'ETAS'  $real.Publisher
Assert-Equal 'real form: product'      'INCA'  $real.Product
Assert-Equal 'real form: architecture' 'x64'   $real.Architecture
Assert-Equal 'real form: version'      '7.5.7' $real.Version
Assert-Equal 'real form: revision'     '0001'  $real.Revision
Assert-Equal 'real form: language'     'MUL'   $real.Language
Assert-Equal 'the package name is the site code plus the branding key' `
    'ETAS_INCA_x64_7.5.7-0001_MUL' (Get-AudiBrandingKey -PackageName 'INA_ETAS_INCA_x64_7.5.7-0001_MUL')

# a hyphenated version must not confuse the split
$hy = Split-AudiPackageName -PackageName 'INA_MSFT_Visual_Studio_Code_x64_1.90-0002_EN'
Assert-Equal 'hyphenated form keeps a multi-part product' 'Visual_Studio_Code' $hy.Product
Assert-Equal 'hyphenated form: version'  '1.90' $hy.Version
Assert-Equal 'hyphenated form: revision' '0002' $hy.Revision

$tooShort = $false
try { Split-AudiPackageName -PackageName 'INA_AUDI_Test' | Out-Null } catch { $tooShort = $true }
Assert-True 'a malformed package name is rejected' $tooShort
$badName = ''
try { Split-AudiPackageName -PackageName 'INA_AUDI_Test' | Out-Null } catch { $badName = $_.Exception.Message }
Assert-True 'and the message shows the expected shape' ($badName -like '*INA_ETAS_INCA_x64_7.5.7-0001_MUL*')

Assert-Equal 'branding key' 'AUDI_DummyTest_x86_1.0-0001_MUL' (Get-AudiBrandingKey -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL')

# ------------------------------------------------------- reading a package
# The window is only useful if it fills itself in, so this reads a real sample
# package built by New-AudiSwSamplePackage.ps1 - a genuine PSADT v4 script
# and a genuine .docx - and checks every field actually arrives.
Write-Host ''
Write-Host 'Reading a package' -ForegroundColor Cyan

$sampleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AudiSample_{0}" -f ([guid]::NewGuid().ToString('N')))
try {
    $builder = Join-Path $PSScriptRoot 'New-AudiSwSamplePackage.ps1'
    Assert-True 'the sample package builder exists' (Test-Path -LiteralPath $builder)

    $made   = & $builder -Path $sampleRoot
    $detail = Read-AudiPackageDetail -PackagePath $made.Path

    Assert-Equal 'the PSADT generation is detected' 'v4' $detail.Generation
    Assert-True  'the deployment script is found'   ($detail.ScriptPath -like '*Invoke-AppDeployToolkit.ps1')
    Assert-True  'the instruction document is found' ($detail.DocumentPath -like '*.docx') ($detail.Notes -join '; ')

    # from the script
    foreach ($pair in @(@('Publisher','Adobe'), @('Product','Acrobat Reader'), @('Version','2024.1'),
                        @('Architecture','x64'), @('Language','MUL'), @('Revision','0003'))) {
        Assert-Equal "script gives $($pair[0])" $pair[1] $detail.Fields[$pair[0]]
    }

    # ---- the script is the authority for everything except the description
    Assert-Equal 'script gives the order number' 'AES-1-000123-A' $detail.Fields['OrderNumber']
    Assert-Equal 'script gives the portfolio'    'Adobe'          $detail.Fields['Portfolio']

    # SoftIdent is declared twice; the CUSTOM APPLICATION VARIABLES one wins,
    # because only that one carries the Wow6432Node placeholder
    Assert-True 'SoftIdent comes from the custom variables block' `
        ($detail.Fields['SoftIdentRaw'] -like '*VWG_CurrentRegWOW*') $detail.Fields['SoftIdentRaw']
    Assert-True 'and the placeholder is resolved away for x64' `
        ($detail.Fields['SoftIdent'] -notlike '*VWG_CurrentRegWOW*' -and $detail.Fields['SoftIdent'] -notlike '*Wow6432Node*') $detail.Fields['SoftIdent']

    # ---- the document is consulted for the description only
    Assert-True  'document gives the English description' ($detail.Fields['ApplicationDescriptionEN'] -like '*PDF*')
    Assert-True  'document gives the German description'  ($detail.Fields['ApplicationDescriptionDE'] -like '*PDF*')
    Assert-True  'the SHORT description is preferred over the detailed one' `
        ($detail.Fields['ApplicationDescriptionEN'] -notlike '*Detailed*') $detail.Fields['ApplicationDescriptionEN']
    Assert-True  'nothing else is taken from the document' `
        (-not ($detail.Origin.Keys | Where-Object { $detail.Origin[$_] -like 'document*' -and $_ -notlike 'ApplicationDescription*' }))

    Assert-Equal 'every field records where it came from' $detail.Fields.Count $detail.Origin.Count
    Assert-Equal 'script fields are attributed to the script' 'script:v4' $detail.Origin['Publisher']
    Assert-Equal 'document fields are attributed to the document' 'document' $detail.Origin['ApplicationDescriptionEN']

    # ---- a 32-bit package: SoftIdent must gain Wow6432Node
    $made86   = & $builder -Path $sampleRoot -PackageName 'ICZ_ADOBE_Acrobat_Reader_x86_2024.1-0003_MUL'
    $detail86 = Read-AudiPackageDetail -PackagePath $made86.Path
    Assert-Equal 'the 32-bit sample really is x86' 'x86' $detail86.Fields['Architecture']
    Assert-True  'a 32-bit package resolves SoftIdent to Wow6432Node' `
        ($detail86.Fields['SoftIdent'] -like '*\Wow6432Node\Microsoft\*') $detail86.Fields['SoftIdent']
    Assert-True  'and the origin says so' ($detail86.Origin['SoftIdent'] -like '*x86*')

    # the resolver on its own, both ways round
    Assert-Equal 'resolver: x86 inserts the node' 'HKLM:\SOFTWARE\Wow6432Node\X' `
        (Resolve-AudiSoftIdent -SoftIdent 'HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)X' -Architecture 'x86')
    Assert-Equal 'resolver: x64 removes it'       'HKLM:\SOFTWARE\X' `
        (Resolve-AudiSoftIdent -SoftIdent 'HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)X' -Architecture 'x64')
    Assert-Equal 'resolver: the bare variable form too' 'HKLM:\SOFTWARE\Wow6432Node\X' `
        (Resolve-AudiSoftIdent -SoftIdent 'HKLM:\SOFTWARE\$VWG_CurrentRegWOWX' -Architecture 'x86')
    Assert-Equal 'resolver: an empty SoftIdent stays empty' '' (Resolve-AudiSoftIdent -SoftIdent '' -Architecture 'x86')

    # a folder with nothing in it must report that, not invent values
    $empty = Join-Path $sampleRoot 'EmptyPackage'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $none = Read-AudiPackageDetail -PackagePath $empty
    Assert-Equal 'an empty package yields no fields' 0 $none.Fields.Count
    Assert-True  'and says why' (@($none.Notes).Count -gt 0)
}
finally { if (Test-Path -LiteralPath $sampleRoot) { Remove-Item -LiteralPath $sampleRoot -Recurse -Force -ErrorAction SilentlyContinue } }

# ---------------------------------------------------------------- the plan
Write-Host ''
Write-Host 'Integration plan' -ForegroundColor Cyan
$plan = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'INA' -Rfc 'RFC0012345'

Assert-Equal 'plan collection count' 9 $plan.Collections.Count
Assert-Equal 'first collection name' 'GY1-INA_AUDI_DummyTest_x86_1.0_0001_MUL' $plan.Collections[0].Name
Assert-Equal 'remove collection name' 'SM1-INA_AUDI_DummyTest_x86_1.0_0001_MUL_RemoveComputer' (@($plan.Collections | Where-Object { $_.DeploymentAction -eq 'Uninstall' })[0].Name)
Assert-Equal 'deployment type name' 'INA_AUDI_DummyTest_x86_1.0_0001_MUL_INSTALLCOMPUTER' $plan.DeploymentType
Assert-Equal 'detection key' 'Software\VWG\CM\AUDI_DummyTest_x86_1.0-0001_MUL' $plan.DetectionKey
Assert-Equal 'detection data is the revision' '0001' $plan.DetectionData
Assert-Equal 'ars group name' 'G-AUDI-AG-SW-INA_AUDI_DummyTest_x86_1.0_0001_MUL' $plan.ArsGroupName
Assert-True  'content path is under the environment share' ($plan.ContentPath -like ($ina.ContentShare + '*')) $plan.ContentPath
Assert-True  'rfc is recorded on every collection'         (@($plan.Collections | Where-Object { $_.Comment -like '*RFC0012345*' }).Count -eq 9)
# read from config, not hardcoded: the account is a normal user while testing and
# becomes the gMSA later, and the test should not care which
Assert-Equal 'executor is the environment service account' $ina.Service.account $plan.Executor

# ------------------------------------------------- parity with the old tool
# Every value below is read straight out of the tool being replaced, from
# EQS-PoshGUI-Tool-1.0.3\INA\VWG-SCCM-ApplicationIntegration_v2.0.0.0.xml.
# An application this tool makes must be indistinguishable from one theirs made,
# so a difference here has to be a decision, not a slip.
Write-Host ''
Write-Host 'Parity with the old tool' -ForegroundColor Cyan

$d = Get-AudiDefaults
Assert-Equal 'estimated install minutes'      '3'   $d.Application.estimatedInstallMinutes
Assert-Equal 'maximum run time minutes'       '120' $d.Application.maxRuntimeMinutes
Assert-Equal 'category'                       'Development' $d.Application.category
Assert-Equal 'default language'               'en-us' $d.Application.defaultLanguage
Assert-Equal 'install command'                'Invoke-AppDeployToolkit.exe Install'   $d.Commands.install
Assert-Equal 'uninstall command'              'Invoke-AppDeployToolkit.exe Uninstall' $d.Commands.uninstall
Assert-Equal 'deployment type suffix'         '_INSTALLCOMPUTER' $d.Naming.deploymentTypeSuffix
Assert-Equal 'branding registry root'         'Software\VWG\CM\' $d.Naming.brandingRegistryRoot
Assert-Equal 'AD group prefix'                'G-AUDI-AG-SW-' $d.Naming.arsGroupPrefix

Assert-Equal 'program visibility'             'Hidden' $d.DeploymentType.programVisibility
Assert-Equal 'installation behaviour'         'InstallForSystem' $d.DeploymentType.installationBehaviorType
Assert-Equal 'logon requirement'              'WhetherOrNotUserLoggedOn' $d.DeploymentType.logonRequirementType
Assert-Equal 'slow network mode'              'Download' $d.DeploymentType.slowNetworkDeploymentMode
Assert-Equal 'distribution point setting'     'AutoDownload' $d.DeploymentType.distributionPointSetting
Assert-Equal 'allow client to share content'  'false' $d.DeploymentType.allowClientToShareContent
Assert-Equal 'allow client to use fallback'   'true'  $d.DeploymentType.allowClientToUseFallback
Assert-Equal 'persist content in cache'       'false' $d.DeploymentType.persistContentInClientCache
Assert-Equal 'run 32-bit on 64-bit'           'false' $d.DeploymentType.run32BitOn64Bit

Assert-Equal 'detection value name'           'Revision' $d.Detection.valueName
Assert-Equal 'detection data type'            'String'   $d.Detection.dataType
Assert-Equal 'detection is 64-bit'            'true'     $d.Detection.is64Bit
Assert-Equal 'detection method'               'Value'    $d.Detection.method

# The settings the deployment type is actually given, not just the ones in
# config - a value that never reaches SCCM is not parity.
foreach ($field in 'MaxRuntimeMinutes', 'EstimatedInstallMinutes', 'ProgramVisibility',
                   'InstallationBehaviorType', 'LogonRequirementType', 'OnSlowNetworkMode',
                   'AllowClientToShareContent', 'AllowClientToUseFallback',
                   'PersistContentInCache', 'Run32BitOn64Bit', 'ApplicationComment') {
    Assert-True "the plan carries $field" ([bool]$plan.PSObject.Properties[$field])
}
Assert-Equal 'the plan carries their estimate, not ours' 3 $plan.EstimatedInstallMinutes

# Windows 7 is the one deliberate difference in the OS list, because it is out
# of support. Everything else about the deployment type matches.
Assert-Equal 'two operating systems, Windows 7 dropped on purpose' 2 @($d.OperatingSystems).Count
Assert-True  'no Windows 7 platform string remains' `
    (@($d.OperatingSystems | Where-Object { $_.Value -like '*Windows_7*' }).Count -eq 0)

# The application's admin comment carries the audit link instead of their fixed
# "created by manual MCB script".
Assert-True 'the application comment carries the job id' ($plan.ApplicationComment -like "*$($plan.JobId)*")
Assert-True 'and the RFC'                                ($plan.ApplicationComment -like '*RFC0012345*')

# ------------------------------------------------------------ detection rules
# Two rules, both of which must hold: the branding key the package writes, and
# the product's own uninstall entry from VWG_SoftIdent. There is deliberately no
# separate "detection key" to keep in step with the branding key - the branding
# key IS rule 1.
Write-Host ''
Write-Host 'Detection rules' -ForegroundColor Cyan

Assert-Equal 'a package with no SoftIdent gets one rule' 1 @($plan.DetectionRules).Count
Assert-Equal 'and it is the branding key'   'Software\VWG\CM\AUDI_DummyTest_x86_1.0-0001_MUL' $plan.DetectionRules[0].Key
Assert-Equal 'checked on the revision'      'Revision' $plan.DetectionRules[0].ValueName
Assert-Equal 'against the revision itself'  '0001'     $plan.DetectionRules[0].Value

$softPlan = Get-AudiIntegrationPlan -PackageName 'INA_ETAS_INCA_x64_7.5.7-0001_MUL' -EnvironmentCode 'INA' -Rfc 'RFC0012345' `
                -SoftIdent 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\INCA7.5.7 [DisplayVersion=7.5.7]'
Assert-Equal 'a SoftIdent adds a second rule' 2 @($softPlan.DetectionRules).Count
$rule2 = $softPlan.DetectionRules[1]
Assert-Equal 'rule 2 hive'       'HKLM' $rule2.Hive
Assert-Equal 'rule 2 key'        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\INCA7.5.7' $rule2.Key
Assert-Equal 'rule 2 value name' 'DisplayVersion' $rule2.ValueName
Assert-Equal 'rule 2 value'      '7.5.7' $rule2.Value
Assert-True  'the two rules are different registry keys' ($softPlan.DetectionRules[0].Key -ne $rule2.Key)

# A 32-bit package resolves the script's own placeholder, so the rule points at
# the view the product actually installs into. We never guess this.
$wowPlan = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'INA' -Rfc 'R' `
               -SoftIdent (Resolve-AudiSoftIdent -SoftIdent 'HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Vendor\Thing [Version=1.0]' -Architecture 'x86')
Assert-True 'a 32-bit package detects under Wow6432Node' ($wowPlan.DetectionRules[1].Key -like 'SOFTWARE\Wow6432Node\*') $wowPlan.DetectionRules[1].Key

# A key with no value test is an existence check, not a value comparison.
$existsPlan = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'INA' -Rfc 'R' `
                  -SoftIdent 'HKLM:\SOFTWARE\Vendor\Thing'
Assert-Equal 'a SoftIdent with no value test is an existence check' 'KeyExists' $existsPlan.DetectionRules[1].Method
Assert-Equal 'and carries no value name' '' $existsPlan.DetectionRules[1].ValueName

# Guessing at a SoftIdent nobody can parse would produce an application that
# installs and then reports itself as not installed, so it is dropped instead.
$oddPlan = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'INA' -Rfc 'R' `
               -SoftIdent 'this is not a registry path'
Assert-Equal 'an unrecognised SoftIdent is dropped rather than guessed at' 1 @($oddPlan.DetectionRules).Count

$unresolvedPlan = Get-AudiIntegrationPlan -PackageName 'INA_AUDI_DummyTest_x86_1.0_0001_MUL' -EnvironmentCode 'INA' -Rfc 'R' `
                      -SoftIdent 'HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Vendor\Thing [Version=1.0]'
Assert-Equal 'an unresolved placeholder never becomes a literal key' 1 @($unresolvedPlan.DetectionRules).Count

Assert-True 'the rules read back as one line for the log and the window' `
    ((Format-AudiDetectionRule -Rules $softPlan.DetectionRules) -like '*AND*')

# The test site is a plain environment file like any other - its own site code
# and server, everything else ICZ's. Skipped once it is deleted.
if ($codes -contains 'II1') {
    Write-Host ''
    Write-Host 'The test site' -ForegroundColor Cyan
    $test = Get-AudiEnvironment -Code 'II1'
    Assert-Equal 'its own site code'   'II1' $test.SiteCode
    Assert-Equal 'its own site server' 'AUDIINSA1299.audi.vwg5t' $test.SiteServer
    Assert-True  'not ICZ''s server'   ((Get-AudiEnvironment -Code 'ICZ').SiteServer -ne $test.SiteServer)
    Assert-Equal 'its own drop folder' 'C:\AudiSwIntegration\DropFolder\II1' $test.Transport.DropFolder
}

# --------------------------------------------------- privacy: nothing personal
# Audi's requirement: no real person's name may reach the SCCM side at all -
# not an SCCM object, and not the tool's own log or job record on the server.
# The RFC number is the audit link instead. These checks exist so the rule
# cannot be lost in a later refactor without a test going red.
Write-Host ''
Write-Host 'Privacy - no person reaches the SCCM side' -ForegroundColor Cyan

# The strongest guarantee is structural: if the plan holds no person, there is
# nothing for any log line, comment or record to write.
Assert-True 'the plan has no Requester field' (-not $plan.PSObject.Properties['Requester'])
Assert-True 'Get-AudiIntegrationPlan takes no -Requester parameter' `
    (-not (Get-Command Get-AudiIntegrationPlan).Parameters.ContainsKey('Requester'))

Assert-Equal 'the RFC carries the audit trail instead' 'RFC0012345' $plan.Rfc
Assert-True  'every collection comment carries the job id' `
    (@($plan.Collections | Where-Object { $_.Comment -like "*$($plan.JobId)*" }).Count -eq 9)

# every string the engine writes into SCCM or AD, checked in one place. The
# signed-in account is the one name guaranteed to be available to leak.
$sccmBound = @($plan.ApplicationName, $plan.LocalizedName, $plan.LocalizedDescription,
               $plan.DeploymentType, $plan.DetectionKey, $plan.Category,
               $plan.ArsGroupName, $plan.ArsDescription) +
             @($plan.Collections | ForEach-Object { $_.Name; $_.Comment })
$leaked = @($sccmBound | Where-Object { $_ -like "*$env:USERNAME*" -or $_ -like '*tester*' })
Assert-True 'nothing bound for SCCM or AD names a person' ($leaked.Count -eq 0) ($leaked -join ' | ')

Assert-True 'an RFC is required, so a change is never untraceable' (Get-AudiDefaults).Audit.RequireRfc

# and a config edit must not be able to put it back
Assert-Equal 'a template naming the requester is refused' 1 `
    (@(Test-AudiSccmCommentTemplate -Template 'job {jobId} requested by {requester}').Count)
Assert-Equal 'a clean template passes' 0 `
    (@(Test-AudiSccmCommentTemplate -Template 'job {jobId} | RFC {rfc}').Count)

# ---------------------------------------------------------------- summary
Write-Host ''
if ($script:Fail -eq 0) { Write-Host ("All {0} checks passed." -f $script:Pass) -ForegroundColor Green }
else                    { Write-Host ("{0} passed, {1} FAILED." -f $script:Pass, $script:Fail) -ForegroundColor Red }
Write-Host ''
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
