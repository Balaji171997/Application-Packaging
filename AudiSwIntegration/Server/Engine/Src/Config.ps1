# ==============================================================================
#  Audi SCCM Integration Tool - configuration and package-reading engine
# ==============================================================================
#  Increment 1 of the blueprint: everything that can be built and proven without
#  touching SCCM. No site connection and no SCCM commands live here yet.
#
#  Design rules this file follows:
#    * Nothing environment-specific is written in code. It all comes from
#      Environments\<CODE>.xml and Environments\Defaults.xml.
#    * No parsing rule is written in code either. How a package name is split,
#      how the branding key is built, and which patterns pull values out of a
#      PSADT script or an instruction document all come from Defaults.xml.
#    * Every config file is validated against Environment.xsd before use, so a
#      typo is caught up front instead of halfway through an integration.
#    * ASCII only, so the file has no encoding dependency.
# ==============================================================================

Set-StrictMode -Version 2.0

# this file lives in <tool>\Src, so the tool root is one level up
$script:AudiRoot          = Split-Path -Parent $PSScriptRoot
$script:AudiConfigErrors  = New-Object System.Collections.Generic.List[string]
$script:AudiDefaultsCache = $null

function Get-AudiConfigRoot {
    <#  <tool>\Config - the schema and Defaults.xml.  #>
    [CmdletBinding()]
    param([string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { $Root = $script:AudiRoot }
    return (Join-Path $Root 'Config')
}

function Get-AudiEnvironmentRoot {
    <#  <tool>\Config\Environments - one file per environment, nothing else in it. #>
    [CmdletBinding()]
    param([string]$Root)
    return (Join-Path (Get-AudiConfigRoot -Root $Root) 'Environments')
}

function Test-AudiConfigFile {
    <#  Validates one XML file against Environment.xsd.
        Returns @{ Ok = bool; Errors = string[]; Document = XmlDocument }.
        Never throws on a bad file - the caller decides what to do.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Ok = $false; Errors = @("File not found: $Path"); Document = $null }
    }
    if ([string]::IsNullOrWhiteSpace($SchemaPath)) {
        $SchemaPath = Join-Path (Get-AudiConfigRoot) 'Environment.xsd'
    }
    if (-not (Test-Path -LiteralPath $SchemaPath)) {
        return @{ Ok = $false; Errors = @("Schema not found: $SchemaPath"); Document = $null }
    }

    $script:AudiConfigErrors = New-Object System.Collections.Generic.List[string]
    $doc = New-Object System.Xml.XmlDocument

    try { $doc.Load($Path) }
    catch { return @{ Ok = $false; Errors = @("Not valid XML: $($_.Exception.Message)"); Document = $null } }

    try { $null = $doc.Schemas.Add($null, $SchemaPath) }
    catch { return @{ Ok = $false; Errors = @("Schema could not be loaded: $($_.Exception.Message)"); Document = $null } }

    $handler = [System.Xml.Schema.ValidationEventHandler] {
        param($sender, $e)
        $script:AudiConfigErrors.Add("$($e.Severity): $($e.Message)")
    }
    try { $doc.Validate($handler) }
    catch { $script:AudiConfigErrors.Add($_.Exception.Message) }

    $errors = @($script:AudiConfigErrors)
    return @{ Ok = ($errors.Count -eq 0); Errors = $errors; Document = $doc }
}

