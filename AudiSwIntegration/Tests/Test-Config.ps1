# ==============================================================================
#  Test harness for increment 1. Runs anywhere - no SCCM, no network, no rights.
#    .\Test-AudiSwIntegration.ps1
# ==============================================================================

[CmdletBinding()]
param([switch]$Quiet)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'SccmServer\Engine\AudiSwIntegration.ps1')

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

# EWALD'S CASE: ConfigMgr -Name parameters take wildcards, so a package name
# with one would match every object that fits the pattern - and a removal
# would take all of them. Such a name never gets as far as a plan.
foreach ($wild in 'INA_*_x64_1.0_0001_MUL', 'INA_AUDI_Test?_x86_1.0_0001_MUL', 'INA_AUDI_[a-z]_x86_1.0_0001_MUL',
                  'INA_AUDI_..\..\Test_x86_1.0_0001_MUL', 'INA_AUDI_Te st_x86_1.0_0001_MUL', 'INA_AUDI_Test"_x86_1.0_0001_MUL') {
    $refused = ''
    try { Split-AudiPackageName -PackageName $wild | Out-Null } catch { $refused = $_.Exception.Message }
    Assert-True "a name with a wildcard or path character is refused: $wild" ($refused -like '*not allowed in a name*') $refused
}
# and the provider's own guard says the same for any name that reaches it
$guard = ''
try { Assert-AudiExactName -Name 'INA_*' -What 'application name' | Out-Null } catch { $guard = $_.Exception.Message }
Assert-True 'the provider refuses a wildcard name before any cmdlet sees it' ($guard -like '*wildcard*') $guard
Assert-Equal 'and passes an exact one through' 'INA_X' (Assert-AudiExactName -Name 'INA_X')

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

    # Detection is the branding key only, so the script's VWG_SoftIdent is not
    # read at all - a value nobody uses must not appear in the window either.
    Assert-True 'the SoftIdent is not read from the script' (-not $detail.Fields.Contains('SoftIdent'))

    # The install title is what Software Center shows. It comes from the script,
    # never composed from the package name.
    Assert-Equal 'script gives the install title' 'Adobe Acrobat Reader 2024.1' $detail.Fields['InstallTitle']

    # ---- the document is consulted for the description only
    Assert-True  'document gives the English description' ($detail.Fields['ApplicationDescriptionEN'] -like '*PDF*')
    Assert-True  'document gives the German description'  ($detail.Fields['ApplicationDescriptionDE'] -like '*PDF*')
    Assert-True  'the SHORT description is preferred over the detailed one' `
        ($detail.Fields['ApplicationDescriptionEN'] -notlike '*Detailed*') $detail.Fields['ApplicationDescriptionEN']
    Assert-True  'nothing else is taken from the document' `
        (-not ($detail.Origin.Keys | Where-Object { $detail.Origin[$_] -like 'document*' -and $_ -notlike 'ApplicationDescription*' }))

    Assert-Equal 'every field records where it came from' $detail.Fields.Count $detail.Origin.Count
    Assert-Equal 'script fields are attributed to the script' 'script:v4' $detail.Origin['Publisher']
    Assert-True 'document fields are attributed to the document, by name' ($detail.Origin['ApplicationDescriptionEN'] -like 'document: *Software Integration*') $detail.Origin['ApplicationDescriptionEN']

    # ---- a 32-bit package reads the same way; architecture changes nothing else
    $made86   = & $builder -Path $sampleRoot -PackageName 'ICZ_ADOBE_Acrobat_Reader_x86_2024.1-0003_MUL'
    $detail86 = Read-AudiPackageDetail -PackagePath $made86.Path
    Assert-Equal 'the 32-bit sample really is x86' 'x86' $detail86.Fields['Architecture']
    Assert-Equal 'and carries the same install title' $detail.Fields['InstallTitle'] $detail86.Fields['InstallTitle']

    # ---- the description, both shapes, through the REAL reader
    # The sample closes nothing, so the short description stands on its own -
    # no empty "will be closed:" sentence in front of it.
    Assert-Equal 'closing nothing: the short description alone' `
        'Reads, prints and annotates PDF documents.' $detail.Fields['ApplicationDescriptionEN']
    Assert-Equal 'closing nothing: the German one too' `
        'Liest, druckt und kommentiert PDF-Dokumente.' $detail.Fields['ApplicationDescriptionDE']
    Assert-True  'closing nothing: no process list is recorded' (-not $detail.Fields.Contains('ProcessesClosed'))

    # Now the same package told to close two processes, as a real PSADT 4
    # script does it, read again: the sentence must come FIRST, then the
    # short description, in both languages, and the list must be recorded.
    $closing = & $builder -Path $sampleRoot -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0004_MUL'
    $script  = Join-Path $closing.Path 'Invoke-AppDeployToolkit.ps1'
    $text    = [System.IO.File]::ReadAllText($script)
    $text    = $text.Replace("    AppScriptAuthor = 'Packaging Team'", "    AppScriptAuthor = 'Packaging Team'`r`n    AppProcessesToClose = @('AcroRd32', 'AcroCEF')")
    [System.IO.File]::WriteAllText($script, $text)
    $detailClosing = Read-AudiPackageDetail -PackagePath $closing.Path
    Assert-Equal 'closing processes: sentence first, then the short description' `
        'The following applications will be closed for installation: AcroRd32,AcroCEF. Reads, prints and annotates PDF documents.' `
        $detailClosing.Fields['ApplicationDescriptionEN']
    Assert-Equal 'closing processes: the German sentence too' `
        'Folgende Anwendungen werden fuer die Installation geschlossen: AcroRd32,AcroCEF. Liest, druckt und kommentiert PDF-Dokumente.' `
        $detailClosing.Fields['ApplicationDescriptionDE']
    Assert-Equal 'closing processes: the list is recorded' 'AcroRd32,AcroCEF' $detailClosing.Fields['ProcessesClosed']
    Assert-True  'closing processes: the DETAILED description is still not used' `
        ($detailClosing.Fields['ApplicationDescriptionEN'] -notlike '*Detailed*')
    # Reading the same package twice must not stack the sentence twice.
    $again = Read-AudiPackageDetail -PackagePath $closing.Path
    Assert-Equal 'the sentence is never doubled' $detailClosing.Fields['ApplicationDescriptionEN'] $again.Fields['ApplicationDescriptionEN']

    # ---- which Word file is the request form
    # Audi's form now arrives as "<Product>-<Version>_Software Integration
    # Level 3_request_(1).docx". The sample is named that way, and it must be
    # found by that name - not by being the only, or the newest, Word file.
    Assert-True 'the request form is found under its new Audi name' `
        ((Split-Path -Leaf $detail.DocumentPath) -like '*Software Integration Level 3_request*') $detail.DocumentPath

    $decoyed = & $builder -Path $sampleRoot -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0005_MUL' -WithDecoyDocument
    $detailDecoy = Read-AudiPackageDetail -PackagePath $decoyed.Path
    Assert-True  'with a NEWER vendor document beside it, the form still wins' `
        ((Split-Path -Leaf $detailDecoy.DocumentPath) -like '*Software Integration*') $detailDecoy.DocumentPath
    Assert-Equal 'and the description comes from the form, not the vendor sheet' `
        'Reads, prints and annotates PDF documents.' $detailDecoy.Fields['ApplicationDescriptionEN']
    Assert-True  'and the packager is told which file was read and which was not' `
        (@($detailDecoy.Info | Where-Object { $_ -like 'Read from: *Software Integration*' -and $_ -notlike '*product sheet*' }).Count -eq 1) ($detailDecoy.Info -join ' | ')
    Assert-True  'as information, not as a problem' (@($detailDecoy.Notes | Where-Object { $_ -like '*Word files*' }).Count -eq 0)
    Assert-True  'the decoy is not the document of record' ($detailDecoy.DocumentPath -notlike '*product sheet*')

    # ---- the cascade: form, then install document, then anything else.
    # Every Word file is read; each field comes from the FIRST file that has
    # it. With all three present the form wins; take the form away and the
    # install document supplies the English description, and the vendor sheet
    # - newest of all - still never does.
    $cascade = & $builder -Path $sampleRoot -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0007_MUL' -WithDecoyDocument -WithInstallDocument
    $c1 = Read-AudiPackageDetail -PackagePath $cascade.Path
    Assert-Equal 'all three present: the form supplies the English description' `
        'Reads, prints and annotates PDF documents.' $c1.Fields['ApplicationDescriptionEN']
    Assert-True  'and says it came from the form' ($c1.Origin['ApplicationDescriptionEN'] -like 'document: *Software Integration*') $c1.Origin['ApplicationDescriptionEN']
    Assert-True  'the info line lists the files read, form first' `
        (@($c1.Info | Where-Object { $_ -like 'Read from: *Software Integration*' }).Count -eq 1) ($c1.Info -join ' | ')
    Remove-Item -LiteralPath (@(Get-ChildItem -LiteralPath $cascade.Path -Filter '*Software Integration*' -Recurse)[0].FullName) -Force
    $c2 = Read-AudiPackageDetail -PackagePath $cascade.Path
    Assert-Equal 'form gone: the install document supplies it' 'From the install document.' $c2.Fields['ApplicationDescriptionEN']
    Assert-True  'and says so' ($c2.Origin['ApplicationDescriptionEN'] -like 'document: install_document.docx*') $c2.Origin['ApplicationDescriptionEN']
    Assert-True  'the newer vendor sheet still never supplies it' ($c2.Fields['ApplicationDescriptionEN'] -notlike 'WRONG*')
    Assert-True  'the install document is now the document of record' ((Split-Path -Leaf $c2.DocumentPath) -eq 'install_document.docx') $c2.DocumentPath
    Assert-True  'German, which no remaining file has, is simply absent' (-not $c2.Fields.Contains('ApplicationDescriptionDE'))
    Assert-True  'and no amber note about a missing description, since one was found' `
        (@($c2.Notes | Where-Object { $_ -like '*no description*' }).Count -eq 0) ($c2.Notes -join ' | ')

    # ---- the documents location: forms kept apart from packages.
    #   <root>\<AES-ID> <Vendor> <App> <Version>\Documentation\<form>.docx
    # Used only when the package holds no form of its own; found by AES ID,
    # else by vendor + product + version in the folder name.
    $docRoot = Join-Path $sampleRoot 'Documents'
    $aesDir  = Join-Path $docRoot 'AES-1-000123-A Adobe Acrobat Reader 2024.1\Documentation'
    $bare    = & $builder -Path $sampleRoot -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0008_MUL' -DocumentTarget $aesDir
    Assert-True  'the bare package holds no Word file' (@(Get-ChildItem -LiteralPath $bare.Path -Filter '*.docx' -Recurse).Count -eq 0)

    $noRoot = Read-AudiPackageDetail -PackagePath $bare.Path
    Assert-True  'without a documents location the description is missing' (-not $noRoot.Fields.Contains('ApplicationDescriptionEN'))
    Assert-True  'and the packager is told to type it' (@($noRoot.Notes | Where-Object { $_ -like '*typed in by hand*' }).Count -gt 0)

    $viaRoot = Read-AudiPackageDetail -PackagePath $bare.Path -DocumentRoot $docRoot
    Assert-Equal 'with the documents location the description arrives' 'Reads, prints and annotates PDF documents.' $viaRoot.Fields['ApplicationDescriptionEN']
    Assert-True  'the form was found under the AES folder''s Documentation subfolder' ($viaRoot.DocumentPath -like "*AES-1-000123-A*\Documentation\*Software Integration*") $viaRoot.DocumentPath
    Assert-True  'the folder is reported as matched by the AES ID' (@($viaRoot.Info | Where-Object { $_ -like '*matched by the AES ID AES-1-000123-A*' }).Count -eq 1) ($viaRoot.Info -join ' | ')
    Assert-True  'and DocumentFolder names it' ($viaRoot.DocumentFolder -like '*AES-1-000123-A Adobe Acrobat Reader 2024.1')

    # A folder named without the AES ID is still found by app + version - the
    # vendor is NOT required (Audi leave it out, shorten it or abbreviate it).
    Rename-Item -LiteralPath (Split-Path -Parent $aesDir) -NewName 'Acrobat_Reader 2024_1 request'
    $fuzzy = Read-AudiPackageDetail -PackagePath $bare.Path -DocumentRoot $docRoot
    Assert-Equal 'no AES ID, no vendor in the folder name: matched by app + version' 'Reads, prints and annotates PDF documents.' $fuzzy.Fields['ApplicationDescriptionEN']
    Assert-True  'and the answer says it was a name match' (@($fuzzy.Info | Where-Object { $_ -like '*matched by name on*' }).Count -eq 1) ($fuzzy.Info -join ' | ')
    # Two folders match on app + version: the one that also names the vendor wins.
    $withVendor = Join-Path $docRoot 'Adobe Acrobat Reader 2024.1 (second request)\Documentation'
    $null = & $builder -Path $sampleRoot -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0010_MUL' -DocumentTarget $withVendor
    (Get-Item -LiteralPath (Split-Path -Parent $withVendor)).LastWriteTime = (Get-Date).AddDays(-30)   # older, so only the vendor can win it
    $prefer = Read-AudiPackageDetail -PackagePath $bare.Path -DocumentRoot $docRoot
    Assert-True  'of two name matches, the folder naming the vendor is preferred' ($prefer.DocumentFolder -like '*Adobe Acrobat Reader 2024.1 (second request)') $prefer.DocumentFolder

    # A package with its own form never consults the documents location.
    $own = Read-AudiPackageDetail -PackagePath $made.Path -DocumentRoot $docRoot
    Assert-True  'a package with its own form reads that, not the documents location' ($own.DocumentPath -like "$($made.Path)*") $own.DocumentPath
    Assert-True  'and says nothing about the documents location' (@($own.Info | Where-Object { $_ -like '*documents location*' }).Count -eq 0)

    # Nothing matching in the documents location: a clear note, no guess.
    # (The sample script always carries Adobe's AES ID, so the test uses a
    # documents location that holds somebody else's request only.)
    $otherRoot = Join-Path $sampleRoot 'Documents2'
    New-Item -ItemType Directory -Path (Join-Path $otherRoot 'AES-9-999999-Z Foo Bar 1.0\Documentation') -Force | Out-Null
    $none = Read-AudiPackageDetail -PackagePath $bare.Path -DocumentRoot $otherRoot
    Assert-True  'no matching folder: the note says what was looked for' (@($none.Notes | Where-Object { $_ -like '*No folder under*matches this package*' }).Count -eq 1) ($none.Notes -join ' | ')
    Assert-True  'and no description is invented' (-not $none.Fields.Contains('ApplicationDescriptionEN'))

    # ---- putting the package on the content share
    # Two shapes: the script at the top (copy as is), or under Content\ beside
    # Documents\ and Icons\ (copy Content\ only). The target carries the SCCM
    # spelling, and a half-copied package never appears under the real name.
    Write-Host ''
    Write-Host 'Copying to the content share' -ForegroundColor Cyan
    $share = Join-Path $sampleRoot 'ContentShare'
    New-Item -ItemType Directory -Path $share -Force | Out-Null

    Assert-Equal 'a flat package copies from its own root' $made.Path (Get-AudiPackageContentRoot -PackagePath $made.Path)

    $shaped = Join-Path $sampleRoot 'INA_ADOBE_Acrobat_Reader_x64_2024.1-0011_MUL'
    New-Item -ItemType Directory -Path (Join-Path $shaped 'Content\Files') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $shaped 'Documents') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $shaped 'Icons') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $made.Path 'Invoke-AppDeployToolkit.ps1') -Destination (Join-Path $shaped 'Content\Invoke-AppDeployToolkit.ps1')
    Set-Content -LiteralPath (Join-Path $shaped 'Content\Files\setup.exe') -Value 'x' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $shaped 'Documents\notes.txt') -Value 'x' -Encoding ASCII
    Assert-Equal 'a Content\Documents\Icons package copies Content only' (Join-Path $shaped 'Content') (Get-AudiPackageContentRoot -PackagePath $shaped)

    $noScript = Join-Path $sampleRoot 'INA_AUDI_Empty_x64_1.0_0001_MUL'
    New-Item -ItemType Directory -Path $noScript -Force | Out-Null
    $refused = $false
    try { $null = Get-AudiPackageContentRoot -PackagePath $noScript } catch { $refused = $true }
    Assert-True 'a folder with no deployment script is refused, not copied' $refused

    $sccm = Get-AudiSccmName -PackageName (Split-Path -Leaf $shaped)
    $seen = New-Object System.Collections.Generic.List[string]
    $copy = Copy-AudiPackageContent -PackagePath $shaped -ContentShare $share -SccmName $sccm -OnProgress { param($d, $t, $f) $seen.Add("$d/$t $f") }
    Assert-True  'the package lands under its SCCM (underscore) name' (Test-Path -LiteralPath (Join-Path $share 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0011_MUL'))
    Assert-True  'with the script at the top, not under Content\' (Test-Path -LiteralPath (Join-Path $share "$sccm\Invoke-AppDeployToolkit.ps1"))
    Assert-True  'and its files beneath it' (Test-Path -LiteralPath (Join-Path $share "$sccm\Files\setup.exe"))
    Assert-True  'Documents and Icons are NOT copied' (-not (Test-Path -LiteralPath (Join-Path $share "$sccm\Documents")) -and -not (Test-Path -LiteralPath (Join-Path $share "$sccm\notes.txt")))
    Assert-True  'no staging folder is left behind' (@(Get-ChildItem -LiteralPath $share -Directory -Filter '~*').Count -eq 0)
    Assert-Equal 'progress was reported per file' 2 $seen.Count
    Assert-True  'the copy says it copied' $copy.Copied
    $again = Copy-AudiPackageContent -PackagePath $shaped -ContentShare $share -SccmName $sccm
    Assert-True  'a second run finds it there and copies nothing' (-not $again.Copied)
    $missingShare = $false
    # ---- UPDATE CONTENT: only what differs is written; judged by size and
    # hash, never by timestamp; timestamps are never rewritten
    $store = Join-Path $share $sccm
    $srcRoot = Get-AudiPackageContentRoot -PackagePath $shaped
    $newFile = Join-Path $srcRoot 'Files\added.txt'; 'new' | Set-Content -LiteralPath $newFile -Encoding UTF8
    $script1 = Join-Path $srcRoot 'Invoke-AppDeployToolkit.ps1'
    $untouched = @(Get-ChildItem -LiteralPath $srcRoot -File -Recurse | Where-Object { $_.FullName -ne $script1 -and $_.FullName -ne $newFile })[0]
    (Get-Content -LiteralPath $script1 -Raw) + "`r`n# changed" | Set-Content -LiteralPath $script1 -Encoding UTF8
    # the untouched file gets a DIFFERENT timestamp on the source side - as it
    # would after a copy between machines - and must still count as unchanged
    (Get-Item -LiteralPath $untouched.FullName).LastWriteTime = (Get-Date).AddDays(-30)
    $storeUntouchedBefore = (Get-Item -LiteralPath (Join-Path $store ($untouched.FullName.Substring($srcRoot.TrimEnd('\').Length).TrimStart('\')))).LastWriteTimeUtc
    'old' | Set-Content -LiteralPath (Join-Path $store 'Files\stale.txt') -Encoding UTF8   # in the store, no longer in the package
    $sync = Sync-AudiPackageContent -Source $srcRoot -Target $store
    Assert-Equal 'update content: the changed script is replaced'      1 $sync.Replaced
    Assert-Equal 'update content: the new file is added'               1 $sync.Added
    Assert-Equal 'update content: the file no longer sent is removed'  1 $sync.Removed
    Assert-True  'update content: everything else is left alone'       ($sync.Unchanged -ge 1 -and $sync.Replaced + $sync.Added + $sync.Unchanged -eq $sync.Files)
    Assert-True  'a different timestamp alone does not make a file "changed"' ($sync.Unchanged -ge 1)
    Assert-True  'the store copy of an unchanged file keeps its timestamp'  ((Get-Item -LiteralPath (Join-Path $store ($untouched.FullName.Substring($srcRoot.TrimEnd('\').Length).TrimStart('\')))).LastWriteTimeUtc -eq $storeUntouchedBefore)
    Assert-True  'a replaced file carries the timestamp it has in Sources, not "now"' `
        ([Math]::Abs(((Get-Item -LiteralPath (Join-Path $store 'Invoke-AppDeployToolkit.ps1')).LastWriteTimeUtc - (Get-Item -LiteralPath $script1).LastWriteTimeUtc).TotalSeconds) -lt 2)
    Assert-True  'the replaced content really is the new content'      ((Get-Content -LiteralPath (Join-Path $store 'Invoke-AppDeployToolkit.ps1') -Raw) -like '*# changed*')
    Assert-True  'no temporary file is left in the store'              (@(Get-ChildItem -LiteralPath $store -Recurse -Force | Where-Object { $_.Name -like '~*' }).Count -eq 0)
    $again = Sync-AudiPackageContent -Source $srcRoot -Target $store
    Assert-Equal 'a second update finds nothing to do'                 0 ($again.Replaced + $again.Added + $again.Removed)

    # ---- room on the target volume is checked before a byte moves
    $freeHere = Get-AudiFreeSpace -Path $share
    Assert-True 'free space on a local path can be read' ($freeHere -gt 0) "$freeHere"
    $tooBig = ''
    try { Assert-AudiEnoughSpace -Path $share -Bytes ($freeHere + 1GB) -What 'a test package' } catch { $tooBig = $_.Exception.Message }
    Assert-True 'a copy that would not fit is refused up front, with the numbers' ($tooBig -like 'Not enough free space*GB free*') $tooBig
    $fits = ''
    try { Assert-AudiEnoughSpace -Path $share -Bytes 1KB -MarginBytes 0 } catch { $fits = $_.Exception.Message }
    Assert-True 'one that fits goes ahead' (-not $fits) $fits

    try { $null = Copy-AudiPackageContent -PackagePath $shaped -ContentShare (Join-Path $sampleRoot 'NoSuchShare') -SccmName $sccm } catch { $missingShare = $true }
    Assert-True  'an unreachable share is an error, not a silent nothing' $missingShare

    # A package whose only Word file matches no name pattern is still read - a
    # pattern picks between files, it never hides the only one there is.
    $lone = & $builder -Path $sampleRoot -PackageName 'INA_ADOBE_Acrobat_Reader_x64_2024.1_0006_MUL'
    $formPath = @(Get-ChildItem -LiteralPath $lone.Path -Filter '*.docx' -Recurse)[0].FullName
    $renamed  = Join-Path (Split-Path -Parent $formPath) 'Install instruction.docx'
    Move-Item -LiteralPath $formPath -Destination $renamed
    $detailLone = Read-AudiPackageDetail -PackagePath $lone.Path
    Assert-Equal 'a lone document with an unmatched name is still read' 'Install instruction.docx' (Split-Path -Leaf $detailLone.DocumentPath)
    Assert-Equal 'and gives its description' 'Reads, prints and annotates PDF documents.' $detailLone.Fields['ApplicationDescriptionEN']

    # The order in Defaults.xml is the order of preference.
    $docSpec = (Get-AudiDefaults).PackageSource.Document
    Assert-Equal 'Software Integration is tried first' 'Software Integration' @($docSpec.NamePatterns)[0]
    Assert-Equal 'the install instruction second'    'Install' @($docSpec.NamePatterns)[1]

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
Assert-Equal 'detection key' 'Software\VWG\CM\AUDI_DummyTest_x86_1.0-0001_MUL' $plan.DetectionRules[0].Key
Assert-Equal 'detection data is the revision' '0001' $plan.DetectionRules[0].Value
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
Assert-Equal 'estimated install minutes'      '10'  $d.Application.estimatedInstallMinutes
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
Assert-Equal 'the plan carries their estimate, not ours' 10 $plan.EstimatedInstallMinutes

# Windows 7 is the one deliberate difference in the OS list, because it is out
# of support. Everything else about the deployment type matches.
Assert-Equal 'two operating systems, Windows 7 dropped on purpose' 2 @($d.OperatingSystems).Count
Assert-True  'no Windows 7 platform string remains' `
    (@($d.OperatingSystems | Where-Object { $_.Value -like '*Windows_7*' }).Count -eq 0)

# The application's admin comment carries the audit link instead of their fixed
# "created by manual MCB script".
Assert-True 'the application comment carries the job id' ($plan.ApplicationComment -like "*$($plan.JobId)*")
Assert-True 'and the RFC'                                ($plan.ApplicationComment -like '*RFC0012345*')

# ------------------------------------------------------------ two spellings
# Audi's rule: the browsed folder may carry a hyphen before the revision, but
# everything in SCCM and the content folder on the share carry an underscore.
# Only the branding key keeps the hyphen, because the script writes it so.
Write-Host ''
Write-Host 'Underscore in SCCM, hyphen in the branding key' -ForegroundColor Cyan

$hyphenName = 'INA_WinMerge_WinMerge_x64_2.16.58-0001_test'
$sccmName   = 'INA_WinMerge_WinMerge_x64_2.16.58_0001_test'
Assert-Equal 'a hyphen name spells as underscore for SCCM'   $sccmName (Get-AudiSccmName -PackageName $hyphenName)
Assert-Equal 'an underscore name is already the SCCM name'  $sccmName (Get-AudiSccmName -PackageName $sccmName)
Assert-Equal 'the branding key keeps the hyphen, from either' 'WinMerge_WinMerge_x64_2.16.58-0001_test' (Get-AudiBrandingKey -PackageName $hyphenName)
Assert-Equal 'and from the underscore spelling too'          'WinMerge_WinMerge_x64_2.16.58-0001_test' (Get-AudiBrandingKey -PackageName $sccmName)

$wmPlan = Get-AudiIntegrationPlan -PackageName $hyphenName -EnvironmentCode 'INA' -Rfc 'RFC0012345'
Assert-Equal 'the plan carries the SCCM spelling'            $sccmName $wmPlan.PackageName
Assert-Equal 'the application is named with the underscore' $sccmName $wmPlan.ApplicationName
Assert-True  'the deployment type too'                      ($wmPlan.DeploymentType -like "$sccmName*") $wmPlan.DeploymentType
Assert-True  'the content folder on the share too'          ($wmPlan.ContentPath -like "*\$sccmName") $wmPlan.ContentPath
Assert-True  'every collection too'                         (@($wmPlan.Collections | Where-Object { $_.Name -notlike "*$sccmName*" }).Count -eq 0)
Assert-True  'nothing on the SCCM side carries the hyphen'  (@($wmPlan.Collections | Where-Object { $_.Name -like '*2.16.58-0001*' }).Count -eq 0 -and $wmPlan.ContentPath -notlike '*2.16.58-0001*')
Assert-True  'the AD group too'                             ($wmPlan.ArsGroupName -like "*$sccmName") $wmPlan.ArsGroupName
Assert-Equal 'while detection reads the hyphen key the script writes' 'Software\VWG\CM\WinMerge_WinMerge_x64_2.16.58-0001_test' $wmPlan.DetectionRules[0].Key
Assert-Equal 'and the revision is still the revision'       '0001' $wmPlan.DetectionRules[0].Value

# ------------------------------------------------------------ detection rule
# ONE rule: the branding key the package writes, checked on the revision. There
# is deliberately no separate "detection key" to keep in step with the branding
# key - the branding key IS the rule - and nothing else is detected on.
Write-Host ''
Write-Host 'Detection rule' -ForegroundColor Cyan

Assert-Equal 'every package gets exactly one rule' 1 @($plan.DetectionRules).Count
Assert-Equal 'and it is the branding key'   'Software\VWG\CM\AUDI_DummyTest_x86_1.0-0001_MUL' $plan.DetectionRules[0].Key
Assert-Equal 'checked on the revision'      'Revision' $plan.DetectionRules[0].ValueName
Assert-Equal 'against the revision itself'  '0001'     $plan.DetectionRules[0].Value
Assert-Equal 'under HKLM'                   'HKLM'     $plan.DetectionRules[0].Hive
Assert-Equal 'named for what it is'         'Branding key' $plan.DetectionRules[0].Source

# A real package name gives the same shape - and never a vendor uninstall key.
$incaPlan = Get-AudiIntegrationPlan -PackageName 'INA_ETAS_INCA_x64_7.5.7-0001_MUL' -EnvironmentCode 'INA' -Rfc 'RFC0012345'
Assert-Equal 'a second package: still one rule' 1 @($incaPlan.DetectionRules).Count
Assert-True  'and it is not a vendor uninstall key' `
    ($incaPlan.DetectionRules[0].Key -notlike '*Uninstall*') $incaPlan.DetectionRules[0].Key

# The plan no longer accepts a SoftIdent at all - a caller that still passes one
# is a caller that has not been updated, and should fail loudly.
$softRefused = $false
try { $null = Get-AudiIntegrationPlan -PackageName 'INA_ETAS_INCA_x64_7.5.7-0001_MUL' -EnvironmentCode 'INA' -Rfc 'R' -SoftIdent 'HKLM:\X' }
catch { $softRefused = $true }
Assert-True 'a SoftIdent parameter is refused' $softRefused
Assert-True 'and the plan carries no SoftIdent field' (-not $incaPlan.PSObject.Properties['SoftIdent'])

# One rule reads as one rule - no dangling "AND" for a condition that is not
# there.
$oneLine = Format-AudiDetectionRule -Rules $incaPlan.DetectionRules
Assert-True 'a single rule reads back without a dangling AND' `
    ($oneLine -and $oneLine -notlike '*AND*') $oneLine
Assert-True 'and it names the branding key it checks' ($oneLine -like '*Software\VWG\CM\*') $oneLine

# Defaults.xml must not quietly grow a second rule back.
$defaultsDoc = [xml](Get-Content -LiteralPath (Join-Path (Get-AudiConfigRoot) 'Defaults.xml') -Raw)
Assert-True 'Defaults.xml declares no SoftIdent detection' ($null -eq $defaultsDoc.SelectSingleNode('/Defaults/SoftIdentDetection'))
Assert-True 'and reads no SoftIdent from any script' ($null -eq $defaultsDoc.SelectSingleNode("//Field[@name='SoftIdent']"))

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
               $plan.DeploymentType, $plan.DetectionRules[0].Key, $plan.Category,
               $plan.ArsGroupName, $plan.ArsDescription) +
             @($plan.Collections | ForEach-Object { $_.Name; $_.Comment })
$leaked = @($sccmBound | Where-Object { $_ -like "*$env:USERNAME*" -or $_ -like '*tester*' })
Assert-True 'nothing bound for SCCM or AD names a person' ($leaked.Count -eq 0) ($leaked -join ' | ')

# The RFC is recorded, not required: the application name is already unique in
# SCCM, so nothing depends on the RFC to identify an object. The rule that DOES
# still hold is the one Audi actually asked for - no personal name on any SCCM
# object - and that is what the template check below enforces.
$comment = Expand-AudiTemplate -Template (Get-AudiDefaults).Comments.application `
                               -Values @{ jobId = 'a1b2c3'; rfc = 'RFC0012345'; package = 'x' }
Assert-True 'the comment says the tool created it' ($comment -like 'Created by the SCCM Integrator*') $comment
Assert-True 'and carries the RFC when there is one' ($comment -like '*RFC0012345*') $comment

# An empty RFC must not leave a label pointing at nothing.
$noRfcComment = Expand-AudiTemplate -Template (Get-AudiDefaults).Comments.application `
                                    -Values @{ jobId = 'a1b2c3'; rfc = ''; package = 'x' }
Assert-True 'an empty RFC is dropped, not left dangling' ($noRfcComment -notlike '*RFC*') $noRfcComment
Assert-True 'and the job id is still there' ($noRfcComment -like '*a1b2c3*') $noRfcComment

# and a config edit must not be able to put it back
Assert-Equal 'a template naming the requester is refused' 1 `
    (@(Test-AudiSccmCommentTemplate -Template 'job {jobId} requested by {requester}').Count)
Assert-Equal 'a clean template passes' 0 `
    (@(Test-AudiSccmCommentTemplate -Template 'job {jobId} | RFC {rfc}').Count)

# ---------------------------------------------------------------- summary
Write-Host ''
# --------------------------------------------- processes the package closes
Write-Host ''
Write-Host 'Reading the process list out of a PSADT script' -ForegroundColor Cyan

# A real Audi package writes this five different ways. The one that matters most
# is the POINTER: VWG_ProcToClose usually holds no names of its own, it points
# at AppProcessesToClose in the session hashtable further up the file. Reading
# the line literally gives '$adtSession.AppProcessesToClose' and no processes.
$procFields = @{ AppProcessesToClose = "@('firefox', 'plugin-container', 'plugin-hang-ui')" }

Assert-Equal 'an empty list means the package closes nothing' 0 `
    (@(Get-AudiProcessName -Raw '@()' -Fields $procFields).Count)
Assert-Equal 'plain names are read in order' 'plugin-container,plugin-hang-ui,firefox' `
    ((@(Get-AudiProcessName -Raw "@('plugin-container', 'plugin-hang-ui', 'firefox')" -Fields $procFields)) -join ',')
Assert-Equal 'a friendly label is dropped, the process name kept' 'firefox,notepad' `
    ((@(Get-AudiProcessName -Raw "@('firefox=Mozilla Firefox', 'notepad=Notepad')" -Fields $procFields)) -join ',')
Assert-Equal 'PSADT 4 process objects give up their names' 'firefox,thunderbird' `
    ((@(Get-AudiProcessName -Raw "@(@{ Name = 'firefox'; Description = 'Mozilla Firefox' }, @{ Name = 'thunderbird'; Description = 'Mail' })" -Fields $procFields)) -join ',')
Assert-Equal 'a pointer into the session hashtable is followed' 'firefox,plugin-container,plugin-hang-ui' `
    ((@(Get-AudiProcessName -Raw '$adtSession.AppProcessesToClose' -Fields $procFields)) -join ',')
Assert-Equal 'a bare comma list still parses' 'firefox,chrome' `
    ((@(Get-AudiProcessName -Raw '@(firefox, chrome)' -Fields $procFields)) -join ',')

# A variable this tool cannot resolve must give NOTHING, never the variable name
# itself - '$SomethingElse' in a Software Center description would be visible to
# every user of the package.
Assert-Equal 'an unresolvable variable yields no processes' 0 `
    (@(Get-AudiProcessName -Raw '$SomethingElse' -Fields $procFields).Count)

# ---- the sentence, exactly as Audi specified it
$fmt  = (Get-AudiDefaults).DescriptionFormat
$made = ($fmt.processPrefixEn.Replace('{processes}', 'plugin-container,plugin-hang-ui,firefox') +
         'Mozilla Firefox is a free and open source web browser which is made by the Mozilla Foundation and its subsidiary, the Mozilla Corporation.').Trim()
Assert-Equal 'the description reads exactly as Audi specified' `
    'The following applications will be closed for installation: plugin-container,plugin-hang-ui,firefox. Mozilla Firefox is a free and open source web browser which is made by the Mozilla Foundation and its subsidiary, the Mozilla Corporation.' `
    $made

# ---- against the real WinMerge package, with the v4.1 "Software Integration
#      Level 3 Request" form (headings without "Short", two Word files in the
#      package, hyphen in the folder name). Skipped where the package is absent.
$wmPkg = 'C:\temp\INA_WinMerge_WinMerge_x64_2.16.58-0001_test'
if (Test-Path -LiteralPath $wmPkg) {
    Write-Host ''
    Write-Host 'The real WinMerge package' -ForegroundColor Cyan
    $wm = Read-AudiPackageDetail -PackagePath $wmPkg
    Assert-True  'the Software Integration request form is the document read' `
        ((Split-Path -Leaf $wm.DocumentPath) -like '*Software Integration Level 3_request*') $wm.DocumentPath
    Assert-True  'not install_document.docx' ((Split-Path -Leaf $wm.DocumentPath) -ne 'install_document.docx')
    Assert-Equal 'install title from the script' 'WinMerge 2.16.58' $wm.Fields['InstallTitle']
    Assert-Equal 'RFC from the script'           'AES-1-020879-A'   $wm.Fields['OrderNumber']
    Assert-Equal 'the English description: processes first, then the SHORT sentence' `
        'The following applications will be closed for installation: WinMergeU,Winmerge. WinMerge is a free differencing and merging software tool for files and folders.' `
        $wm.Fields['ApplicationDescriptionEN']
    Assert-True  'the German description follows the same shape' `
        ($wm.Fields['ApplicationDescriptionDE'] -like 'Folgende Anwendungen werden fuer die Installation geschlossen: WinMergeU,Winmerge. WinMerge ist eine freie Software*') $wm.Fields['ApplicationDescriptionDE']
    Assert-True  'the long paragraph is NOT taken' ($wm.Fields['ApplicationDescriptionEN'] -notlike '*Open Source differencing*')
    Assert-Equal 'both Windows versions ticked'    'Win10x64,Win11x64' (@($wm.OperatingSystems) -join ',')
    Assert-Equal 'the predecessor package is read' 'INA_Winmerge_Winmerge_x64_2.16.46_0001_MUL' $wm.Fields['PredecessorPackage']
    Assert-True  'and that it is to be discontinued' $wm.Fields.Contains('PredecessorDiscontinued')
    $wmSites = @($wm.Fields.Keys | Where-Object { $_ -like 'Site:*' } | ForEach-Object { $_.Substring(5) })
    Assert-Equal 'the five ticked sites, none of the four unticked' 'IN1/NE1,GY1,SJ1,IN9,NE9' ($wmSites -join ',')
    Assert-Equal 'the software category'          'Learning & Collaboration' $wm.Fields['SoftwareCategory']
    Assert-Equal 'SCCM spelling of the folder name' 'INA_WinMerge_WinMerge_x64_2.16.58_0001_test' (Get-AudiSccmName -PackageName (Split-Path -Leaf $wmPkg))
    Assert-Equal 'branding key keeps the hyphen'    'WinMerge_WinMerge_x64_2.16.58-0001_test' (Get-AudiBrandingKey -PackageName (Split-Path -Leaf $wmPkg))
}

# ---- against the real package Audi supplied
$realPkg = 'C:\temp\INA_Microsoft_WindowsDesktopRuntime_x86_10.0.9.50000-0001_ZXX'
if (Test-Path -LiteralPath $realPkg) {
    $realDetail = Read-AudiPackageDetail -PackagePath $realPkg
    Assert-Equal 'the real package gives up its install title' `
        'Microsoft WindowsDesktopRuntimeRuntime 10.0.9.50000' $realDetail.Fields['InstallTitle']
    # Its lists are all @(), so no sentence is added at all.
    Assert-True 'and closes nothing, so no prefix is added' `
        (-not $realDetail.Fields.Contains('ProcessesClosed'))
}

Write-Host ''
if ($script:Fail -eq 0) { Write-Host ("All {0} checks passed." -f $script:Pass) -ForegroundColor Green }
else                    { Write-Host ("{0} passed, {1} FAILED." -f $script:Pass, $script:Fail) -ForegroundColor Red }
Write-Host ''
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
