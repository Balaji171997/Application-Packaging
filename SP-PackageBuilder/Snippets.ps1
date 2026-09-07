##############################################################
# Snippets.ps1
# Load categorised code snippets from snippets.json (categories -> subcategories ->
# snippets) and expose them for the Step-3 editor panel. The file is the single source
# of truth - no inline snippets. Ported from the reference SnippetManager.
##############################################################

$script:Snippets = $null
$script:SnippetsPath = $null   # remembered so Save-Snippet / Remove-Snippet write back to the same file

function Initialize-Snippets {
    param([string]$JsonPath)
    $script:SnippetsPath = $JsonPath
    if (-not $JsonPath -or -not (Test-Path $JsonPath)) { Write-Log "snippets.json not found ($JsonPath)" Warning; $script:Snippets = $null; return }
    try {
        $raw = if (Get-Command Read-FileSmart -ErrorAction SilentlyContinue) { Read-FileSmart -Path $JsonPath } else { Get-Content $JsonPath -Raw }
        $script:Snippets = $raw | ConvertFrom-Json -ErrorAction Stop
        Write-Log "Snippets loaded from $JsonPath" Success
    } catch {
        Write-Log "Could not load snippets.json: $($_.Exception.Message)" Warning
        $script:Snippets = $null
    }
}

# Category names for the filter dropdown ('All' first).
function Get-SnippetCategoryNames {
    if (-not $script:Snippets -or -not $script:Snippets.categories) { return @('All') }
    return @('All') + @($script:Snippets.categories | ForEach-Object { $_.name })
}

# Flat list of snippets (optionally filtered by category + search text).
function Get-FilteredSnippets {
    param([string]$CategoryName = 'All', [string]$SearchText = '')
    if (-not $script:Snippets -or -not $script:Snippets.categories) { return @() }
    $cats = if ($CategoryName -and $CategoryName -ne 'All') {
        @($script:Snippets.categories | Where-Object { $_.name -eq $CategoryName })
    } else { @($script:Snippets.categories) }
    $flat = @()
    foreach ($cat in $cats) {
        foreach ($sub in @($cat.subcategories)) {
            foreach ($snip in @($sub.snippets)) {
                if (-not $snip -or -not $snip.name) { continue }
                $flat += [PSCustomObject]@{
                    Name        = [string]$snip.name
                    Code        = [string]$snip.code
                    Category    = [string]$cat.name
                    Subcategory = [string]$sub.name
                    Label       = "$($cat.name) / $($sub.name) / $($snip.name)"
                }
            }
        }
    }
    if ($SearchText) {
        $n = $SearchText.ToLower()
        $flat = @($flat | Where-Object { $_.Name.ToLower().Contains($n) -or ($_.Code -and $_.Code.ToLower().Contains($n)) })
    }
    return $flat
}

function Get-SnippetCode {
    param([string]$SnippetName)
    if (-not $script:Snippets -or -not $script:Snippets.categories) { return '' }
    foreach ($cat in $script:Snippets.categories) {
        foreach ($sub in @($cat.subcategories)) {
            foreach ($snip in @($sub.snippets)) {
                if ($snip.name -eq $SnippetName) { return [string]$snip.code }
            }
        }
    }
    return ''
}

# Serialize the model back to snippets.json. PS 5.1 escapes < > & ' as \uXXXX; we restore them so the file stays
# readable (ConvertFrom-Json reads either form). Writes UTF-8 no-BOM and reloads $script:Snippets.
function Save-SnippetsModel {
    param([Parameter(Mandatory)]$Root, [string]$JsonPath)
    if (-not $JsonPath) { $JsonPath = $script:SnippetsPath }
    if (-not $JsonPath) { return $false }
    try {
        $json = $Root | ConvertTo-Json -Depth 12
        $json = $json -replace '\\u003c','<' -replace '\\u003e','>' -replace '\\u0026','&' -replace '\\u0027',"'"
        $enc = New-Object System.Text.UTF8Encoding($false)
        # Write a temp file in the same folder, then atomically swap it in - with retries, so a SHARED file briefly
        # locked by another user (two people saving at once) doesn't corrupt the JSON or lose the write.
        $dir = Split-Path $JsonPath -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
        $tmp = Join-Path $dir ('.snip_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.tmp')
        [IO.File]::WriteAllText($tmp, $json, $enc)
        $ok = $false
        for ($i = 0; $i -lt 5 -and -not $ok; $i++) {
            try {
                if (Test-Path $JsonPath) { [IO.File]::Replace($tmp, $JsonPath, $null) } else { [IO.File]::Move($tmp, $JsonPath) }
                $ok = $true
            } catch { Start-Sleep -Milliseconds 200 }
        }
        if (-not $ok) { try { [IO.File]::Copy($tmp, $JsonPath, $true); $ok = $true } catch {} ; try { Remove-Item $tmp -Force -EA SilentlyContinue } catch {} }
        if (-not $ok) { Write-Log "Could not write snippets to $JsonPath (locked by another user? try again)" Warning; return $false }
        Initialize-Snippets $JsonPath
        return $true
    } catch { Write-Log "Could not save snippets.json: $($_.Exception.Message)" Warning; return $false }
}