function Get-AudiDefaults {
    <#  Loads Defaults.xml. Cached, because the packager window reads it often.  #>
    [CmdletBinding()]
    param([string]$Root, [switch]$Force)

    if ($script:AudiDefaultsCache -and -not $Force) { return $script:AudiDefaultsCache }

    $path   = Join-Path (Get-AudiConfigRoot -Root $Root) 'Defaults.xml'
    $result = Test-AudiConfigFile -Path $path
    if (-not $result.Ok) {
        throw "Defaults.xml is not valid:`r`n  " + ($result.Errors -join "`r`n  ")
    }

    $d = $result.Document.Defaults
    $osList = @($result.Document.SelectNodes('/Defaults/OperatingSystems/OperatingSystem')) |
        ForEach-Object {
            [pscustomobject]@{
                Key               = $_.key
                Label             = $_.label
                Value             = $_.value
                SelectedByDefault = [bool]::Parse($_.selectedByDefault)
            }
        }

    $namePatterns = @($result.Document.SelectNodes('/Defaults/PackageName/Pattern') | ForEach-Object { $_.InnerText.Trim() })

    # The editable-settings catalogue. Options are read as a list of
    # value/label pairs so the window can show a sentence and send back the
    # value SCCM wants.
    $settings = @($result.Document.SelectNodes('/Defaults/Settings/Setting')) |
        ForEach-Object {
            $node = $_
            [pscustomobject]@{
                Key      = $node.key
                Scope    = $node.scope
                Property = $node.property
                Label    = $node.label
                Editor   = $node.editor
                Unit     = $(if ($node.HasAttribute('unit')) { $node.unit } else { '' })
                Hint     = $(if ($node.HasAttribute('hint')) { $node.hint } else { '' })
                # Editable unless the file says otherwise, so a new setting is
                # editable by default and locking one is a deliberate act.
                Editable = $(if ($node.HasAttribute('editable')) { [bool]::Parse($node.editable) } else { $true })
                LockedReason = $(if ($node.HasAttribute('lockedReason')) { $node.lockedReason } else { '' })
                WriteParameter = $(if ($node.HasAttribute('writeParameter')) { $node.writeParameter } else { '' })
                Options  = @($node.SelectNodes('Option') | ForEach-Object {
                                [pscustomobject]@{
                                    Value = $_.value
                                    Label = $_.InnerText.Trim()
                                    # What the SET cmdlet wants. Same as Value
                                    # unless the file says otherwise.
                                    WriteValue = $(if ($_.HasAttribute('writeValue')) { $_.writeValue } else { $_.value })
                                }
                            })
            }
        }

    $scripts = @($result.Document.SelectNodes('/Defaults/PackageSource/Script')) |
        ForEach-Object {
            $node = $_
            [pscustomobject]@{
                Generation = $node.generation
                FileName   = $node.fileName
                Fields     = @($node.SelectNodes('Field')) | ForEach-Object {
                    [pscustomobject]@{
                        Name          = $_.name
                        Pattern       = $_.pattern
                        LastMatchWins = $(if ($_.HasAttribute('lastMatchWins')) { [bool]::Parse($_.lastMatchWins) } else { $true })
                    }
                }
            }
        }

    $docNode  = $result.Document.SelectSingleNode('/Defaults/PackageSource/Document')
    $document = $null
    if ($docNode) {
        $document = [pscustomobject]@{
            Filter = $docNode.filter
            Fields = @($docNode.SelectNodes('Field')) | ForEach-Object {
                [pscustomobject]@{ Name = $_.name; Pattern = $_.pattern }
            }
        }
    }

    # No personal name may reach an SCCM object - checked here, at load, so a
    # later edit on the server cannot reintroduce one silently.
    # @() around the call: an empty array returned from a function is unrolled to
    # $null, and $null.Count throws under StrictMode
    $offending = @(Test-AudiSccmCommentTemplate -Template $d.Comments.collection)
    if ($offending.Count -gt 0) {
        throw ("Defaults.xml is not acceptable: the collection comment contains " +
               (($offending | ForEach-Object { "{$_}" }) -join ', ') +
               ". No personal name may be written to an SCCM object. Use {jobId} instead - " +
               "the tool's log on the server maps a job ID back to the person who asked.")
    }

    $script:AudiDefaultsCache = [pscustomobject]@{
        SchemaVersion    = $d.schemaVersion
        Commands         = $d.Commands
        # Steps that can be switched off for every environment at once.
        Steps            = [pscustomobject]@{ CreateArsGroup = [bool]::Parse($d.Steps.createArsGroup) }
        # The application's Distribution Settings tab in the console.
        Distribution     = $d.Distribution
        Naming           = $d.Naming
        Application      = $d.Application
        Detection        = $d.Detection
        SoftIdentDetection = $d.SoftIdentDetection
        DeploymentType   = $d.DeploymentType
        Comments         = $d.Comments
        Audit            = [pscustomobject]@{ RequireRfc = [bool]::Parse($d.Audit.requireRfc) }
        OperatingSystems = $osList
        PackageName      = [pscustomobject]@{
            Separator         = $d.PackageName.separator
            BrandingKeyFormat = $d.PackageName.brandingKeyFormat
            Patterns          = $namePatterns
        }
        PackageSource    = [pscustomobject]@{
            SearchDepth = [int]$d.PackageSource.searchDepth
            Scripts     = $scripts
            Document    = $document
        }
        Runtime          = [pscustomobject]@{
            RetryCount                 = [int]$d.Runtime.retryCount
            RetryDelaySeconds          = [int]$d.Runtime.retryDelaySeconds
            DistributionTimeoutMinutes = [int]$d.Runtime.distributionTimeoutMinutes
            DistributionPollSeconds    = [int]$d.Runtime.distributionPollSeconds
            LogRoot                    = [Environment]::ExpandEnvironmentVariables($d.Runtime.logRoot)
            LogRetentionDays           = [int]$d.Runtime.logRetentionDays
            LockTimeoutMinutes         = [int]$d.Runtime.lockTimeoutMinutes
            TransientErrors            = @($result.Document.SelectNodes('/Defaults/Runtime/TransientErrors/Pattern') | ForEach-Object { $_.InnerText })
        }
        Settings         = $settings
        Path             = $path
    }
    return $script:AudiDefaultsCache
}

