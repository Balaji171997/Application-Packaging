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
    # Also drops a vendor document beside the request form, newer than it, so a
    # test can prove the form is chosen by NAME and not by date.
    [switch]$WithDecoyDocument,
    # Also drops an install_document.docx with its own English short
    # description, so a test can prove it is read AFTER the form and BEFORE
    # anything else.
    [switch]$WithInstallDocument,
    # Writes the request form HERE instead of into the package - the way Audi
    # keep forms apart from packages, one folder per request under a documents
    # location. The package then holds the script only.
    [string]$DocumentTarget,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$package = Join-Path $Path $PackageName
if ((Test-Path -LiteralPath $package) -and -not $Force) {
    return [pscustomobject]@{ Path = $package; Created = $false }
}

New-Item -ItemType Directory -Path (Join-Path $package 'Files') -Force | Out-Null

# The script must agree with the folder name, or the sample would contradict
# itself.
$arch = if ($PackageName -match '_(x86|x64|ALL)_') { $Matches[1] } else { 'x64' }

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
    # What Software Center shows. This is the install title the window reads.
    InstallTitle    = 'Adobe Acrobat Reader 2024.1'
}

# A real package also declares VWG_SoftIdent, twice. It is kept here so the
# sample looks like a real script - the tool does not read it: detection is the
# branding key only.
[string] $Global:VWG_SoftIdent   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AcroRead2024 [DisplayVersion=2024.1]'
[string] $Global:VWG_Portfv      = 'Adobe'
[string] $Global:VWG_OrderNumber = 'AES-1-000123-A'

#region CUSTOM APPLICATION VARIABLES AND FUNCTIONS
##================================================
## CUSTOM APPLICATION VARIABLES BEGIN
##================================================
[string]$Global:VWG_SoftIdent = "HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\Windows\CurrentVersion\Uninstall\AcroRead2024 [DisplayVersion=2024.1]"
##================================================
## CUSTOM APPLICATION VARIABLES END
##================================================
#endregion

function Install-ADTDeployment {
    Start-ADTMsiProcess -Action Install -FilePath 'AcroRead.msi'
}

function Uninstall-ADTDeployment {
    Start-ADTMsiProcess -Action Uninstall -FilePath 'AcroRead.msi'
}
'@
$adt = $adt -replace "AppArch         = 'x64'", "AppArch         = '$arch'"
Set-Content -LiteralPath (Join-Path $package 'Invoke-AppDeployToolkit.ps1') -Value $adt -Encoding UTF8
Set-Content -LiteralPath (Join-Path $package 'Files\AcroRead.msi') -Value 'placeholder installer' -Encoding ASCII

# --------------------------------------------------- install instruction .docx
# A .docx is a zip of XML parts, so one can be written without Word installed.
# The lines below are laid out the way the patterns in Defaults.xml expect.
# Laid out like a real Audi "Software Package Request": a table, so each label
# is on one line and its value on the next, indented by a tab.
# The document is consulted for the description only. A detailed description is
# included as well, so the short-then-detailed preference can be exercised.
$lines = @(
    'Software Package Request'
    'Basic information'
    'Manufacturer'
    "`tAdobe Systems Incorporated"
    'Product Name'
    "`tAcrobat Reader"
    'Short description of the product in German'
    "`tLiest, druckt und kommentiert PDF-Dokumente."
    'Short description of the product in English'
    "`tReads, prints and annotates PDF documents."
    'Detailed description of the product in German'
    "`tAusfuehrliche Beschreibung, nur als Rueckfallebene."
    'Detailed description of the product in English'
    "`tDetailed description, used only when the short one is missing."
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

# Named the way Audi's request form arrives now:
#   <Product>-<Version>_Software Integration Level 3_request_(1).docx
# "Software Integration" is the constant part, and it is what Defaults.xml
# looks for first when a package holds more than one Word file.
$docx = $(if ($DocumentTarget) {
    if (-not (Test-Path -LiteralPath $DocumentTarget)) { New-Item -ItemType Directory -Path $DocumentTarget -Force | Out-Null }
    Join-Path $DocumentTarget 'Acrobat Reader-2024_1_Software Integration Level 3_request_(1).docx'
} else {
    Join-Path $package 'Acrobat Reader-2024_1_Software Integration Level 3_request_(1).docx'
})

function Write-SampleDocx { param([string]$Target, [hashtable]$Content)
    if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Force }
    # Entries are created by name rather than with CreateFromDirectory, because
    # on Windows that helper writes the separator as a BACKSLASH
    # ("word\document.xml"). The OPC format requires a forward slash, and
    # anything reading the file by the correct part name then finds nothing.
    $stream = [System.IO.File]::Open($Target, [System.IO.FileMode]::Create)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Content.Keys) {
                $entry  = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
                $writer = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
                try { $writer.Write([string]$Content[$name]) } finally { $writer.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

Write-SampleDocx -Target $docx -Content $parts

if ($WithDecoyDocument) {
    # A vendor document, laid out with the SAME headings so that if it were
    # read by mistake the wrong description would visibly come through - and
    # written after the form, so it is the newer file.
    $decoyLines = @('Vendor product sheet', 'Short description of the product in English', "`tWRONG - this is the vendor sheet, not the request form.")
    $decoyParas = ($decoyLines | ForEach-Object { '<w:p><w:r><w:t xml:space="preserve">' + $_ + '</w:t></w:r></w:p>' }) -join ''
    $decoy = [ordered]@{}
    foreach ($k in $parts.Keys) { $decoy[$k] = $parts[$k] }
    $decoy['word/document.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' + $decoyParas + '</w:body></w:document>'
    $decoyPath = Join-Path $package 'Files\Acrobat Reader product sheet.docx'
    Write-SampleDocx -Target $decoyPath -Content $decoy
    (Get-Item -LiteralPath $decoyPath).LastWriteTime = (Get-Item -LiteralPath $docx).LastWriteTime.AddMinutes(10)
}

if ($WithInstallDocument) {
    # The install instruction, as it ships beside the form. It carries an
    # English short description of its own - different wording, so a test can
    # tell which file a value came from - and NO German one.
    $instLines = @('Install instruction', 'Short description of the product in English', "`tFrom the install document.")
    $instParas = ($instLines | ForEach-Object { '<w:p><w:r><w:t xml:space="preserve">' + $_ + '</w:t></w:r></w:p>' }) -join ''
    $inst = [ordered]@{}
    foreach ($k in $parts.Keys) { $inst[$k] = $parts[$k] }
    $inst['word/document.xml'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' + $instParas + '</w:body></w:document>'
    $instPath = Join-Path $package 'install_document.docx'
    Write-SampleDocx -Target $instPath -Content $inst
    (Get-Item -LiteralPath $instPath).LastWriteTime = (Get-Item -LiteralPath $docx).LastWriteTime.AddMinutes(20)
}

return [pscustomobject]@{ Path = $package; Created = $true }
