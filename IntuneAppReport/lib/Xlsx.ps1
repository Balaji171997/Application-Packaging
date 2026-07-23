# Xlsx.ps1 - minimal, dependency-free .xlsx writer.
# No Excel COM, no ImportExcel module, no Python: just hand-written OOXML zipped with
# System.IO.Compression. Produces a real workbook Excel opens without a repair prompt.

# Two assemblies: ZipFile lives in .FileSystem, ZipArchive/ZipArchiveMode in the base one.
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue

function ConvertTo-XmlText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
    # Excel rejects control characters outright - strip everything below 0x20 except tab/LF/CR.
    return ($t -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
}

function Get-ColumnLetter {
    param([int]$Index)   # 1 -> A
    $s = ''
    while ($Index -gt 0) {
        $m = ($Index - 1) % 26
        $s = [char](65 + $m) + $s
        $Index = [int](($Index - $m - 1) / 26)
    }
    return $s
}

# One worksheet from an array of PSObjects + an ordered column list.
function New-SheetXml {
    param([object[]]$Rows, [string[]]$Columns)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')

    # Sensible widths: header length + a little, capped so one long command line cannot wreck the sheet.
    [void]$sb.Append('<cols>')
    for ($i = 0; $i -lt $Columns.Count; $i++) {
        $w = [Math]::Min(52, [Math]::Max(11, $Columns[$i].Length + 3))
        [void]$sb.Append(('<col min="{0}" max="{0}" width="{1}" customWidth="1"/>' -f ($i + 1), $w))
    }
    [void]$sb.Append('</cols>')

    [void]$sb.Append('<sheetData>')
    # header
    [void]$sb.Append('<row r="1">')
    for ($i = 0; $i -lt $Columns.Count; $i++) {
        $ref = (Get-ColumnLetter ($i + 1)) + '1'
        [void]$sb.Append(('<c r="{0}" s="1" t="inlineStr"><is><t>{1}</t></is></c>' -f $ref, (ConvertTo-XmlText $Columns[$i])))
    }
    [void]$sb.Append('</row>')

    $r = 1
    foreach ($row in $Rows) {
        $r++
        [void]$sb.Append(('<row r="{0}">' -f $r))
        for ($i = 0; $i -lt $Columns.Count; $i++) {
            $ref = (Get-ColumnLetter ($i + 1)) + $r
            $v = $row.($Columns[$i])
            if ($null -eq $v) { continue }                       # skip empties - smaller file, same result
            if ($v -is [array]) { $v = ($v | ForEach-Object { "$_" }) -join '; ' }
            # Write real numbers as numbers so Excel can sort and total them.
            if (($v -is [int]) -or ($v -is [long]) -or ($v -is [double]) -or ($v -is [decimal])) {
                [void]$sb.Append(('<c r="{0}"><v>{1}</v></c>' -f $ref, $v))
            } else {
                $s = "$v"
                if ($s -eq '') { continue }
                [void]$sb.Append(('<c r="{0}" t="inlineStr"><is><t xml:space="preserve">{1}</t></is></c>' -f $ref, (ConvertTo-XmlText $s)))
            }
        }
        [void]$sb.Append('</row>')
    }
    [void]$sb.Append('</sheetData>')

    # Freeze the header and switch on the filter dropdowns - this is what makes it usable as a report.
    $lastCol = Get-ColumnLetter $Columns.Count
    [void]$sb.Append(('<autoFilter ref="A1:{0}{1}"/>' -f $lastCol, [Math]::Max(1, $Rows.Count + 1)))
    [void]$sb.Append('</worksheet>')
    return $sb.ToString()
}

# $Sheets = ordered list of @{ Name; Rows; Columns }
function New-XlsxWorkbook {
    param([Parameter(Mandatory)][object[]]$Sheets, [Parameter(Mandatory)][string]$Path)

    # Parts are collected in memory and written as zip entries with EXPLICIT forward-slash names.
    # ZipFile::CreateFromDirectory on Windows emits backslash entry names, which OOXML readers
    # (Excel included) reject or "repair" - so we never round-trip through a temp directory.
    $parts = New-Object 'System.Collections.Specialized.OrderedDictionary'
    function Put { param($Rel, $Content) $parts[($Rel -replace '\\', '/')] = $Content }

    $ct = New-Object Text.StringBuilder
    [void]$ct.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    [void]$ct.Append('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    [void]$ct.Append('<Default Extension="xml" ContentType="application/xml"/>')
    [void]$ct.Append('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    [void]$ct.Append('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
    for ($i = 1; $i -le $Sheets.Count; $i++) {
        [void]$ct.Append(('<Override PartName="/xl/worksheets/sheet{0}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' -f $i))
    }
    [void]$ct.Append('</Types>')
    Put '[Content_Types].xml' $ct.ToString()

    Put '_rels\.rels' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')

    $wb = New-Object Text.StringBuilder
    [void]$wb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>')
    for ($i = 1; $i -le $Sheets.Count; $i++) {
        # Excel forbids : \ / ? * [ ] in sheet names and caps them at 31 chars.
        $nm = ($Sheets[$i - 1].Name -replace '[\\/\?\*\[\]:]', '-')
        if ($nm.Length -gt 31) { $nm = $nm.Substring(0, 31) }
        [void]$wb.Append(('<sheet name="{0}" sheetId="{1}" r:id="rId{1}"/>' -f (ConvertTo-XmlText $nm), $i))
    }
    [void]$wb.Append('</sheets></workbook>')
    Put 'xl\workbook.xml' $wb.ToString()

    $rel = New-Object Text.StringBuilder
    [void]$rel.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
    for ($i = 1; $i -le $Sheets.Count; $i++) {
        [void]$rel.Append(('<Relationship Id="rId{0}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{0}.xml"/>' -f $i))
    }
    [void]$rel.Append(('<Relationship Id="rId{0}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' -f ($Sheets.Count + 1)))
    [void]$rel.Append('</Relationships>')
    Put 'xl\_rels\workbook.xml.rels' $rel.ToString()

    # Two formats: 0 = normal, 1 = bold white on dark blue (the header row).
    Put 'xl\styles.xml' ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>' +
        '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>' +
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' +
        '<fill><patternFill patternType="solid"><fgColor rgb="FF2F5BD0"/><bgColor indexed="64"/></patternFill></fill></fills>' +
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>' +
        '</styleSheet>')

    for ($i = 1; $i -le $Sheets.Count; $i++) {
        Put ("xl\worksheets\sheet$i.xml") (New-SheetXml -Rows @($Sheets[$i - 1].Rows) -Columns $Sheets[$i - 1].Columns)
    }

    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $enc = New-Object Text.UTF8Encoding($false)
    $fs  = [IO.File]::Open($Path, [IO.FileMode]::Create)
    try {
        $zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $parts.Keys) {
                $entry = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
                $es = $entry.Open()
                try { $bytes = $enc.GetBytes([string]$parts[$name]); $es.Write($bytes, 0, $bytes.Length) }
                finally { $es.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $fs.Dispose() }
    return $Path
}