function Get-AudiSettingCatalogue {
    <#  The settings the Modify tab is allowed to edit, and the values SCCM
        accepts for each. Straight out of Defaults.xml - the window never
        carries its own list, so adding an option is a config edit.

        A Choice setting's Options are what the operator picks from. A Text or
        Number setting has none, and is typed.  #>
    [CmdletBinding()]
    param([string]$Root, [string]$Scope)

    $all = @((Get-AudiDefaults -Root $Root).Settings)
    if ($Scope) { return @($all | Where-Object { $_.Scope -eq $Scope }) }
    return $all
}

function Get-AudiEnvironmentCode {
    <#  Every environment code that has a file, e.g. ICZ, INA, PCZ.  #>
    [CmdletBinding()]
    param([string]$Root)
    $dir = Get-AudiEnvironmentRoot -Root $Root
    return @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File |
        ForEach-Object { $_.BaseName } | Sort-Object)
}

function Get-AudiEnvironment {
    <#  Loads and validates one environment file.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [string]$Root
    )

    $path   = Join-Path (Get-AudiEnvironmentRoot -Root $Root) ("$Code.xml")
    $result = Test-AudiConfigFile -Path $path
    if (-not $result.Ok) {
        throw "Environment '$Code' is not valid:`r`n  " + ($result.Errors -join "`r`n  ")
    }

    $e = $result.Document.Environment
    if ($e.code -ne $Code) {
        throw "Environment file '$path' declares code '$($e.code)' but is named '$Code'."
    }

    $collections = @($result.Document.SelectNodes('/Environment/Collections/Collection')) |
        ForEach-Object {
            [pscustomobject]@{
                Prefix               = $_.prefix
                Suffix               = $(if ($_.HasAttribute('suffix')) { $_.suffix } else { '' })
                LimitingCollectionId = $_.limitingCollectionId
                Folder               = $_.folder
                DeploymentAction     = $_.deploymentAction
            }
        }

    return [pscustomobject]@{
        Code              = $e.code
        Description       = $e.description
        SchemaVersion     = $e.schemaVersion
        Verified          = [bool]::Parse($e.verified)

        DomainNames       = @($result.Document.SelectNodes('/Environment/Domain/Name') | ForEach-Object { $_.InnerText })
        LogonPrefix       = $e.Domain.logonPrefix
        SiteCode          = $e.Site.code
        SiteServer        = $e.Site.server
        # The machine that runs the collector. Not the SCCM server: it connects
        # to the SMS Provider above, from Zone Global.
        RunnerHost        = $e.Runner.host
        Service           = $e.Service
        # How the window reaches this environment. Flow 2 = DropFolder: the
        # window never connects to the server, it leaves a file in a share.
        Transport         = [pscustomobject]@{
            Mode                 = $e.Transport.mode
            DropFolder           = $(if ($e.Transport.HasAttribute('dropFolder'))           { $e.Transport.dropFolder }                 else { '' })
            ResultTimeoutMinutes = $(if ($e.Transport.HasAttribute('resultTimeoutMinutes')) { [int]$e.Transport.resultTimeoutMinutes } else { 30 })
        }
        ContentShare      = $e.Content.share
        DistributionPointGroup = $e.Content.distributionPointGroup
        ApplicationFolder = $e.ApplicationFolder
        Collections       = $collections
        SecurityScopes    = @($result.Document.SelectNodes('/Environment/SecurityScopes/Scope') | ForEach-Object { $_.InnerText })
        ArsProviderUrl    = $e.ActiveDirectory.arsProviderUrl
        ArsGroupOu        = $e.ActiveDirectory.groupOu
        Path              = $path
    }
}

function Resolve-AudiEnvironmentCode {
    <#  Which environment this machine belongs to, decided by its AD domain.
        -Code overrides the lookup; the old tool offered no override at all.  #>
    [CmdletBinding()]
    param([string]$Code, [string]$Domain, [string]$Root)

    if (-not [string]::IsNullOrWhiteSpace($Code)) { return $Code.ToUpperInvariant() }

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        try { $Domain = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Domain }
        catch { $Domain = $env:USERDNSDOMAIN }
    }
    if ([string]::IsNullOrWhiteSpace($Domain)) { return $null }

    foreach ($code in (Get-AudiEnvironmentCode -Root $Root)) {
        $env = Get-AudiEnvironment -Code $code -Root $Root
        foreach ($name in $env.DomainNames) {
            if ($name -eq $Domain) { return $env.Code }
        }
    }
    return $null
}

