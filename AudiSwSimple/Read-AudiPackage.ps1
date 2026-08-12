<#
    Reads a package folder and returns everything the integration needs.

        .\Read-AudiPackage.ps1 -PackagePath C:\temp\II1_Lumivero_Citavi_x86_6.19.2.1-0002_MUL

    Three sources, in this order of authority:

      1. THE FOLDER NAME     Site_Publisher_Product_Arch_Version-Revision_Language
                             It is the naming standard, so it is the truth about
                             what this package is.
      2. THE DEPLOYMENT SCRIPT   Deploy-Application.ps1 (PSADT v3) or
                             Invoke-AppDeployToolkit.ps1 (v4). Gives the RFC
                             number and the SoftIdent - the product's own
                             uninstall key, which becomes detection rule 2.
      3. THE REQUEST DOCUMENT    the .docx. Descriptions only, English and German.

    Nothing here touches SCCM.
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PackagePath)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PackagePath)) { throw "No such package folder: $PackagePath" }
$packageName = Split-Path -Leaf $PackagePath

# ---------------------------------------------------------------- 1. the name
#
# Site_Publisher_Product_Arch_Version-Revision_Language
# The product may contain underscores (Acrobat_Reader), and the revision is
# separated by either '-' or '_' depending on the package's age. Both real forms:
#     INA_ETAS_INCA_x64_7.5.7-0001_MUL
#     INA_ADOBE_Acrobat_Reader_x64_2024.1_0003_MUL
$pattern = '^(?<Site>[A-Za-z0-9]{3})_(?<Publisher>[^_]+)_(?<Product>.+)_(?<Arch>x64|x86)_(?<Version>[0-9][^_]*?)[-_](?<Revision>\d+)_(?<Language>[^_]+)$'
$m = [regex]::Match($packageName, $pattern)
if (-not $m.Success) {
    throw "The package name '$packageName' does not match Site_Publisher_Product_Arch_Version-Revision_Language."
}

$package = [ordered]@{
    Name       = $packageName
    Site       = $m.Groups['Site'].Value
    Publisher  = $m.Groups['Publisher'].Value
    Product    = $m.Groups['Product'].Value
    Arch       = $m.Groups['Arch'].Value
    Version    = $m.Groups['Version'].Value
    Revision   = $m.Groups['Revision'].Value
    Language   = $m.Groups['Language'].Value
}

# The branding key is the package name without the site prefix, with the
# revision always joined by '-'. It is what the package writes into the registry
# and what detection rule 1 looks for.
$package.BrandingKey  = '{0}_{1}_{2}_{3}-{4}_{5}' -f $package.Publisher, $package.Product,
                        $package.Arch, $package.Version, $package.Revision, $package.Language
$package.DetectionKey = "Software\VWG\CM\$($package.BrandingKey)"

# ------------------------------------------------------ 2. the deployment script
$package.Rfc       = ''
$package.SoftIdent = ''

$script = Get-ChildItem -LiteralPath $PackagePath -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -in 'Invoke-AppDeployToolkit.ps1', 'Deploy-Application.ps1' } |
          Select-Object -First 1

if ($script) {
    $package.ScriptPath = $script.FullName
    $text = Get-Content -LiteralPath $script.FullName -Raw

    # VWG_OrderNumber = 'AES-1-020627-A'
    $rfc = [regex]::Match($text, "VWG_OrderNumber\s*=\s*['`"]([^'`"]+)")
    if ($rfc.Success) { $package.Rfc = $rfc.Groups[1].Value }

    # VWG_SoftIdent = "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)...\INCA7.5.7 [DisplayVersion=7.5.7]"
    # Take the LAST assignment: the file declares a placeholder version first and
    # the real one further down.
    $soft = [regex]::Matches($text, "VWG_SoftIdent\s*=\s*['`"]([^'`"]+)")
    if ($soft.Count -gt 0) {
        $value = $soft[$soft.Count - 1].Groups[1].Value

        # $($VWG_CurrentRegWOW) is filled in at run time: 'Wow6432Node\' for a
        # 32-bit package, empty otherwise. Resolve it, so what we hand to SCCM is
        # the key that will really be looked at rather than a placeholder.
        $wow = if ($package.Arch -eq 'x86') { 'Wow6432Node\' } else { '' }
        $value = $value -replace '\$\(\s*\$?VWG_CurrentRegWOW\s*\)', $wow
        $value = $value -replace '\$VWG_CurrentRegWOW', $wow
        $package.SoftIdent = $value
    }
}
else {
    $package.ScriptPath = ''
    Write-Warning "No Deploy-Application.ps1 or Invoke-AppDeployToolkit.ps1 under $PackagePath - no RFC and no SoftIdent."
}

# ------------------------------------------------------ 3. the request document
# A .docx is a zip; word/document.xml is the text. Strip the tags and read the
# two descriptions out of what is left. No Word, no COM.
$package.DescriptionEn = ''
$package.DescriptionDe = ''

$doc = Get-ChildItem -LiteralPath $PackagePath -Recurse -Depth 2 -File -Filter '*.docx' -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -notlike '~$*' } | Select-Object -First 1

if ($doc) {
    $package.DocumentPath = $doc.FullName
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($doc.FullName)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -replace '\\', '/' -eq 'word/document.xml' } | Select-Object -First 1
            if ($entry) {
                $reader = New-Object System.IO.StreamReader($entry.Open())
                try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }

                # Each paragraph becomes a line, then the tags go. The form is a
                # table: a label on one line, its answer on the next.
                $plain = $xml -replace '</w:p>', "`n" -replace '<[^>]+>', ''
                $plain = [System.Net.WebUtility]::HtmlDecode($plain)
                $lines = @($plain -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

                # The line AFTER the label. "Short description of the product in
                # English", then the description. Falls back to the detailed one
                # when the short is empty, which is how the packagers do it.
                function Get-Answer { param([string[]]$Lines, [string]$Label)
                    for ($i = 0; $i -lt $Lines.Count - 1; $i++) {
                        if ($Lines[$i] -match $Label) { return $Lines[$i + 1] }
                    }
                    return ''
                }

                $package.DescriptionEn = Get-Answer $lines '^Short\s+description\s+of\s+the\s+product\s+in\s+English'
                if (-not $package.DescriptionEn) { $package.DescriptionEn = Get-Answer $lines '^Detailed\s+description\s+of\s+the\s+product\s+in\s+English' }

                $package.DescriptionDe = Get-Answer $lines '^Short\s+description\s+of\s+the\s+product\s+in\s+German'
                if (-not $package.DescriptionDe) { $package.DescriptionDe = Get-Answer $lines '^Detailed\s+description\s+of\s+the\s+product\s+in\s+German' }

                # A label with no answer picks up the NEXT label. Discard that.
                if ($package.DescriptionEn -match '(?i)^(short|detailed)\s+description') { $package.DescriptionEn = '' }
                if ($package.DescriptionDe -match '(?i)^(short|detailed)\s+description') { $package.DescriptionDe = '' }
            }
        }
        finally { $zip.Dispose() }
    }
    catch { Write-Warning "Could not read $($doc.Name): $($_.Exception.Message)" }
}
else { $package.DocumentPath = '' }

# Fall back to something sensible rather than publishing an empty description.
if (-not $package.DescriptionEn) { $package.DescriptionEn = '{0} - {1} - {2}' -f $package.Publisher, $package.Product, $package.Version }
if (-not $package.DescriptionDe) { $package.DescriptionDe = $package.DescriptionEn }

$package.DisplayName = '{0} - {1} - {2}' -f $package.Publisher, $package.Product, $package.Version

return [pscustomobject]$package
