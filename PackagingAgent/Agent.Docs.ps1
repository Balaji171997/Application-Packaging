##############################################################
# Agent.Docs.ps1
# Deterministic readers for the documents that arrive with an order - no Word/Excel, no Python: the OOXML zip is
# read directly (System.IO.Compression), so this works on a locked-down VDI and in a background runspace.
#   Read-AgentDocx : paragraphs + tables IN ORDER (checkbox glyphs kept: ☐ / ☒), and every embedded picture with
#                    the caption text next to it -> the AO's wizard screenshots can be shown to the model.
#   Read-AgentXlsx : every sheet as rows of cell text (shared strings + inline strings resolved).
#   Find-AgentOrderDocs : which files in an order folder are the AO form, the complexity matrix, the RITM marker, etc.
##############################################################
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# Read one entry of a zip (docx/xlsx) as text. $null when missing.
function Get-AgentZipEntryText {
    param($Zip, [string]$Name)
    $e = $Zip.GetEntry($Name); if (-not $e) { return $null }
    $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
    try { return $sr.ReadToEnd() } finally { $sr.Close() }
}
function Get-AgentZipEntryBytes {
    param($Zip, [string]$Name)
    $e = $Zip.GetEntry($Name); if (-not $e) { return $null }
    $s = $e.Open(); $ms = New-Object IO.MemoryStream
    try { $s.CopyTo($ms); return $ms.ToArray() } finally { $s.Close(); $ms.Dispose() }
}

# Text of one w:p node: runs, tabs, breaks, symbol chars, checkbox content controls, and [IMAGE n] placeholders for
# drawings. $ImageSink (List) receives @{ RelId; ParagraphIndex } for each picture found.
function Get-AgentDocxParagraphText {
    param($Node, $Ns, $ImageSink, [int]$ParaIndex)
    $sb = New-Object Text.StringBuilder
    $nodes = $Node.SelectNodes('.//w:t | .//w:tab | .//w:br | .//w:cr | .//w:sym | .//w:drawing | .//w:pict | .//w14:checkbox', $Ns)
    foreach ($n in $nodes) {
        switch ($n.LocalName) {
            't'        { [void]$sb.Append($n.InnerText) }
            'tab'      { [void]$sb.Append("`t") }
            'br'       { [void]$sb.Append("`n") }
            'cr'       { [void]$sb.Append("`n") }
            'sym'      { $ch = $n.GetAttribute('char', $Ns.LookupNamespace('w')); if ($ch -match '^[0-9A-Fa-f]{4}$') { $code = [Convert]::ToInt32($ch, 16); if ($code -ge 0xF000) { $code -= 0xF000 }; [void]$sb.Append([char]$code) } }
            'checkbox' { $ck = $n.SelectSingleNode('w14:checked', $Ns); $v = if ($ck) { $ck.GetAttribute('val', $Ns.LookupNamespace('w14')) } else { '0' }
                         # the visible glyph is ALSO in a w:t right after the control; only add ours when the run text lacks one
                         if ($v -in '1','true') { [void]$sb.Append([char]0x2612) } else { [void]$sb.Append([char]0x2610) } }
            'drawing'  { $blip = $n.SelectSingleNode('.//a:blip', $Ns); if ($blip) { $rid = $blip.GetAttribute('embed', $Ns.LookupNamespace('r')); if ($rid) { $ImageSink.Add(@{ RelId = $rid; ParagraphIndex = $ParaIndex }); [void]$sb.Append(" [IMAGE $($ImageSink.Count)] ") } } }
            'pict'     { $im = $n.SelectSingleNode('.//v:imagedata', $Ns); if ($im) { $rid = $im.GetAttribute('id', $Ns.LookupNamespace('r')); if ($rid) { $ImageSink.Add(@{ RelId = $rid; ParagraphIndex = $ParaIndex }); [void]$sb.Append(" [IMAGE $($ImageSink.Count)] ") } } }
        }
    }
    # a checkbox control duplicates its glyph (control + literal run): collapse "☒☒" / "☐☐"
    $t = $sb.ToString() -replace '([\u2610\u2612])\1', '$1'
    return $t
}