function Split-AudiPackageName {
    <#  Splits a package name into its parts using the patterns in Defaults.xml.

        The tool being replaced did this with a text replacement, which corrupted
        any name whose site code appeared again later - ADO_ADOBE_Reader became
        INA_INABE_Reader. Here each naming convention is one regex with named
        groups, tried in order, so a product name containing the separator still
        parses and a second convention is a config line rather than a code
        change.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [string]$Root
    )

    $defaults = Get-AudiDefaults -Root $Root
    $spec     = $defaults.PackageName

    $match   = $null
    $matched = $null
    foreach ($pattern in $spec.Patterns) {
        $regex = [regex]$pattern
        $m = $regex.Match($PackageName)
        if ($m.Success) { $match = $m; $matched = $regex; break }
    }
    if (-not $match) {
        throw ("Package name '{0}' does not match any known naming convention. Expected something like " +
               "INA_ETAS_INCA_x64_7.5.7-0001_MUL - site, publisher, product, architecture, version-revision, language. " +
               "The conventions the tool accepts are the <Pattern> entries in Defaults.xml.") -f $PackageName
    }

    # every named group in the pattern becomes a field, so adding one to the
    # regex is all it takes to surface a new part
    $result = [ordered]@{}
    foreach ($name in $matched.GetGroupNames()) {
        if ($name -match '^\d+$') { continue }          # skip the numbered groups
        $result[$name] = $match.Groups[$name].Value
    }

    $result['PackageName'] = $PackageName
    return [pscustomobject]$result
}

function Test-AudiSccmCommentTemplate {
    <#  Enforces Audi's privacy requirement: no personal name may be written to
        an SCCM object.

        The comment templates live in Defaults.xml, which is the right place for
        them - but that also means someone could edit {requester} back in on the
        server, long after we have gone. This is checked every time the config
        loads, so that edit fails loudly instead of quietly stamping names onto
        collections. Returns the offending placeholders, empty if clean.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Template)

    $banned = @('requester', 'user', 'userName', 'operator')
    return @($banned | Where-Object { $Template -match ('\{' + [regex]::Escape($_) + '\}') })
}

function Expand-AudiTemplate {
    <#  Replaces {Name} placeholders from a hashtable or object.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Template, [Parameter(Mandatory = $true)]$Values)

    $out = $Template
    $names = if ($Values -is [System.Collections.IDictionary]) { @($Values.Keys) }
             else { @($Values.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($name in $names) {
        $value = if ($Values -is [System.Collections.IDictionary]) { $Values[$name] } else { $Values.$name }
        $out = $out.Replace('{' + $name + '}', [string]$value)
    }
    return $out
}

function Get-AudiBrandingKey {
    <#  Branding key built from the template in Defaults.xml, not by string surgery.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackageName, [string]$Root)
    $defaults = Get-AudiDefaults -Root $Root
    $parts    = Split-AudiPackageName -PackageName $PackageName -Root $Root
    return (Expand-AudiTemplate -Template $defaults.PackageName.BrandingKeyFormat -Values $parts)
}

function Resolve-AudiSoftIdent {
    <#  Turns the SoftIdent as written in the script into the path it actually
        means on a client.

        The deployment script writes it with a placeholder:

            HKLM:\SOFTWARE\$($VWG_CurrentRegWOW)Microsoft\Windows\...

        VWG_CurrentRegWOW is filled in by the PSADT extensions at run time. It
        is 'Wow6432Node\' for a 32-bit application on 64-bit Windows and empty
        otherwise, so the architecture decides it. Resolving it here means the
        window shows the key that will really be looked at, rather than a
        placeholder nobody can check.

        Returns the resolved path; the raw form stays available to the caller. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SoftIdent,
        [string]$Architecture
    )

    if ([string]::IsNullOrWhiteSpace($SoftIdent)) { return '' }

    $wow = if ($Architecture -match '^(x86|32|Win32)$') { 'Wow6432Node\' } else { '' }

    # both the $(...) and the bare $Var forms, whichever the script used
    $out = $SoftIdent -replace '\$\(\s*\$?VWG_CurrentRegWOW\s*\)', $wow
    $out = $out -replace '\$VWG_CurrentRegWOW', $wow
    return $out
}

function Split-AudiSoftIdent {
    <#  Turns a resolved SoftIdent into the parts of a registry detection rule.

        The deployment script writes it as a path plus an optional value test:

            HKLM:\SOFTWARE\...\Uninstall\INCA7.5.7 [DisplayVersion=7.5.7]

        which becomes hive HKLM, key SOFTWARE\...\INCA7.5.7, value name
        DisplayVersion, value 7.5.7. Without the bracket it is a key-exists
        test and ValueName comes back empty.

        Returns $null when there is nothing to parse or the shape is not
        recognised - the caller then simply has one detection rule. Guessing at
        a half-understood SoftIdent would produce an application that installs
        and then immediately reports itself as not installed.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SoftIdent,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($SoftIdent)) { return $null }

    $spec = (Get-AudiDefaults -Root $Root).SoftIdentDetection
    if (-not $spec) { return $null }

    $match = [regex]::Match($SoftIdent, $spec.pattern)
    if (-not $match.Success) { return $null }

    $key = $match.Groups['Key'].Value.Trim().TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }

    # a placeholder that was never resolved would silently become a literal key
    if ($key -match '\$') { return $null }

    return [pscustomobject]@{
        Hive      = $match.Groups['Hive'].Value.ToUpperInvariant()
        Key       = $key
        ValueName = $match.Groups['ValueName'].Value.Trim()
        Value     = $match.Groups['Value'].Value.Trim()
    }
}

