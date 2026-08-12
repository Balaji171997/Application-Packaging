# Builds fixtures for testing the migrator engine: a v3 package, a v4 package, an .ico, and a
# request-form .docx carrying the short + detailed description cells.
param([string]$Root)
$ErrorActionPreference = 'Stop'
if (Test-Path $Root) { Remove-Item $Root -Recurse -Force }
New-Item $Root -ItemType Directory -Force | Out-Null

$toolLib = Join-Path (Split-Path -Parent $PSScriptRoot) 'Lib'

# ---------- v3 package ----------------------------------------------------------------------
$v3 = Join-Path $Root 'Contoso_TestAppV3_x64_1.0.0-0001_MUL'
New-Item (Join-Path $v3 'Files') -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $toolLib 'PSADTv3Utilities\Deploy-Application.exe') $v3 -Force
Set-Content (Join-Path $v3 'Deploy-Application.ps1') -Value '# fake v3 psadt script' -Encoding UTF8
Set-Content (Join-Path $v3 'Files\payload.txt') -Value ('x' * 2048) -Encoding UTF8

# ---------- v4 package (launcher nested one level down, like a real corpus) ------------------
$v4root = Join-Path $Root 'Contoso_TestAppV4_x64_2.5.1-0003_ENU'
$v4 = Join-Path $v4root 'MUL_x64_0001'
New-Item (Join-Path $v4 'Files') -ItemType Directory -Force | Out-Null
Set-Content (Join-Path $v4 'Invoke-AppDeployToolkit.exe') -Value 'MZ fake' -Encoding ASCII
Set-Content (Join-Path $v4 'Invoke-AppDeployToolkit.ps1') -Value '# fake v4 psadt script' -Encoding UTF8
Set-Content (Join-Path $v4 'Files\payload.txt') -Value ('y' * 4096) -Encoding UTF8

# ---------- an icon in the v4 package (Icons folder at package root) -------------------------
Add-Type -AssemblyName System.Drawing
$icoDir = Join-Path $v4root 'Icons'
New-Item $icoDir -ItemType Directory -Force | Out-Null
$bmp = New-Object System.Drawing.Bitmap(64, 64)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::MediumSeaGreen)
$g.FillEllipse([System.Drawing.Brushes]::White, 12, 12, 40, 40)
$g.Dispose()
$icoPath = Join-Path $icoDir 'TestAppV4.ico'
# write a real .ico (single 64x64 PNG-compressed frame)
$pngMs = New-Object System.IO.MemoryStream
$bmp.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
$png = $pngMs.ToArray(); $pngMs.Dispose(); $bmp.Dispose()
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)      # ICONDIR
$bw.Write([byte]64); $bw.Write([byte]64); $bw.Write([byte]0); $bw.Write([byte]0)
$bw.Write([uint16]1); $bw.Write([uint16]32)
$bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
$bw.Write($png)
$bw.Flush(); $bw.Close(); $fs.Close()

# ---------- request-form .docx with the two description cells --------------------------------
function New-TestDocx {
    param([string]$Path, [string]$Short, [string]$Detailed,
          [string]$ShortLabel = 'Short description of the product in English',
          [string]$DetailedLabel = 'Detailed description of the product in English')
    $tmp = Join-Path $env:TEMP ("docx_" + [guid]::NewGuid().ToString('N'))
    New-Item (Join-Path $tmp '_rels') -ItemType Directory -Force | Out-Null
    New-Item (Join-Path $tmp 'word') -ItemType Directory -Force | Out-Null
    @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
'@ | Set-Content -LiteralPath (Join-Path $tmp '[Content_Types].xml') -Encoding UTF8
    @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
'@ | Set-Content (Join-Path $tmp '_rels\.rels') -Encoding UTF8
    $cells = @($ShortLabel, $Short, $DetailedLabel, $Detailed, 'Dependencies', 'none')
    $rows = ($cells | ForEach-Object { "<w:tc><w:p><w:r><w:t xml:space=`"preserve`">$([System.Security.SecurityElement]::Escape($_))</w:t></w:r></w:p></w:tc>" }) -join ''
    $doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
           '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:tbl><w:tr>' +
           $rows + '</w:tr></w:tbl></w:body></w:document>'
    Set-Content (Join-Path $tmp 'word\document.xml') -Value $doc -Encoding UTF8
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $Path) { Remove-Item $Path -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tmp, $Path)
    Remove-Item $tmp -Recurse -Force
}
New-TestDocx -Path (Join-Path $v4root 'Installation instructions.docx') `
             -Short 'Compact CAD viewer for shop-floor terminals.' `
             -Detailed 'Installs the viewer silently, registers the file associations and pins the shortcut to the start menu. Requires the runtime package.'

# a package whose docx has ONLY a placeholder in the short cell
$v3docx = Join-Path $v3 'Installation instructions.docx'
New-TestDocx -Path $v3docx -Short 'Click here to enter text.' -Detailed 'Deploys the legacy client in silent mode.'

# ---------- scenario 3: a PLAIN installer, no toolkit at all ---------------------------------
# Mirrors the real shape: the SCCM content location points at the folder holding the executable,
# while Icons\ and the request form sit at the PACKAGE root one level above it.
$plainRoot = Join-Path $Root 'Contoso_PlainSetup_x64_9.9.9-0001_ENU'
$plainBin  = Join-Path $plainRoot 'Source'
New-Item $plainBin -ItemType Directory -Force | Out-Null
Set-Content (Join-Path $plainBin 'setup.exe') -Value 'MZ fake plain installer' -Encoding ASCII
Set-Content (Join-Path $plainBin 'setup.ini') -Value '[opts]' -Encoding UTF8
# icon at the PACKAGE root, not next to the exe
$pIcoDir = Join-Path $plainRoot 'Icons'
New-Item $pIcoDir -ItemType Directory -Force | Out-Null
Copy-Item $icoPath (Join-Path $pIcoDir 'PlainSetup.ico') -Force
# request form at the package root, in GERMAN
New-TestDocx -Path (Join-Path $plainRoot 'Installationsanweisung.docx') `
             -Short 'Klick hier um Text einzugeben.' `
             -Detailed 'Installiert das Werkzeug unbeaufsichtigt und legt die Verknuepfung an.' `
             -ShortLabel 'Kurzbeschreibung' -DetailedLabel 'Ausfuehrliche Beschreibung'

Write-Host "Fixtures at $Root"