# Read a .docx into ordered text blocks + extracted images.
# Returns @{ Ok; Path; Text (all blocks joined); Blocks = @(@{ Kind='p'|'table'; Text }); Images = @(@{ Index; File; Caption; MediaName }); Notes }.
# Images are written to $ImageDir (created) as their original bytes (png/jpeg/emf...); the caller converts for the model.
function Read-AgentDocx {
    param([Parameter(Mandatory)][string]$Path, [string]$ImageDir, [int]$MaxBlocks = 4000)
    $out = @{ Ok = $false; Path = $Path; Text = ''; Blocks = @(); Images = @(); Notes = @() }
    if (-not (Test-Path -LiteralPath $Path)) { $out.Notes += 'file not found'; return $out }
    if ([IO.Path]::GetExtension($Path) -ine '.docx') { $out.Notes += 'not a .docx (legacy .doc cannot be read without Word)'; return $out }
    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        $xml = Get-AgentZipEntryText -Zip $zip -Name 'word/document.xml'
        if (-not $xml) { $out.Notes += 'word/document.xml missing'; return $out }
        $doc = New-Object Xml.XmlDocument; $doc.PreserveWhitespace = $true; $doc.LoadXml($xml)
        $ns = New-Object Xml.XmlNamespaceManager($doc.NameTable)
        $ns.AddNamespace('w',   'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        $ns.AddNamespace('w14', 'http://schemas.microsoft.com/office/word/2010/wordml')
        $ns.AddNamespace('a',   'http://schemas.openxmlformats.org/drawingml/2006/main')
        $ns.AddNamespace('r',   'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
        $ns.AddNamespace('v',   'urn:schemas-microsoft-com:vml')
        # relationships -> media names
        $rels = @{}
        $relXml = Get-AgentZipEntryText -Zip $zip -Name 'word/_rels/document.xml.rels'
        if ($relXml) {
            $rd = New-Object Xml.XmlDocument; $rd.LoadXml($relXml)
            foreach ($r in $rd.DocumentElement.ChildNodes) { if ($r.LocalName -eq 'Relationship') { $rels["$($r.GetAttribute('Id'))"] = "$($r.GetAttribute('Target'))" } }
        }
        $body = $doc.SelectSingleNode('/w:document/w:body', $ns)
        if (-not $body) { $out.Notes += 'no body'; return $out }
        $blocks = New-Object System.Collections.Generic.List[object]
        $images = New-Object System.Collections.Generic.List[object]
        $paraIdx = 0
        # Walk body-level children; descend into content controls (w:sdt) so the form's tagged fields are read in place.
        $queue = New-Object System.Collections.Generic.Queue[object]
        foreach ($ch in $body.ChildNodes) { $queue.Enqueue($ch) }
        $ordered = New-Object System.Collections.Generic.List[object]
        while ($queue.Count) {
            $n = $queue.Dequeue()
            switch ($n.LocalName) {
                'p'   { $ordered.Add($n) }
                'tbl' { $ordered.Add($n) }
                'sdt' { $c = $n.SelectSingleNode('w:sdtContent', $ns); if ($c) { $inner = @($c.ChildNodes); $tmp = New-Object System.Collections.Generic.List[object]; foreach ($i in $inner) { $tmp.Add($i) }
                        # re-queue in order right after the current position: simplest is to process now recursively
                        foreach ($i in $tmp) { if ($i.LocalName -eq 'p' -or $i.LocalName -eq 'tbl') { $ordered.Add($i) } elseif ($i.LocalName -eq 'sdt') { $c2 = $i.SelectSingleNode('w:sdtContent', $ns); if ($c2) { foreach ($j in $c2.ChildNodes) { if ($j.LocalName -in 'p','tbl') { $ordered.Add($j) } } } } } } }
                default {}
            }
        }
        foreach ($n in $ordered) {
            if ($blocks.Count -ge $MaxBlocks) { $out.Notes += "truncated at $MaxBlocks blocks"; break }
            if ($n.LocalName -eq 'p') {
                $paraIdx++
                $t = Get-AgentDocxParagraphText -Node $n -Ns $ns -ImageSink $images -ParaIndex $paraIdx
                $t = "$t".Trim()
                if (-not $t) { continue }
                if ($t -match 'PAGEREF _Toc|^TOC \\o|^\s*HYPERLINK ') { continue }   # table-of-contents field junk
                $blocks.Add(@{ Kind = 'p'; Text = $t; Index = $paraIdx })
            } elseif ($n.LocalName -eq 'tbl') {
                $rowsOut = New-Object System.Collections.Generic.List[string]
                # Rows and cells may be wrapped in content controls (the form's tagged fields sit at CELL level:
                # w:tr > w:sdt > w:sdtContent > w:tc) - a plain w:tc walk silently drops every VALUE cell.
                foreach ($row in $n.SelectNodes('w:tr | w:sdt/w:sdtContent/w:tr', $ns)) {
                    $cells = New-Object System.Collections.Generic.List[string]
                    foreach ($cell in $row.SelectNodes('w:tc | w:sdt/w:sdtContent/w:tc', $ns)) {
                        $ct = New-Object System.Collections.Generic.List[string]
                        foreach ($cp in $cell.SelectNodes('.//w:p', $ns)) { $paraIdx++; $pt = (Get-AgentDocxParagraphText -Node $cp -Ns $ns -ImageSink $images -ParaIndex $paraIdx).Trim(); if ($pt) { $ct.Add($pt) } }
                        $cells.Add(($ct -join ' / '))
                    }
                    $line = ($cells -join ' | ').Trim()
                    if ($line -and $line -ne '|' -and ($line -replace '[\s|]', '')) { $rowsOut.Add($line) }
                }
                if ($rowsOut.Count) { $blocks.Add(@{ Kind = 'table'; Text = ($rowsOut -join "`n"); Index = $paraIdx }) }
            }
        }
        $out.Blocks = $blocks.ToArray()
        $out.Text = (($blocks | ForEach-Object { if ($_.Kind -eq 'table') { "[TABLE]`n$($_.Text)`n[/TABLE]" } else { $_.Text } }) -join "`n")
        # Images: write bytes out, caption = the paragraph's own text (minus placeholder) or the next paragraph.
        if ($images.Count) {
            if (-not $ImageDir) { $ImageDir = Join-Path $env:TEMP ("PackagingAgent\docimg_" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
            try { New-Item -ItemType Directory -Force -Path $ImageDir | Out-Null } catch {}
            $blockByIdx = @{}; for ($i = 0; $i -lt $blocks.Count; $i++) { $blockByIdx[[int]$blocks[$i].Index] = $i }
            $k = 0
            foreach ($im in $images) {
                $k++
                $target = $rels["$($im.RelId)"]; if (-not $target) { continue }
                $entryName = if ($target -match '^/') { $target.TrimStart('/') } else { "word/$target" }
                $bytes = Get-AgentZipEntryBytes -Zip $zip -Name $entryName
                if (-not $bytes) { continue }
                $ext = [IO.Path]::GetExtension($entryName); if (-not $ext) { $ext = '.bin' }
                $file = Join-Path $ImageDir ('image{0:D2}{1}' -f $k, $ext)
                try { [IO.File]::WriteAllBytes($file, $bytes) } catch { continue }
                # caption: text in the same block without the placeholder; for a picture on its own line, BOTH neighbours
                # (the AO forms put the instruction BEFORE the picture, vendor docs often after) - the model can tell.
                $cap = ''
                $bi = $null; foreach ($key in ($blockByIdx.Keys | Sort-Object)) { if ($key -ge $im.ParagraphIndex) { $bi = $blockByIdx[$key]; break } }
                if ($null -ne $bi) {
                    $clean = { param($t) (("$t" -replace '\[IMAGE \d+\]', '') -replace '\s+', ' ').Trim() }
                    $own = & $clean $blocks[$bi].Text
                    if ($own) { $cap = $own }
                    else {
                        $prev = if ($bi -gt 0 -and $blocks[$bi-1].Kind -eq 'p') { & $clean $blocks[$bi-1].Text } else { '' }
                        $next = if (($bi + 1) -lt $blocks.Count -and $blocks[$bi+1].Kind -eq 'p') { & $clean $blocks[$bi+1].Text } else { '' }
                        if ($prev.Length -gt 160) { $prev = $prev.Substring(0, 160) + '...' }; if ($next.Length -gt 160) { $next = $next.Substring(0, 160) + '...' }
                        $cap = (@($(if ($prev) { "before: $prev" }), $(if ($next) { "after: $next" })) | Where-Object { $_ }) -join ' | '
                    }
                }
                if ($cap.Length -gt 340) { $cap = $cap.Substring(0, 340) + '...' }
                $out.Images += @{ Index = $k; File = $file; Caption = $cap; MediaName = $entryName; Bytes = $bytes.Length }
            }
        }
        $out.Ok = $true
    } catch { $out.Notes += "read failed: $($_.Exception.Message)" }
    finally { if ($zip) { $zip.Dispose() } }
    return $out
}

# Excel column letters -> index (A=1, AA=27).
function ConvertFrom-AgentXlsxColumn { param([string]$Ref) $col = ($Ref -replace '\d', ''); $n = 0; foreach ($ch in $col.ToCharArray()) { $n = $n * 26 + ([int][char]$ch - 64) }; return $n }

# Read every sheet of an .xlsx/.xlsm as rows of cell text. Returns @{ Ok; Sheets = @(@{ Name; Rows = @(@(cells)) }); Text; Notes }.
function Read-AgentXlsx {
    param([Parameter(Mandatory)][string]$Path, [int]$MaxRows = 400)
    $out = @{ Ok = $false; Path = $Path; Sheets = @(); Text = ''; Notes = @() }
    if (-not (Test-Path -LiteralPath $Path)) { $out.Notes += 'file not found'; return $out }
    if ([IO.Path]::GetExtension($Path) -notmatch '(?i)^\.xls[xm]$') { $out.Notes += 'not an .xlsx/.xlsm'; return $out }
    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        $ss = @()
        $ssXml = Get-AgentZipEntryText -Zip $zip -Name 'xl/sharedStrings.xml'
        if ($ssXml) {
            $sd = New-Object Xml.XmlDocument; $sd.LoadXml($ssXml)
            $nsS = New-Object Xml.XmlNamespaceManager($sd.NameTable); $nsS.AddNamespace('m', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
            $ss = @(foreach ($si in $sd.SelectNodes('/m:sst/m:si', $nsS)) { (@($si.SelectNodes('.//m:t', $nsS) | ForEach-Object { $_.InnerText }) -join '') })
        }
        $wbXml = Get-AgentZipEntryText -Zip $zip -Name 'xl/workbook.xml'
        $names = @(); $sheetFiles = @()
        if ($wbXml) {
            $wd = New-Object Xml.XmlDocument; $wd.LoadXml($wbXml)
            $nsW = New-Object Xml.XmlNamespaceManager($wd.NameTable); $nsW.AddNamespace('m', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'); $nsW.AddNamespace('r', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
            $relXml = Get-AgentZipEntryText -Zip $zip -Name 'xl/_rels/workbook.xml.rels'
            $rels = @{}
            if ($relXml) { $rd = New-Object Xml.XmlDocument; $rd.LoadXml($relXml); foreach ($r in $rd.DocumentElement.ChildNodes) { if ($r.LocalName -eq 'Relationship') { $rels["$($r.GetAttribute('Id'))"] = "$($r.GetAttribute('Target'))" } } }
            foreach ($sh in $wd.SelectNodes('/m:workbook/m:sheets/m:sheet', $nsW)) {
                $rid = $sh.GetAttribute('id', $nsW.LookupNamespace('r')); $t = $rels["$rid"]
                if ($t) { $names += "$($sh.GetAttribute('name'))"; $sheetFiles += $(if ($t -match '^/') { $t.TrimStart('/') } else { "xl/$t" }) }
            }
        }
        if (-not $sheetFiles.Count) { $sheetFiles = @('xl/worksheets/sheet1.xml'); $names = @('Sheet1') }
        $allText = New-Object Text.StringBuilder
        for ($s = 0; $s -lt $sheetFiles.Count; $s++) {
            $x = Get-AgentZipEntryText -Zip $zip -Name $sheetFiles[$s]; if (-not $x) { continue }
            $d = New-Object Xml.XmlDocument; $d.LoadXml($x)
            $nsX = New-Object Xml.XmlNamespaceManager($d.NameTable); $nsX.AddNamespace('m', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
            $rows = New-Object System.Collections.Generic.List[object]
            foreach ($row in $d.SelectNodes('/m:worksheet/m:sheetData/m:row', $nsX)) {
                if ($rows.Count -ge $MaxRows) { $out.Notes += "$($names[$s]): truncated at $MaxRows rows"; break }
                $cells = @{}; $maxc = 0
                foreach ($c in $row.SelectNodes('m:c', $nsX)) {
                    $ref = $c.GetAttribute('r'); $ci = ConvertFrom-AgentXlsxColumn $ref; if ($ci -gt $maxc) { $maxc = $ci }
                    $type = $c.GetAttribute('t'); $val = ''
                    $v = $c.SelectSingleNode('m:v', $nsX)
                    if ($type -eq 's' -and $v) { $i = [int]$v.InnerText; if ($i -lt $ss.Count) { $val = $ss[$i] } }
                    elseif ($type -eq 'inlineStr') { $val = (@($c.SelectNodes('.//m:t', $nsX) | ForEach-Object { $_.InnerText }) -join '') }
                    elseif ($v) { $val = $v.InnerText; if ($type -eq 'b') { $val = if ($val -eq '1') { 'TRUE' } else { 'FALSE' } } }
                    $cells[$ci] = "$val".Trim()
                }
                if ($maxc -eq 0) { continue }
                $arr = @(for ($i = 1; $i -le $maxc; $i++) { if ($cells.ContainsKey($i)) { $cells[$i] } else { '' } })
                if (($arr -join '').Trim()) { $rows.Add($arr) }
            }
            $out.Sheets += @{ Name = $names[$s]; Rows = $rows.ToArray() }
            [void]$allText.AppendLine("== Sheet: $($names[$s]) ==")
            foreach ($r in $rows) { [void]$allText.AppendLine((($r | Where-Object { $_ -ne '' }) -join ' | ')) }
        }
        $out.Text = $allText.ToString(); $out.Ok = $true
    } catch { $out.Notes += "read failed: $($_.Exception.Message)" }
    finally { if ($zip) { $zip.Dispose() } }
    return $out
}

# Classify the documents in an ORDER folder (Incoming\<pkg> or a SharePoint staging copy): the AO's Software Package
# Request form, the complexity matrix, the RITM marker, vendor PDFs/readmes, mails. Looks at the whole tree (the
# layouts differ per order: doc\ + source\, flat, nested version folders). Temp/lock files (~$) are ignored.
function Find-AgentOrderDocs {
    param([Parameter(Mandatory)][string]$Folder)
    $r = @{ Form = $null; FormCandidates = @(); Complexity = $null; Ritm = ''; RitmFile = $null; Pdfs = @(); Readmes = @(); Mails = @(); Other = @(); AllDocs = @() }
    if (-not (Test-Path -LiteralPath $Folder)) { return $r }
    $files = @(Get-ChildItem -LiteralPath $Folder -File -Recurse -Depth 8 -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^~\$' })
    foreach ($f in $files) {
        $n = $f.Name; $e = $f.Extension.ToLower()
        if ($n -match '^(RITM\d+)\.txt$') { $r.Ritm = $Matches[1]; $r.RitmFile = $f.FullName; continue }
        if ($e -in '.docx', '.doc') {
            $r.AllDocs += $f.FullName
            if ($n -match '(?i)install(ation)?[ _-]*instruction|software[ _-]*package[ _-]*request|anleitung') { $r.FormCandidates += $f } else { $r.Other += $f.FullName }
            continue
        }
        if ($e -in '.xlsx', '.xlsm') { $r.AllDocs += $f.FullName; if ($n -match '(?i)complexity') { if (-not $r.Complexity) { $r.Complexity = $f.FullName } } else { $r.Other += $f.FullName }; continue }
        if ($e -eq '.pdf') { $r.Pdfs += $f.FullName; $r.AllDocs += $f.FullName; continue }
        if ($e -in '.txt', '.md', '.rtf' -and $n -match '(?i)readme|install|silent|deploy|setup|notes') { $r.Readmes += $f.FullName; $r.AllDocs += $f.FullName; continue }
        if ($e -in '.msg', '.eml') { $r.Mails += $f.FullName; $r.AllDocs += $f.FullName; continue }
    }
    # The form: prefer the .docx candidate with the most content (the real form is 200 KB+ with screenshots; a 0 KB
    # "~$" lock or an empty template loses). A lone .docx anywhere is taken when nothing is named like a form.
    $cand = @($r.FormCandidates | Where-Object { $_.Extension -ieq '.docx' } | Sort-Object Length -Descending)
    if (-not $cand.Count) { $cand = @($files | Where-Object { $_.Extension -ieq '.docx' } | Sort-Object Length -Descending) }
    if ($cand.Count) { $r.Form = $cand[0].FullName }
    $r.FormCandidates = @($r.FormCandidates | ForEach-Object { $_.FullName })
    return $r
}