function Format-AudiDetectionRule {
    <#  The detection rules as one readable line, for the window, the log and the
        preview - so what SCCM will be asked for is visible before it is asked. #>
    [CmdletBinding()]
    param($Rules)

    $list = @($Rules)
    if ($list.Count -eq 0) { return 'no detection rule' }

    return (@($list | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_.ValueName)) { "{0}\{1} exists" -f $_.Hive, $_.Key }
        else { "{0}\{1}\{2}={3}" -f $_.Hive, $_.Key, $_.ValueName, $_.Value }
    }) -join '  AND  ')
}

function Get-AudiDocumentText {
    <#  Plain text out of a .docx, without needing Word installed.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        # Word writes 'word/document.xml', but some tools that produce .docx
        # files write the separator as a backslash. Match either, and ignore
        # case, so a document is never silently skipped over a slash.
        $entry = $zip.Entries |
                 Where-Object { $_.FullName.Replace('\', '/') -ieq 'word/document.xml' } |
                 Select-Object -First 1
        if (-not $entry) { return '' }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    catch { return '' }
    finally { if ($zip) { $zip.Dispose() } }

    # Paragraph and line breaks become newlines, then the rest of the markup goes.
    # Closing tags are used deliberately - they never carry attributes, whereas
    # Word writes opening tags as <w:p w14:paraId=".." ..>.
    #
    # Tables matter as much as paragraphs: an install instruction document
    # usually puts "label | value" in a two-column table, and without the tab
    # the label and value would run together into one unreadable word.
    $text = $xml -replace '</w:p>', "`r`n"                  # paragraphs
    $text = $text -replace '<w:br[^>]*/>', "`r`n"           # manual line breaks
    $text = $text -replace '<w:tab[^>]*/>', "`t"            # tabs
    $text = $text -replace '</w:tc>', "`t"                  # table cell -> tab
    $text = $text -replace '</w:tr>', "`r`n"                # table row  -> new line
    $text = $text -replace '<[^>]+>', ''
    $text = $text -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&apos;', "'"
    return $text
}

function Read-AudiPackageDetail {
    <#  Fills in what the packager would otherwise retype, by reading the
        package's own PSADT script and the install instruction document.

        Every field records where it came from, so the window can show the
        operator what was detected and what they still have to supply. Anything
        not found is simply left empty - never guessed.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [string]$Root
    )

    $defaults = Get-AudiDefaults -Root $Root
    $source   = $defaults.PackageSource
    $fields   = [ordered]@{}
    $origin   = [ordered]@{}
    $notes    = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        $notes.Add("Package path not found: $PackagePath")
        return [pscustomobject]@{ Fields = $fields; Origin = $origin; Generation = $null; ScriptPath = $null; DocumentPath = $null; Notes = @($notes) }
    }

    # ---- the deployment script -------------------------------------------------
    $generation = $null
    $scriptPath = $null
    foreach ($candidate in $source.Scripts) {
        $found = Get-ChildItem -LiteralPath $PackagePath -Filter $candidate.FileName -File -Recurse -Depth $source.SearchDepth -ErrorAction SilentlyContinue |
                 Sort-Object { $_.FullName.Length } | Select-Object -First 1
        if ($found) {
            $generation = $candidate.Generation
            $scriptPath = $found.FullName
            $content    = Get-Content -LiteralPath $found.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                foreach ($field in $candidate.Fields) {
                    $matches = [regex]::Matches($content, $field.Pattern)
                    if ($matches.Count -gt 0) {
                        $m = if ($field.LastMatchWins) { $matches[$matches.Count - 1] } else { $matches[0] }
                        $value = $m.Groups[1].Value.Trim()
                        if ($value) { $fields[$field.Name] = $value; $origin[$field.Name] = "script:$($candidate.Generation)" }
                    }
                }
            }
            break
        }
    }
    if (-not $scriptPath) {
        $wanted = ($source.Scripts | ForEach-Object { $_.FileName }) -join ' or '
        $notes.Add("No deployment script found in this folder - looked for $wanted, up to $($source.SearchDepth) folder(s) deep. Check the path points at the package root, or fill the fields in by hand.")
    }

    # ---- the install instruction document -------------------------------------
    $documentPath = $null
    if ($source.Document) {
        $doc = Get-ChildItem -LiteralPath $PackagePath -Filter $source.Document.Filter -File -Recurse -Depth $source.SearchDepth -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '~$*' } |
               # A readable .docx always beats an old .doc, however recent the
               # .doc is; newest wins only within the same format.
               Sort-Object @{ Expression = { $_.Extension -ieq '.docx' }; Descending = $true },
                           @{ Expression = { $_.LastWriteTime };          Descending = $true } |
               Select-Object -First 1
        if ($doc) {
            $documentPath = $doc.FullName
            $text = Get-AudiDocumentText -Path $doc.FullName
            if ($text) {
                $took = 0
                foreach ($field in $source.Document.Fields) {
                    $m = [regex]::Match($text, $field.Pattern)
                    if ($m.Success) {
                        $value = $m.Groups[1].Value.Trim()
                        if ($value -and -not $fields.Contains($field.Name)) {
                            $fields[$field.Name] = $value; $origin[$field.Name] = 'document'
                            $took++
                        }
                    }
                }
                # Read cleanly but matched nothing: the document exists and is
                # legible, so the headings are not the ones we look for. Say so,
                # otherwise it looks identical to "no document" from outside.
                if ($took -eq 0) {
                    $notes.Add("Read $($doc.Name) but found no description in it - the headings may differ from the standard template. Type the descriptions in by hand.")
                }
            }
            elseif ($doc.Extension -ine '.docx') {
                # .doc is a binary OLE file, not a zip, so the reader cannot open
                # it. Word being installed makes no difference - the fix is the
                # file format.
                $notes.Add("$($doc.Name) is in the old .doc format, which cannot be read. Open it in Word and Save As .docx, or type the descriptions in by hand.")
            }
            else {
                $notes.Add("Instruction document found but no text could be read: $($doc.Name). It may be corrupt or still open in Word.")
            }
        } else { $notes.Add('No install instruction document found in the package - the descriptions have to be typed in by hand.') }
    }

    # ---- description: short, else detailed, else leave it to the caller -------
    # Audi's rule. The short description is what belongs in Software Center; the
    # detailed one is a reasonable second best; if neither is filled in, nothing
    # is invented here and the window falls back to "Publisher - Product -
    # Version" the way it always has.
    foreach ($lang in 'EN', 'DE') {
        $short = "ApplicationDescription$lang"
        $long  = "ApplicationDescription${lang}Long"
        if (-not $fields.Contains($short) -and $fields.Contains($long)) {
            $fields[$short] = $fields[$long]
            $origin[$short] = 'document (detailed)'
        }
        if ($fields.Contains($long)) { $fields.Remove($long); $origin.Remove($long) }
    }

    # ---- SoftIdent: resolve the Wow6432Node placeholder ----------------------
    # The raw value is kept as well, so the packager can still see what the
    # script actually says.
    if ($fields.Contains('SoftIdent')) {
        $resolved = Resolve-AudiSoftIdent -SoftIdent $fields['SoftIdent'] -Architecture $fields['Architecture']
        if ($resolved -ne $fields['SoftIdent']) {
            $fields['SoftIdentRaw'] = $fields['SoftIdent']
            $origin['SoftIdentRaw'] = $origin['SoftIdent']
            $fields['SoftIdent']    = $resolved
            $origin['SoftIdent']    = "$($origin['SoftIdent']) (Wow6432Node resolved for $($fields['Architecture']))"
        }
    }

    return [pscustomobject]@{
        Fields       = $fields
        Origin       = $origin
        Generation   = $generation
        ScriptPath   = $scriptPath
        DocumentPath = $documentPath
        Notes        = @($notes)
    }
}