# Add (or replace by name within its subcategory) a snippet, creating the category/subcategory as needed, then
# persist. This is the "easy way" to store a snippet - no hand-editing JSON, all escaping handled here.
function Save-Snippet {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Category,
          [string]$Subcategory = 'General', [Parameter(Mandatory)][string]$Code, [string]$JsonPath)
    if (-not $JsonPath) { $JsonPath = $script:SnippetsPath }
    $root = $null
    if ($JsonPath -and (Test-Path $JsonPath)) {
        try { $raw = if (Get-Command Read-FileSmart -EA SilentlyContinue) { Read-FileSmart -Path $JsonPath } else { Get-Content $JsonPath -Raw }
              $root = $raw | ConvertFrom-Json -ErrorAction Stop } catch {}
    }
    if (-not $root) { $root = [pscustomobject]@{ version='1.0'; categories=@() } }
    if (-not ($root.PSObject.Properties.Name -contains 'categories') -or -not $root.categories) {
        $root | Add-Member -NotePropertyName categories -NotePropertyValue @() -Force }
    $cat = @($root.categories | Where-Object { $_.name -eq $Category })[0]
    if (-not $cat) { $cat = [pscustomobject]@{ name=$Category; subcategories=@() }; $root.categories = @($root.categories) + $cat }
    if (-not ($cat.PSObject.Properties.Name -contains 'subcategories') -or -not $cat.subcategories) {
        $cat | Add-Member -NotePropertyName subcategories -NotePropertyValue @() -Force }
    $sub = @($cat.subcategories | Where-Object { $_.name -eq $Subcategory })[0]
    if (-not $sub) { $sub = [pscustomobject]@{ name=$Subcategory; snippets=@() }; $cat.subcategories = @($cat.subcategories) + $sub }
    if (-not ($sub.PSObject.Properties.Name -contains 'snippets') -or -not $sub.snippets) {
        $sub | Add-Member -NotePropertyName snippets -NotePropertyValue @() -Force }
    $existing = @($sub.snippets | Where-Object { $_.name -eq $Name })
    if ($existing.Count) { foreach ($e in $existing) { $e.code = $Code } }
    else { $sub.snippets = @($sub.snippets) + ([pscustomobject]@{ name=$Name; code=$Code }) }
    return (Save-SnippetsModel -Root $root -JsonPath $JsonPath)
}

