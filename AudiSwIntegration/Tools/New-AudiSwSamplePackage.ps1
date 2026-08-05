# ==============================================================================
#  Builds a realistic sample package, for trying the tool out.
# ==============================================================================
#      .\Tools\New-AudiSwSamplePackage.ps1 -Path D:\Packages
#
#  It writes a genuine PSADT v4 script and a genuine .docx install instruction,
#  so "Read details" in the window has real content to parse. Nothing here is
#  planted into the window - every value the window shows has been read back out
#  of these files, which is the point of having a sample at all.
#
#  ASCII only.
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    # Real Audi form: version and revision joined by a hyphen, so the name is the
    # site code followed by the branding key.
    [string]$PackageName = 'ICZ_ADOBE_Acrobat_Reader_x64_2024.1-0003_MUL',
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$package = Join-Path $Path $PackageName
if ((Test-Path -LiteralPath $package) -and -not $Force) {
    return [pscustomobject]@{ Path = $package; Created = $false }
}

New-Item -ItemType Directory -Path (Join-Path $package 'Files') -Force | Out-Null

# ------------------------------------------------------------ PSADT v4 script
$adt = @'
<#
    Sample PSADT v4 deployment script - for testing the integration tool only.
#>
[CmdletBinding()]
param()

$adtSession = @{
    AppVendor       = 'Adobe'
    AppName         = 'Acrobat Reader'
    AppVersion      = '2024.1'
    AppArch         = 'x64'
    AppLang         = 'MUL'
    AppRevision     = '0003'
    AppScriptAuthor = 'Packaging Team'
}

function Install-ADTDeployment {
    Start-ADTMsiProcess -Action Install -FilePath 'AcroRead.msi'
}

function Uninstall-ADTDeployment {
    Start-ADTMsiProcess -Action Uninstall -FilePath 'AcroRead.msi'
}
'@
Set-Content -LiteralPath (Join-Path $package 'Invoke-AppDeployToolkit.ps1') -Value $adt -Encoding UTF8
Set-Content -LiteralPath (Join-Path $package 'Files\AcroRead.msi') -Value 'placeholder installer' -Encoding ASCII

# --------------------------------------------------- install instruction .docx
# A .docx is a zip of XML parts, so one can be written without Word installed.
# The lines below are laid out the way the patterns in Defaults.xml expect.
# Laid out like a real Audi "Software Package Request": a table, so each label
# is on one line and its value on the next, indented by a tab.
$lines = @(
    'Software Package Request'
    'Basic information'
    'Manufacturer'
    "`tAdobe Systems Incorporated"
    'Product Name'
    "`tAcrobat Reader"
    'Version / Build'
    "`t2024.1"
    'Which operating systems does the software support?'
    "`t$([char]0x2612)Windows 10"
    "$([char]0x2612)Windows 11"
    'Short description of the product in German'
    "`tLiest, druckt und kommentiert PDF-Dokumente."
    'Short description of the product in English'
    "`tReads, prints and annotates PDF documents."
)
$paragraphs = ($lines | ForEach-Object {
    $safe = $_ -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    '<w:p><w:r><w:t xml:space="preserve">' + $safe + '</w:t></w:r></w:p>'
}) -join ''

$parts = [ordered]@{
    '[Content_Types].xml' = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
'@
    '_rels/.rels' = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
'@
    'word/document.xml' =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' +
        $paragraphs + '</w:body></w:document>'
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$docx = Join-Path $package 'Install instruction.docx'
if (Test-Path -LiteralPath $docx) { Remove-Item -LiteralPath $docx -Force }

# Entries are created by name rather than with CreateFromDirectory, because on
# Windows that helper writes the separator as a BACKSLASH ("word\document.xml").
# The OPC format requires a forward slash, and anything reading the file by the
# correct part name then finds nothing at all.
$stream = [System.IO.File]::Open($docx, [System.IO.FileMode]::Create)
try {
    $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $parts.Keys) {
            $entry  = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
            $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
            try { $writer.Write([string]$parts[$name]) } finally { $writer.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}
finally { $stream.Dispose() }

return [pscustomobject]@{ Path = $package; Created = $true }