function Get-AudiIntegrationPlan {
    <#  Turns a package name plus an environment into the exact list of objects
        that would be created. Nothing is contacted and nothing is changed -
        this is what the packager reviews before pressing Integrate, and what
        the engine will walk through in the next increment.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$EnvironmentCode,
        [string]$Rfc = '',
        [string]$JobId,
        [string]$Root,
        # What the packager types, or what Read-AudiPackageDetail found for them.
        # Audi records both languages, so both are carried through to SCCM.
        [string]$LocalizedName,
        [string]$LocalizedDescription,
        [string]$LocalizedNameDe,
        [string]$LocalizedDescriptionDe,

        # What the packager corrected in the window. The package name and the
        # deployment script give the starting values, but the packager has the
        # last word - so whatever is passed here wins over what was derived.
        # Anything left empty keeps the derived value.
        [hashtable]$PartOverride,
        # The branding key IS the first detection rule, and the SoftIdent IS the
        # second - so there is no separate detection field to pass or to keep in
        # step with them.
        [string]$BrandingKey,
        [string]$SoftIdent
    )

    if ([string]::IsNullOrWhiteSpace($JobId)) { $JobId = [guid]::NewGuid().ToString() }

    $defaults = Get-AudiDefaults -Root $Root
    $env      = Get-AudiEnvironment -Code $EnvironmentCode -Root $Root
    $parts    = Split-AudiPackageName -PackageName $PackageName -Root $Root

    # The packager's corrections win over what was parsed out of the name.
    # Split-AudiPackageName hands back a PSCustomObject, which cannot be indexed
    # like a hashtable - so the parts are rebuilt as one rather than poked at.
    if ($PartOverride -and $PartOverride.Count -gt 0) {
        $merged = [ordered]@{}
        foreach ($property in $parts.PSObject.Properties) { $merged[$property.Name] = $property.Value }
        foreach ($key in @($PartOverride.Keys)) {
            $value = [string]$PartOverride[$key]
            if (-not [string]::IsNullOrWhiteSpace($value) -and $merged.Contains($key)) { $merged[$key] = $value }
        }
        $parts = [pscustomobject]$merged
    }

    $branding = if ([string]::IsNullOrWhiteSpace($BrandingKey)) {
        Expand-AudiTemplate -Template $defaults.PackageName.BrandingKeyFormat -Values $parts
    } else { $BrandingKey }

    # ---- the detection rules -------------------------------------------------
    # Rule 1 is the branding key the package writes. Rule 2 is the product's own
    # uninstall entry, taken from the deployment script's VWG_SoftIdent, which
    # already says whether it lives under Wow6432Node. Both must be true.
    # A package whose SoftIdent is missing or written in an unrecognised shape
    # gets rule 1 only - a guessed rule would detect the wrong thing.
    $detection = "$($defaults.Naming.brandingRegistryRoot)$branding"

    $detectionRules = New-Object System.Collections.Generic.List[object]
    $detectionRules.Add([pscustomobject]@{
        Source    = 'Branding key'
        Hive      = 'HKLM'
        Key       = $detection
        ValueName = $defaults.Detection.valueName
        Value     = $parts.Revision
        DataType  = $defaults.Detection.dataType
        Is64Bit   = [bool]::Parse($defaults.Detection.is64Bit)
        Method    = $defaults.Detection.method
    }) | Out-Null

    $softIdentParts = Split-AudiSoftIdent -SoftIdent $SoftIdent -Root $Root
    if ($softIdentParts) {
        $detectionRules.Add([pscustomobject]@{
            Source    = 'SoftIdent'
            Hive      = $softIdentParts.Hive
            Key       = $softIdentParts.Key
            ValueName = $softIdentParts.ValueName
            Value     = $softIdentParts.Value
            DataType  = $defaults.SoftIdentDetection.dataType
            Is64Bit   = [bool]::Parse($defaults.SoftIdentDetection.is64Bit)
            Method    = $(if ($softIdentParts.ValueName) { $defaults.SoftIdentDetection.method } else { 'KeyExists' })
        }) | Out-Null
    }

    # Tokens available to text the tool writes.
    #
    # THERE IS NO REQUESTER ANYWHERE IN THIS TOOL, BY REQUIREMENT.
    # Audi does not want a real person's name to reach the SCCM side at all -
    # not on an SCCM object, and not in the tool's own log on the server. The
    # plan therefore has no Requester field for anything to read, and the name
    # is not offered as a placeholder. The RFC number is the audit link: it is
    # written to every object, and Audi's change system already knows which
    # person that RFC belongs to.
    #
    # Test-AudiSccmCommentTemplate rejects a config file that tries to put
    # {requester} back, so this cannot be undone by an edit on the server.
    $sccmTokens = @{
        package = $PackageName
        jobId   = $JobId
        rfc     = $(if ($Rfc) { $Rfc } else { 'none' })
    }
    $collectionComment = Expand-AudiTemplate -Template $defaults.Comments.collection -Values $sccmTokens
    # The application's admin Comment field in the console. Their tool wrote a
    # fixed 'created by manual MCB script'; this carries the job and the RFC, so
    # the application is traceable the same way its collections are.
    $applicationComment = Expand-AudiTemplate -Template $defaults.Comments.application -Values $sccmTokens

    $collections = @($env.Collections | ForEach-Object {
        [pscustomobject]@{
            Name                 = "$($_.Prefix)$PackageName$($_.Suffix)"
            LimitingCollectionId = $_.LimitingCollectionId
            Folder               = $_.Folder
            DeploymentAction     = $_.DeploymentAction
            Comment              = $collectionComment
        }
    })

    if (-not $LocalizedName)          { $LocalizedName = "$($parts.Publisher) - $($parts.Product) - $($parts.Version)" }
    if (-not $LocalizedDescription)   { $LocalizedDescription = $LocalizedName }
    # German falls back to English rather than being left blank, so the German
    # display entry in SCCM always says something useful.
    if (-not $LocalizedNameDe)        { $LocalizedNameDe = $LocalizedName }
    if (-not $LocalizedDescriptionDe) { $LocalizedDescriptionDe = $LocalizedDescription }

    return [pscustomobject]@{
        JobId           = $JobId
        Executor        = $env.Service.account
        Rfc             = $Rfc
        Environment     = $env.Code
        Verified        = $env.Verified
        SiteCode        = $env.SiteCode
        SiteServer      = $env.SiteServer
        RunnerHost      = $env.RunnerHost
        PackageName     = $PackageName
        Parts           = $parts
        ApplicationName = $PackageName
        LocalizedName          = $LocalizedName
        LocalizedDescription   = $LocalizedDescription
        LocalizedNameDe        = $LocalizedNameDe
        LocalizedDescriptionDe = $LocalizedDescriptionDe
        InstallationBehaviorType = $defaults.DeploymentType.installationBehaviorType
        LogonRequirementType     = $defaults.DeploymentType.logonRequirementType
        MaxRuntimeMinutes        = [int]$defaults.Application.maxRuntimeMinutes
        EstimatedInstallMinutes  = [int]$defaults.Application.estimatedInstallMinutes
        DeploymentType  = "$PackageName$($defaults.Naming.deploymentTypeSuffix)"
        BrandingKey     = $branding
        # THE detection rules. There is no flat copy of rule 1 beside this any
        # more - two representations of the same thing drift apart, and the flat
        # one was already only half true once a second rule existed.
        # .ToArray(), because @() on a List[object] of PSObjects throws under
        # PowerShell 5.1.
        DetectionRules  = $detectionRules.ToArray()

        # Everything the old tool declared on its <DeploymentType>, so the
        # application it creates is identical in every respect.
        ProgramVisibility         = $defaults.DeploymentType.programVisibility
        OnSlowNetworkMode         = $defaults.DeploymentType.slowNetworkDeploymentMode
        AllowClientToShareContent = [bool]::Parse($defaults.DeploymentType.allowClientToShareContent)
        AllowClientToUseFallback  = [bool]::Parse($defaults.DeploymentType.allowClientToUseFallback)
        PersistContentInCache     = [bool]::Parse($defaults.DeploymentType.persistContentInClientCache)
        Run32BitOn64Bit           = [bool]::Parse($defaults.DeploymentType.run32BitOn64Bit)
        # the platform strings for the OS requirement rule
        OperatingSystems          = @($defaults.OperatingSystems | ForEach-Object { $_.Value })
        # read from VWG_SoftIdent in the deployment script, Wow6432Node resolved
        SoftIdent       = $SoftIdent
        ContentPath     = (Join-Path $env.ContentShare $PackageName)
        DistributionPointGroup = $env.DistributionPointGroup
        Category        = $defaults.Application.category
        InstallCommand  = $defaults.Commands.install
        UninstallCommand= $defaults.Commands.uninstall
        # Empty leaves the Repair command unset, which is what the old tool did.
        RepairCommand   = $(if ($defaults.Commands.HasAttribute('repair')) { $defaults.Commands.repair } else { '' })
        # The application's Distribution Settings tab.
        OnDemandDistribution = [bool]::Parse($defaults.Distribution.onDemand)
        PrestagedSetting     = $defaults.Distribution.prestaged
        ApplicationFolder = $env.ApplicationFolder
        Collections     = $collections
        SecurityScopes  = $env.SecurityScopes
        ApplicationComment = $applicationComment
        CreateArsGroup  = $defaults.Steps.CreateArsGroup
        ArsGroupName    = "$($defaults.Naming.arsGroupPrefix)$PackageName"
        ArsGroupOu      = $env.ArsGroupOu
        ArsProviderUrl  = $env.ArsProviderUrl
        ArsDescription  = "$($defaults.Naming.arsDescriptionPrefix)$PackageName"
    }
}