# Remove a snippet by name (optionally scoped to a category + subcategory), pruning now-empty subs/cats, then save.
function Remove-Snippet {
    param([Parameter(Mandatory)][string]$Name, [string]$Category, [string]$Subcategory, [string]$JsonPath)
    if (-not $JsonPath) { $JsonPath = $script:SnippetsPath }
    if (-not ($JsonPath -and (Test-Path $JsonPath))) { return $false }
    $root = $null
    try { $raw = if (Get-Command Read-FileSmart -EA SilentlyContinue) { Read-FileSmart -Path $JsonPath } else { Get-Content $JsonPath -Raw }
          $root = $raw | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    foreach ($cat in @($root.categories)) {
        if ($Category -and $cat.name -ne $Category) { continue }
        foreach ($sub in @($cat.subcategories)) {
            if ($Subcategory -and $sub.name -ne $Subcategory) { continue }
            $sub.snippets = @($sub.snippets | Where-Object { $_.name -ne $Name })
        }
        $cat.subcategories = @($cat.subcategories | Where-Object { @($_.snippets).Count -gt 0 })
    }
    $root.categories = @($root.categories | Where-Object { @($_.subcategories).Count -gt 0 })
    return (Save-SnippetsModel -Root $root -JsonPath $JsonPath)
}

# Best-effort PSADT v3 -> v4 conversion for a pasted snippet (the dialog shows the result for review before saving).
# High-confidence transforms only: cmdlet renames, -Parameters->-ArgumentList, same-line -Path->-FilePath for the
# process cmdlets, $dirFiles/$dirSupportFiles -> $adtSession.*, and dropping the v3 -Source $deployAppScriptFriendlyName.
function Convert-V3ToV4Snippet {
    param([string]$Code)
    if (-not $Code) { return $Code }
    # Prefer the AUTHORITATIVE converter (PSADT_V3toV4_Mappings.ps1) so the Add dialog gets the SAME validated mapping
    # as predecessor reuse - incl. the branding -Name fix, -AdditionalRegPaths strip, VWG hardcode and shape rewrites,
    # and the Test-Build guard that keeps every target a real v4 function. The inline map below is only a FALLBACK.
    if (Get-Command Convert-V3ToV4Content -ErrorAction SilentlyContinue) {
        $pre = [regex]::Replace($Code, '\s*-Source\s+\$deployAppScriptFriendlyName\b', '')   # v4 auto-sources
        return (Convert-V3ToV4Content -Content $pre)
    }
    $c = $Code
    $map = [ordered]@{
        'Execute-ProcessAsUser'='Start-ADTProcessAsUser'; 'Execute-Process'='Start-ADTProcess'
        'Execute-MSP'='Start-ADTMspProcess'; 'Execute-MSI'='Start-ADTMsiProcess'
        'Write-Log'='Write-ADTLogEntry'; 'Remove-File'='Remove-ADTFile'; 'Remove-Folder'='Remove-ADTFolder'
        'Copy-File'='Copy-ADTFile'; 'New-Folder'='New-ADTFolder'
        'Remove-RegistryKey'='Remove-ADTRegistryKey'; 'Set-RegistryKey'='Set-ADTRegistryKey'
        'Get-RegistryKey'='Get-ADTRegistryKey'; 'Test-RegistryValue'='Test-ADTRegistryValue'
        'Get-InstalledApplication'='Get-ADTApplication'; 'Remove-MSIApplications'='Uninstall-ADTApplication'
        'New-Shortcut'='New-ADTShortcut'; 'Set-Shortcut'='Set-ADTShortcut'; 'Get-Shortcut'='Get-ADTShortcut'
        'Get-UserProfiles'='Get-ADTUserProfiles'; 'Get-FreeDiskSpace'='Get-ADTFreeDiskSpace'
        'Get-FileVersion'='Get-ADTFileVersion'; 'Get-PendingReboot'='Get-ADTPendingReboot'
        'Show-InstallationWelcome'='Show-ADTInstallationWelcome'; 'Show-InstallationProgress'='Show-ADTInstallationProgress'
        'Close-InstallationProgress'='Close-ADTInstallationProgress'; 'Show-InstallationPrompt'='Show-ADTInstallationPrompt'
        'Show-InstallationRestartPrompt'='Show-ADTInstallationRestartPrompt'; 'Show-DialogBox'='Show-ADTDialogBox'
        'Show-BalloonTip'='Show-ADTBalloonTip'; 'Block-AppExecution'='Block-ADTAppExecution'
        'Unblock-AppExecution'='Unblock-ADTAppExecution'; 'Set-ActiveSetup'='Set-ADTActiveSetup'
        'Copy-FileToUserProfiles'='Copy-ADTFileToUserProfiles'; 'Remove-FileFromUserProfiles'='Remove-ADTFileFromUserProfiles'
        'Get-IniValue'='Get-ADTIniValue'; 'Set-IniValue'='Set-ADTIniValue'; 'Set-ItemPermission'='Set-ADTItemPermission'
        'Test-Battery'='Test-ADTBattery'; 'Test-NetworkConnection'='Test-ADTNetworkConnection'; 'Test-PowerPoint'='Test-ADTPowerPoint'
        'Test-ServiceExists'='Test-ADTServiceExists'; 'Get-LoggedOnUser'='Get-ADTLoggedOnUser'
        'Set-ServiceStartMode'='Set-ADTServiceStartMode'; 'Get-ServiceStartMode'='Get-ADTServiceStartMode'
        'Start-ServiceAndDependencies'='Start-ADTServiceAndDependencies'; 'Remove-Branding'='Remove-MTBDetectionKey'
        'Exit-Script'='Close-ADTSession'; 'Import-Certificates'='Import-Certificate'
    }
    foreach ($k in $map.Keys) { $c = [regex]::Replace($c, "(?<![\w-])$([regex]::Escape($k))(?![\w-])", $map[$k]) }
    $c = [regex]::Replace($c, '(?<![\w-])-Parameters(?=[\s:])', '-ArgumentList')
    # same-line -Path -> -FilePath for the process cmdlets (Start-ADTProcess / Start-ADTMsiProcess / Start-ADTMspProcess)
    $c = [regex]::Replace($c, '(?im)(Start-ADT(?:Msi|Msp)?Process(?:AsUser)?\b[^\r\n]*?)\s-Path(?=[\s:])', '$1 -FilePath')
    $c = [regex]::Replace($c, '(?<![\w$])\$dirSupportFiles\b', '$($adtSession.DirSupportFiles)')
    $c = [regex]::Replace($c, '(?<![\w$])\$dirFiles\b', '$($adtSession.DirFiles)')
    $c = [regex]::Replace($c, '\s*-Source\s+\$deployAppScriptFriendlyName', '')
    # Team-custom v3 vars that DO NOT exist in v4 -> hardcode the WOW (32-bit) path directly.
    # $VWG_CurrentRegWOW carried the trailing '\' (e.g. "Wow6432Node\"); $VWG_CurrentSysWOW was "SysWOW64".
    $c = [regex]::Replace($c, '\$\(\s*\$VWG_CurrentRegWOW\s*\)', 'Wow6432Node\')
    $c = [regex]::Replace($c, '(?<![\w$])\$VWG_CurrentRegWOW\b', 'Wow6432Node\')
    $c = [regex]::Replace($c, '\$\(\s*\$VWG_CurrentSysWOW\s*\)', 'SysWOW64')
    $c = [regex]::Replace($c, '(?<![\w$])\$VWG_CurrentSysWOW\b', 'SysWOW64')
    return $c
}
