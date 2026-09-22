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
            # In order of preference; see Defaults.xml. Empty means any file.
            NamePatterns = @($docNode.SelectNodes('NamePattern') | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ })
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
        Deployment       = $d.Deployment
        Naming           = $d.Naming
        Application      = $d.Application
        Detection        = $d.Detection
        DeploymentType   = $d.DeploymentType
        Comments         = $d.Comments
        DescriptionFormat = $d.DescriptionFormat
        Audit            = [pscustomobject]@{ RequireRfc = [bool]::Parse($d.Audit.requireRfc) }
        # What the packager window offers as environments, in file order. The
        # packager chooses - the package name's prefix never decides it. No
        # share per environment: the window only ever writes to the drop folder.
        ClientEnvironments = @($d.ClientEnvironments.Environment | ForEach-Object {
            [pscustomobject]@{ Code = [string]$_.code; Label = [string]$_.label } })
        OperatingSystems = $osList
        PackageName      = [pscustomobject]@{
            Separator         = $d.PackageName.separator
            BrandingKeyFormat = $d.PackageName.brandingKeyFormat
            SccmNameFormat    = $d.PackageName.sccmNameFormat
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
            ResultTimeoutMinutes       = [int]$d.Runtime.resultTimeoutMinutes
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

function New-AudiSiteOnlyPlan {
    <#  The little a job needs when it is not ABOUT one package - Find, and a
        Remove of ticked targets: which site, as whom, under which job. No
        package name is parsed, so a search pattern or a legacy name with a *
        in it never goes near the naming rules or a path.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EnvironmentCode,
        [string]$JobId = '',
        [string]$Rfc = '',
        [string]$Label = 'site',
        [string]$Root
    )
    $env = Get-AudiEnvironment -Code $EnvironmentCode -Root $Root
    if ([string]::IsNullOrWhiteSpace($JobId)) { $JobId = [guid]::NewGuid().ToString() }
    return [pscustomobject]@{
        JobId        = $JobId
        Rfc          = $Rfc
        Environment  = $env.Code
        Verified     = $env.Verified
        SiteCode     = $env.SiteCode
        SiteServer   = $env.SiteServer
        Executor     = $env.Service.account
        PackageName  = $Label
        ContentShare = $env.ContentShare
        DeploymentTypeSuffix = (Get-AudiDefaults -Root $Root).Naming.deploymentTypeSuffix
    }
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

    # Before any convention is tried: a package name becomes SCCM object names,
    # a folder in the store and a folder in the drop folder. ConfigMgr -Name
    # parameters take wildcards, and a path takes separators. Neither may ever
    # be in a name, whatever the naming convention says.
    if ($PackageName -match '[\*\?\[\]\\/:"<>|]' -or $PackageName -match '\s' -or $PackageName -match '\.\.') {
        throw ("Package name '{0}' contains a character that is not allowed in a name: no wildcards (* ? [ ]), " +
               "no path characters (\ / : < > | quote), no spaces, no '..'. Nothing has been done.") -f $PackageName
    }

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

    # Drop pipe-separated segments that lost their value.
    #
    # "Created by ... | job 1234 | RFC {rfc}" with no RFC would otherwise read
    # "... | RFC " - a label pointing at nothing, which looks in the console like
    # somebody forgot to fill something in rather than like a field that is
    # simply not in use here.
    $segments = @($out -split '\s*\|\s*' | Where-Object {
        $_ -and -not ($_ -match '^\s*[A-Za-z][A-Za-z ]*\s*$' -and $_ -notmatch '\s\S')
    })
    return ($segments -join ' | ')
}

function Get-AudiSccmName {
    <#  The one spelling every SCCM object carries: underscore before the
        revision (INA_WinMerge_WinMerge_x64_2.16.58_0001_test), whichever way
        the browsed folder was spelled. Built from the parts and the template
        in Defaults.xml - never by replacing characters in the name, which is
        what corrupted ADO_ADOBE_ into INA_INABE_ in the old tool.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackageName, [string]$Root)
    $defaults = Get-AudiDefaults -Root $Root
    $parts    = Split-AudiPackageName -PackageName $PackageName -Root $Root
    return (Expand-AudiTemplate -Template $defaults.PackageName.SccmNameFormat -Values $parts)
}

function Get-AudiBrandingKey {
    <#  Branding key built from the template in Defaults.xml, not by string
        surgery. Keeps the hyphen between version and revision, because that
        is what the deployment script writes and detection reads.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackageName, [string]$Root)
    $defaults = Get-AudiDefaults -Root $Root
    $parts    = Split-AudiPackageName -PackageName $PackageName -Root $Root
    return (Expand-AudiTemplate -Template $defaults.PackageName.BrandingKeyFormat -Values $parts)
}

function Format-AudiDetectionRule {
    <#  The detection rule as one readable line, for the window, the log and the
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

function Get-AudiProcessName {
    <#  The process names out of one PSADT assignment, whatever shape it is in.

        A real package writes these four ways, and all four appear in the wild:

            @()                                     nothing to close
            @('firefox', 'plugin-container')        plain names
            @('firefox=Mozilla Firefox')            name and a friendly label
            @{ Name = 'firefox'; Description = .. } PSADT 4 process objects

        and one that is not a list at all:

            $adtSession.AppProcessesToClose         a pointer to the hashtable

        The pointer is why this takes the whole field table rather than one
        string: VWG_ProcToClose usually holds no names of its own, it points at
        AppProcessesToClose further up the file. Following it is the difference
        between reading a package's real process list and reading none.

        Returns process names only - never the friendly labels, which are
        sentences and would end up in the Software Center description.  #>
    [CmdletBinding()]
    param([string]$Raw, $Fields)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }
    $value = $Raw.Trim()

    # Follow a pointer into the session hashtable, once. A second hop would mean
    # a package pointing at a pointer, which none do and which could loop.
    $pointer = [regex]::Match($value, '^\$(?:Global:)?(?:adtSession|adtsession)\.(\w+)\s*$')
    if ($pointer.Success) {
        $target = $pointer.Groups[1].Value
        if ($Fields -and $Fields.Contains($target)) { $value = [string]$Fields[$target] }
        else { return @() }
    }

    # An explicitly empty list is a real answer: this package closes nothing.
    if ($value -match '^@\(\s*\)$') { return @() }

    # PSADT 4 process objects name the process in a property; take that and
    # leave the description behind.
    $named = @([regex]::Matches($value, '(?i)\b(?:ProcessName|Name)\s*=\s*[''"]([^''"]+)[''"]') |
               ForEach-Object { $_.Groups[1].Value })

    if ($named.Count -eq 0) {
        # Otherwise every quoted string in the list is a process.
        $named = @([regex]::Matches($value, '[''"]([^''"]+)[''"]') | ForEach-Object { $_.Groups[1].Value })
    }
    if ($named.Count -eq 0) {
        # Last shape: a bare comma list with no quotes at all.
        $named = @($value -replace '^@\(', '' -replace '\)$', '' -split ',')
    }

    return @($named |
             ForEach-Object { ($_ -split '=')[0] } |       # 'firefox=Mozilla Firefox'
             ForEach-Object { $_.Trim().Trim("'", '"').Trim() } |
             Where-Object { $_ -and $_ -notmatch '^\$' })  # a variable is not a process name
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
        # A second place to look for the request form, used ONLY when the
        # package folder holds none. Audi keep the forms apart from the
        # packages, one folder per request:
        #
        #     <DocumentRoot>\<AES-ID> <Vendor> <App> <Version>\Documentation\...
        #
        # The folder is found by the AES ID the deployment script carries
        # (VWG_OrderNumber), which is exact; failing that by vendor, product and
        # version appearing in the folder name, which is fuzzy and says so.
        [string]$DocumentRoot,
        [string]$Root
    )

    $defaults = Get-AudiDefaults -Root $Root
    $source   = $defaults.PackageSource
    $fields   = [ordered]@{}
    $origin   = [ordered]@{}
    $notes    = New-Object System.Collections.Generic.List[string]   # problems - the window shows them amber
    $info     = New-Object System.Collections.Generic.List[string]   # worth telling, not a problem
    $documentFolder = $null                                          # where the form was found, when not in the package

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        $notes.Add("Package path not found: $PackagePath")
        return [pscustomobject]@{ Fields = $fields; Origin = $origin; Generation = $null
                                  ScriptPath = $null; DocumentPath = $null; DocumentFolder = $null; Notes = @($notes); Info = @()
                                  OperatingSystems = @() }
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
                        # First pattern to find something wins. A field name may
                        # be listed more than once - InstallTitle is spelled
                        # differently across PSADT versions - and the ones
                        # earlier in the file are the preferred spellings.
                        if ($value -and -not $fields.Contains($field.Name)) {
                            $fields[$field.Name] = $value; $origin[$field.Name] = "script:$($candidate.Generation)"
                        }
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
        # The order the Word files are read in:
        #   1. the first NamePattern in Defaults.xml that appears in the name
        #      ("Software Integration" before "Install"); a name matching none
        #      ranks last, so a vendor manual never beats the form
        #   2. a readable .docx over an old .doc, however recent the .doc is
        #   3. newest
        $namePatterns = @($source.Document.NamePatterns)
        $rank = {
            param($file)
            for ($i = 0; $i -lt $namePatterns.Count; $i++) {
                # plain text, not a wildcard: a pattern with ( ) [ ] must still match literally
                if ($file.Name.IndexOf([string]$namePatterns[$i], [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $i }
            }
            return $namePatterns.Count
        }
        $candidates = @(Get-ChildItem -LiteralPath $PackagePath -Filter $source.Document.Filter -File -Recurse -Depth $source.SearchDepth -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notlike '~$*' })

        # NO REQUEST FORM IN THE PACKAGE? Look in the documents location.
        #
        # Only the form is fetched from there - the first NamePattern - and
        # only when the package has none of its own. Anything else the package
        # holds (an install document, a vendor sheet) still counts, after it.
        $formInPackage = @($candidates | Where-Object { (& $rank $_) -eq 0 })
        if ($formInPackage.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($DocumentRoot)) {
            $found = Find-AudiDocumentFolder -DocumentRoot $DocumentRoot `
                        -Rfc $(if ($fields.Contains('OrderNumber')) { [string]$fields['OrderNumber'] } else { '' }) `
                        -Publisher $(if ($fields.Contains('Publisher')) { [string]$fields['Publisher'] } else { '' }) `
                        -Product   $(if ($fields.Contains('Product'))   { [string]$fields['Product'] }   else { '' }) `
                        -Version   $(if ($fields.Contains('Version'))   { [string]$fields['Version'] }   else { '' })
            if ($found.Folder) {
                $documentFolder = $found.Folder
                $fromRoot = @(Get-ChildItem -LiteralPath $found.Folder -Filter $source.Document.Filter -File -Recurse -Depth $source.SearchDepth -ErrorAction SilentlyContinue |
                              Where-Object { $_.Name -notlike '~$*' -and (& $rank $_) -eq 0 })
                if ($fromRoot.Count -gt 0) {
                    $candidates = @($fromRoot) + @($candidates)
                    $info.Add(("Request form taken from the documents location: {0} ({1})." -f (Split-Path -Leaf $found.Folder), $found.How))
                } else {
                    $notes.Add(("Found the documents folder {0} ({1}) but no request form in it - nothing named 'Software Integration'." -f (Split-Path -Leaf $found.Folder), $found.How))
                }
            }
            else { $notes.Add($found.Why) }
        }

        $candidates = @($candidates |
                        Sort-Object @{ Expression = { & $rank $_ };                Descending = $false },
                                    @{ Expression = { $_.Extension -ieq '.docx' }; Descending = $true },
                                    @{ Expression = { $_.LastWriteTime };          Descending = $true })

        # EVERY Word file is read, in that order, and a field is taken from the
        # first file that has it. So the request form gives the description
        # when it can; an install instruction fills in whatever the form left
        # blank; and any other document is a last resort. Nothing read later
        # overwrites what an earlier, higher-ranked file said.
        $readFrom  = New-Object System.Collections.Generic.List[string]
        $unreadable = New-Object System.Collections.Generic.List[string]
        foreach ($doc in $candidates) {
            $text = Get-AudiDocumentText -Path $doc.FullName
            if (-not $text) {
                if ($doc.Extension -ine '.docx') { $unreadable.Add("$($doc.Name) (old .doc format - Save As .docx to make it readable)") }
                else                             { $unreadable.Add("$($doc.Name) (no text could be read - corrupt, or open in Word)") }
                continue
            }
            $took = 0
            foreach ($field in $source.Document.Fields) {
                if ($fields.Contains($field.Name)) { continue }
                $m = [regex]::Match($text, $field.Pattern)
                if (-not $m.Success) { continue }
                $value = $m.Groups[1].Value.Trim()
                if ($value) {
                    $fields[$field.Name] = $value; $origin[$field.Name] = "document: $($doc.Name)"
                    $took++
                }
            }
            if ($took -gt 0) {
                $readFrom.Add($doc.Name)
                # the first file that gave anything is THE document of record
                if (-not $documentPath) { $documentPath = $doc.FullName }
            }
        }
        # Nothing gave a description: fall back to the best-ranked file as the
        # document of record, so the packager can still open it from the window.
        if (-not $documentPath -and $candidates.Count -gt 0) { $documentPath = $candidates[0].FullName }

        $hasDescription = $fields.Contains('ApplicationDescriptionEN') -or $fields.Contains('ApplicationDescriptionDE') -or
                          $fields.Contains('ApplicationDescriptionENLong') -or $fields.Contains('ApplicationDescriptionDELong')
        if ($candidates.Count -eq 0) {
            $notes.Add('No Word document found in the package - the descriptions have to be typed in by hand.')
        }
        elseif (-not $hasDescription) {
            $notes.Add(("Read {0} Word file(s) but found no description in any of them - the headings may differ from the standard template. Type the descriptions in by hand." -f $candidates.Count))
        }
        if ($readFrom.Count -gt 0) {
            $info.Add(("Read from: {0}." -f ($readFrom -join ', ')))
        }
        if ($unreadable.Count -gt 0) {
            $notes.Add(("Could not read: {0}." -f ($unreadable -join '; ')))
        }
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

    # ---- the processes the package closes go IN FRONT of the description ------
    # Somebody with a file open in the application being replaced needs to know
    # that before the marketing sentence, not after it.
    #
    # NonUI first, plain ProcToClose as the fallback. If the package closes
    # nothing, neither line appears - an empty "will be closed:" sentence is
    # worse than no sentence.
    # NonUI first, then the interactive list, then the session hashtable itself.
    # Each is resolved through Get-AudiProcessName, which follows the
    # $adtSession.AppProcessesToClose pointer a real package uses.
    $names = @()
    foreach ($candidate in 'ProcToCloseNonUI', 'ProcToClose', 'AppProcessesToClose') {
        if ($names.Count -gt 0) { continue }
        if (-not $fields.Contains($candidate)) { continue }
        $names = @(Get-AudiProcessName -Raw ([string]$fields[$candidate]) -Fields $fields)
    }
    # Every list empty - @() in the script - means the package closes nothing,
    # and the description is the description on its own.
    if ($true) {
        if ($names.Count -gt 0) {
            $list    = $names -join ','
            $format  = $defaults.DescriptionFormat
            $prefix  = @{ EN = $format.processPrefixEn.Replace('{processes}', $list)
                          DE = $format.processPrefixDe.Replace('{processes}', $list) }
            foreach ($lang in 'EN', 'DE') {
                $key = "ApplicationDescription$lang"
                $body = $(if ($fields.Contains($key)) { [string]$fields[$key] } else { '' })
                # Do not prepend twice if a description already carries it.
                if ($body -like "$($prefix[$lang])*") { continue }
                $fields[$key] = ($prefix[$lang] + $body).Trim()
                $origin[$key] = $(if ($body) { "$($origin[$key]) + processes from the script" }
                                  else       { 'processes from the script' })
            }
            $fields['ProcessesClosed'] = $list
            $origin['ProcessesClosed'] = 'script'
        }
    }

    # ---- which Windows versions the document ticked --------------------------
    # The document fields are named OperatingSystem:<key>, and a field only
    # exists when its box carried a tick. An empty list means the document said
    # nothing, NOT that no platform is wanted - the plan requires all of them in
    # that case rather than building an application nothing can install.
    $operatingSystems = @($fields.Keys |
        Where-Object { $_ -like 'OperatingSystem:*' } |
        ForEach-Object { $_.Substring('OperatingSystem:'.Length) })

    return [pscustomobject]@{
        OperatingSystems = $operatingSystems
        Fields       = $fields
        Origin       = $origin
        Generation   = $generation
        ScriptPath   = $scriptPath
        DocumentPath = $documentPath
        DocumentFolder = $documentFolder   # set only when the form came from the documents location
        Notes        = @($notes)
        Info         = @($info)
    }
}

function Get-AudiPackageContentRoot {
    <#  Which folder holds what SCCM needs - the deployment script and
        everything beside it.

        Two shapes come in:

            <package>\Content\Invoke-AppDeployToolkit.ps1   plus Documents\, Icons\ ...
            <package>\Invoke-AppDeployToolkit.ps1           already just the content

        Only the CONTENT goes to the content share, so the first shape copies
        Content\ and the second copies the folder as it is. Returns the folder
        to copy from, or throws when neither shape is recognised - a package
        with no deployment script must not be put on the share.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackagePath, [string]$Root)

    $defaults = Get-AudiDefaults -Root $Root
    $scriptNames = @($defaults.PackageSource.Scripts | ForEach-Object { $_.FileName })

    $atRoot = @($scriptNames | Where-Object { Test-Path -LiteralPath (Join-Path $PackagePath $_) })
    if ($atRoot.Count -gt 0) { return $PackagePath }

    $content = Join-Path $PackagePath 'Content'
    if (Test-Path -LiteralPath $content) {
        $inContent = @($scriptNames | Where-Object { Test-Path -LiteralPath (Join-Path $content $_) })
        if ($inContent.Count -gt 0) { return $content }
    }

    throw ("No deployment script ({0}) at the top of '{1}' or in its Content folder. " +
           "The content share gets the folder that holds the script, and there is none.") -f ($scriptNames -join ' / '), $PackagePath
}

function Get-AudiFreeSpace {
    <#  Free bytes on the volume behind a path - local or UNC. DriveInfo does
        not do UNC, so this asks Windows directly. -1 when it cannot be read;
        a caller then goes ahead and lets the copy speak for itself.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        if (-not ('AudiSw.DiskSpace' -as [type])) {
            Add-Type -Namespace AudiSw -Name DiskSpace -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool GetDiskFreeSpaceEx(string path, out ulong freeToCaller, out ulong total, out ulong free);
'@
        }
        $free = [uint64]0; $total = [uint64]0; $freeAll = [uint64]0
        $probe = $Path
        while ($probe -and -not (Test-Path -LiteralPath $probe)) { $probe = Split-Path -Parent $probe }
        if (-not $probe) { return -1 }
        if ([AudiSw.DiskSpace]::GetDiskFreeSpaceEx($probe, [ref]$free, [ref]$total, [ref]$freeAll)) { return [long]$free }
        return -1
    }
    catch { return -1 }
}

function Assert-AudiEnoughSpace {
    <#  Refuses a copy that would fill the target volume - before a single
        byte moves, with the numbers, rather than half-way through with a
        cryptic write error. A margin is kept so the volume is never left at
        zero.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][long]$Bytes, [long]$MarginBytes = 2GB, [string]$What = 'the copy')
    $free = Get-AudiFreeSpace -Path $Path
    if ($free -lt 0) { return }
    if ($free -lt ($Bytes + $MarginBytes)) {
        throw ("Not enough free space for {0}: it needs {1:N1} GB (plus a {2:N1} GB margin) and the volume behind {3} has {4:N1} GB free. Nothing was copied." -f `
               $What, ($Bytes / 1GB), ($MarginBytes / 1GB), $Path, ($free / 1GB))
    }
}

function Copy-AudiPackageContent {
    <#  Puts the package's content on the content share, under its SCCM name.

            <ContentShare>\<sccm name>\  <-  Get-AudiPackageContentRoot($PackagePath)\*

        Copies into a temporary folder beside the target first and renames it
        into place at the end, so a half-copied package is never left under
        the real name for SCCM - or a second packager - to pick up. Returns
        @{ Target; Copied; Files }.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$ContentShare,
        [Parameter(Mandatory = $true)][string]$SccmName,
        [scriptblock]$OnProgress,
        # Refresh: a folder already there is replaced - the new copy is staged
        # in full first, the old folder stepped aside, the new one renamed in,
        # the old one deleted. At no moment is there no folder under the name.
        [switch]$Replace,
        [string]$Root
    )

    $source = Get-AudiPackageContentRoot -PackagePath $PackagePath -Root $Root
    $target = Join-Path $ContentShare $SccmName
    if ((Test-Path -LiteralPath $target) -and -not $Replace) {
        return @{ Target = $target; Copied = $false; Files = 0 }
    }
    if (-not (Test-Path -LiteralPath $ContentShare)) {
        throw "The content share cannot be opened: $ContentShare"
    }

    $staging = Join-Path $ContentShare ("~{0}.copying" -f $SccmName)
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }

    $files = @(Get-ChildItem -LiteralPath $source -File -Recurse)
    $total = $files.Count; $done = 0
    $need = 0; foreach ($f in $files) { $need += $f.Length }
    Assert-AudiEnoughSpace -Path $ContentShare -Bytes $need -What "the package content ($total files)"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($source.TrimEnd('\').Length).TrimStart('\')
            $dest = Join-Path $staging $relative
            $dir  = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
            $done++
            if ($OnProgress) { & $OnProgress $done $total $relative }
        }
        # VERIFIED before it gets the real name: file count and total bytes on
        # both sides must agree. A copy that does not is dropped and reported,
        # never renamed into place for SCCM to distribute half of.
        $expectedBytes = 0; foreach ($f in $files) { $expectedBytes += $f.Length }
        $copiedFiles = @(Get-ChildItem -LiteralPath $staging -File -Recurse -Force)
        $copiedBytes = 0; foreach ($f in $copiedFiles) { $copiedBytes += $f.Length }
        if ($copiedFiles.Count -ne $total -or $copiedBytes -ne $expectedBytes) {
            throw ("The copy to {0} did not verify: source {1} file(s) / {2} bytes, copy {3} file(s) / {4} bytes. Nothing was put under the real name." -f `
                   $target, $total, $expectedBytes, $copiedFiles.Count, $copiedBytes)
        }
        $previous = Join-Path $ContentShare ("~{0}.previous" -f $SccmName)
        if ($Replace -and (Test-Path -LiteralPath $target)) {
            if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force }
            Rename-Item -LiteralPath $target -NewName (Split-Path -Leaf $previous)
        }
        Rename-Item -LiteralPath $staging -NewName $SccmName
        if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Recurse -Force -ErrorAction SilentlyContinue }
    }
    catch {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
    return @{ Target = $target; Copied = $true; Files = $total; Bytes = $expectedBytes; Replaced = [bool]$Replace }
}

function Sync-AudiPackageContent {
    <#  UPDATE CONTENT WITHOUT COPYING EVERYTHING AGAIN.

        Compares the new files (in the SCCM-side Sources) with what is in the
        store, file by file, and touches only what differs:
          * a file that is not in the store            -> added
          * a file whose size or SHA-256 differs       -> replaced
          * a file in the store that is no longer sent -> removed
          * everything else                            -> left exactly as it is
        Timestamps are NEVER part of the comparison - they differ between the
        machine a package was built on and the share it was copied to - and
        the tool never rewrites one: a replaced file keeps the timestamp it has
        in Sources. Content is judged by what is in it, not when it was saved.

        Each replaced or added file is written to a temporary name beside its
        target and moved into place, so a file is never half-written under
        its real name. Afterwards the whole tree is verified: file count and
        bytes must agree with Sources.

        Returns @{ Added; Replaced; Removed; Unchanged; Bytes; Files; Changed }
        - Changed is the list of relative paths that were touched, for the
        result message.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [scriptblock]$OnProgress
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "There are no new files to sync from: $Source" }
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) { New-Item -ItemType Directory -Path $Target -Force | Out-Null }

    $srcRoot = $Source.TrimEnd('\'); $dstRoot = $Target.TrimEnd('\')
    $relative = { param($file, $root) $file.FullName.Substring($root.Length).TrimStart('\') }
    $srcFiles = @(Get-ChildItem -LiteralPath $srcRoot -File -Recurse -Force)
    $dstFiles = @(Get-ChildItem -LiteralPath $dstRoot -File -Recurse -Force | Where-Object { $_.Name -notlike '~*.syncing' })
    $dstByRel = @{}; foreach ($f in $dstFiles) { $dstByRel[(& $relative $f $dstRoot).ToLowerInvariant()] = $f }

    $added = 0; $replaced = 0; $unchanged = 0; $removed = 0; $bytes = 0
    $changed = New-Object System.Collections.Generic.List[string]
    $total = $srcFiles.Count; $n = 0
    foreach ($src in $srcFiles) {
        $n++
        $rel = & $relative $src $srcRoot
        $bytes += $src.Length
        $dst = $dstByRel[$rel.ToLowerInvariant()]
        $same = $false
        if ($dst -and $dst.Length -eq $src.Length) {
            # same size: only a hash can tell - never the timestamp
            $same = ((Get-FileHash -LiteralPath $src.FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $dst.FullName -Algorithm SHA256).Hash)
        }
        if ($same) { $unchanged++; if ($OnProgress) { & $OnProgress $n $total $rel 'same' }; continue }

        $final = Join-Path $dstRoot $rel
        $dir   = Split-Path -Parent $final
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $temp = Join-Path $dir ("~{0}.syncing" -f (Split-Path -Leaf $final))
        Copy-Item -LiteralPath $src.FullName -Destination $temp -Force
        # keep the timestamp the file has in Sources - the tool never stamps content
        (Get-Item -LiteralPath $temp -Force).LastWriteTimeUtc = $src.LastWriteTimeUtc
        Move-Item -LiteralPath $temp -Destination $final -Force
        if ($dst) { $replaced++ } else { $added++ }
        $changed.Add($rel) | Out-Null
        if ($OnProgress) { & $OnProgress $n $total $rel $(if ($dst) { 'replaced' } else { 'added' }) }
    }
    # what the new package no longer has must not stay in the store
    $srcRel = @{}; foreach ($f in $srcFiles) { $srcRel[(& $relative $f $srcRoot).ToLowerInvariant()] = $true }
    foreach ($key in @($dstByRel.Keys)) {
        if (-not $srcRel.ContainsKey($key)) { Remove-Item -LiteralPath $dstByRel[$key].FullName -Force; $removed++; $changed.Add("- " + (& $relative $dstByRel[$key] $dstRoot)) | Out-Null }
    }
    # empty folders left behind by removed files
    foreach ($d in @(Get-ChildItem -LiteralPath $dstRoot -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending)) {
        if (@(Get-ChildItem -LiteralPath $d.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue }
    }

    # VERIFY the whole tree, not just what was touched
    $after = @(Get-ChildItem -LiteralPath $dstRoot -File -Recurse -Force)
    $afterBytes = 0; foreach ($f in $after) { $afterBytes += $f.Length }
    if ($after.Count -ne $total -or $afterBytes -ne $bytes) {
        throw ("The store does not match Sources after the update: Sources {0} file(s) / {1} bytes, store {2} file(s) / {3} bytes." -f $total, $bytes, $after.Count, $afterBytes)
    }
    return @{ Added = $added; Replaced = $replaced; Removed = $removed; Unchanged = $unchanged; Files = $total; Bytes = $bytes; Changed = $changed.ToArray() }
}

function Remove-AudiPackageContent {
    <#  Deletes ONE package folder from the content store - and only when it
        is what it should be: directly under the store root, not the root
        itself, no wildcard in the path, and actually a folder. Everything is
        -LiteralPath, so no character in a name is ever a pattern. Returns
        @{ Removed; Path; Reason }.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContentShare,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path
    )
    $root = $ContentShare.TrimEnd('\')
    $full = $Path.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($full))                       { return @{ Removed = $false; Path = $Path; Reason = 'no content path is known for it' } }
    if ($full -match '[\*\?]')                                     { return @{ Removed = $false; Path = $Path; Reason = 'the path contains a wildcard character' } }
    if ($full.TrimEnd('\') -ieq $root)                             { return @{ Removed = $false; Path = $Path; Reason = 'it is the store root itself' } }
    if (-not $full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                                                                     return @{ Removed = $false; Path = $Path; Reason = "it is not under this environment's store ($root)" } }
    if ((Split-Path -Parent $full).TrimEnd('\') -ine $root)         { return @{ Removed = $false; Path = $Path; Reason = 'it is not directly under the store root' } }
    # .NET, not the provider cmdlets: the caller may still be standing on the
    # CMSite drive, where Test-Path / Remove-Item on a UNC path fall over with
    # a null reference. Directory.Exists/Delete do not care where the session
    # is. Read-only files (installers often carry them) are cleared first,
    # because Directory.Delete refuses them where Remove-Item -Force would not.
    if (-not [System.IO.Directory]::Exists($full))                 { return @{ Removed = $false; Path = $Path; Reason = 'there is no such folder (already gone)' } }
    foreach ($f in [System.IO.Directory]::EnumerateFileSystemEntries($full, '*', [System.IO.SearchOption]::AllDirectories)) {
        $attr = [System.IO.File]::GetAttributes($f)
        if ($attr -band [System.IO.FileAttributes]::ReadOnly) { [System.IO.File]::SetAttributes($f, $attr -bxor [System.IO.FileAttributes]::ReadOnly) }
    }
    [System.IO.Directory]::Delete($full, $true)
    if ([System.IO.Directory]::Exists($full)) { throw "the folder is still there after the delete - a file in it is probably open on the server" }
    return @{ Removed = $true; Path = $full; Reason = '' }
}

function Find-AudiDocumentFolder {
    <#  The request's own folder under the documents location.

            <DocumentRoot>\AES-1-020879-A WinMerge WinMerge 2.16.58\Documentation\...

        Found by the AES ID first - it is unique, and the script carries it as
        VWG_OrderNumber - and only if that fails by the vendor, product and
        version all appearing in the folder name. The second is a guess, and
        the answer says so, so the packager can check the folder it picked.

        Returns @{ Folder; How; Why } - Folder is $null when nothing matched. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DocumentRoot,
        [string]$Rfc, [string]$Publisher, [string]$Product, [string]$Version
    )

    if (-not (Test-Path -LiteralPath $DocumentRoot)) {
        return @{ Folder = $null; How = ''; Why = "The documents location cannot be opened: $DocumentRoot." }
    }
    $folders = @(Get-ChildItem -LiteralPath $DocumentRoot -Directory -ErrorAction SilentlyContinue)
    if ($folders.Count -eq 0) {
        return @{ Folder = $null; How = ''; Why = "The documents location is empty: $DocumentRoot." }
    }

    $has = { param($name, $text) -not [string]::IsNullOrWhiteSpace($text) -and $name.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }

    if ($Rfc) {
        $byRfc = @($folders | Where-Object { & $has $_.Name $Rfc } | Sort-Object LastWriteTime -Descending)
        if ($byRfc.Count -gt 0) {
            return @{ Folder = $byRfc[0].FullName; How = "matched by the AES ID $Rfc"; Why = '' }
        }
    }

    # Fuzzy: PRODUCT and VERSION have to appear in the folder name. The vendor
    # is not required - Audi's folders leave it out when it equals the app
    # name, shorten it, or abbreviate it - but a folder that does carry it is
    # preferred over one that does not. Underscores, dots and hyphens are
    # treated as spaces, so "Acrobat_Reader" finds "Acrobat Reader" and
    # "2.16.58" finds "2_16_58".
    $norm = { param($s) ([string]$s -replace '[_.\-]', ' ') -replace '\s+', ' ' }
    $wanted = @($Product, $Version | Where-Object { $_ } | ForEach-Object { & $norm $_ })
    $vendor = $(if ($Publisher) { & $norm $Publisher } else { '' })
    if ($wanted.Count -gt 0) {
        $fuzzy = @($folders | Where-Object {
            $name = & $norm $_.Name
            $ok = $true
            foreach ($w in $wanted) { if (-not (& $has $name $w)) { $ok = $false } }
            $ok
        } | Sort-Object @{ Expression = { & $has (& $norm $_.Name) $vendor }; Descending = $true },
                        @{ Expression = { $_.LastWriteTime };                Descending = $true })
        if ($fuzzy.Count -gt 0) {
            $how = "matched by name on '$($wanted -join "', '")'" + $(if ($fuzzy.Count -gt 1) { " - $($fuzzy.Count) folders matched, the one naming the vendor / newest taken" } else { '' })
            return @{ Folder = $fuzzy[0].FullName; How = $how; Why = '' }
        }
    }

    $looked = @(@($(if ($Rfc) { "AES ID $Rfc" })) + @($wanted | ForEach-Object { "'$_'" }) | Where-Object { $_ })
    return @{ Folder = $null; How = ''
              Why = "No folder under $DocumentRoot matches this package (looked for $($looked -join ', ')). The request form was not found." }
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
        # The branding key IS the detection rule - so there is no separate
        # detection field to pass or to keep in step with it.
        [string]$BrandingKey,
        # Which Windows versions the install instruction document ticked, as
        # OperatingSystems/@key values. Empty means the document said nothing
        # and every configured platform is required.
        [string[]]$OperatingSystemKeys = @()
    )

    if ([string]::IsNullOrWhiteSpace($JobId)) { $JobId = [guid]::NewGuid().ToString() }

    $defaults = Get-AudiDefaults -Root $Root
    $env      = Get-AudiEnvironment -Code $EnvironmentCode -Root $Root
    $parts    = Split-AudiPackageName -PackageName $PackageName -Root $Root

    # Everything on the SCCM side - application, deployment type, collections,
    # AD group, content folder - carries the underscore spelling, whichever
    # way the job named the package. Only the branding key keeps the hyphen.
    $PackageName = Expand-AudiTemplate -Template $defaults.PackageName.SccmNameFormat -Values $parts
    $parts.PackageName = $PackageName

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

    # ---- the detection rule --------------------------------------------------
    # ONE rule: the branding key the package writes, with the revision as its
    # value. Audi detect on this alone. A second rule on the vendor's own
    # uninstall entry was tried and dropped: when a vendor key moves between
    # builds, a package that IS installed reads as not installed and reinstalls
    # on every evaluation. Kept as a list so the provider's shape is unchanged.
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
        # Empty, not the word "none": an empty value lets the whole "| RFC ..."
        # segment drop out of the comment. "RFC none" reads in the console like
        # somebody typed the word none into the field.
        rfc     = $Rfc
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

    # Whether these were SUPPLIED or merely derived matters to Modify.
    #
    # Integrate has to put something in Software Center, so a name derived from
    # the package name is better than nothing. Modify is different: a second
    # packager, on a second machine, who typed only the package name has not
    # asked to rename anything - and writing the derived name would quietly
    # replace whatever the person who integrated it chose.
    #
    # So the plan records which it is, and the Modify step writes only what a
    # human actually supplied.
    $localizedNameSupplied        = [bool]$LocalizedName
    $localizedDescriptionSupplied = [bool]$LocalizedDescription

    if (-not $LocalizedName)          { $LocalizedName = "$($parts.Publisher) - $($parts.Product) - $($parts.Version)" }
    if (-not $LocalizedDescription)   { $LocalizedDescription = $LocalizedName }
    # German falls back to English rather than being left blank, so the German
    # display entry in SCCM always says something useful.
    # Same rule for the German pair: falling back to the English text is right
    # when creating, and wrong when modifying - it would overwrite a real German
    # description with the English one.
    $localizedNameDeSupplied        = [bool]$LocalizedNameDe
    $localizedDescriptionDeSupplied = [bool]$LocalizedDescriptionDe

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
        # false = derived from the package name, so Modify leaves the live
        # value alone rather than overwriting a human's wording with ours.
        LocalizedNameSupplied          = $localizedNameSupplied
        LocalizedDescriptionSupplied   = $localizedDescriptionSupplied
        LocalizedNameDeSupplied        = $localizedNameDeSupplied
        LocalizedDescriptionDeSupplied = $localizedDescriptionDeSupplied
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
        # The platform strings for the OS requirement rule.
        #
        # When the install instruction document says which Windows versions the
        # package is for - the ticked boxes on its operating system line - only
        # those are required. The document is the request; requiring a platform
        # nobody asked for makes the application offer itself to machines the
        # requester deliberately left out.
        #
        # No keys given means the document said nothing, and every configured
        # platform is required, which is what the tool did before.
        OperatingSystems          = $(
            $wantedOs = @($OperatingSystemKeys | Where-Object { $_ })
            if ($wantedOs.Count -gt 0) {
                $matched = @($defaults.OperatingSystems | Where-Object { $wantedOs -contains $_.Key })
                if ($matched.Count -gt 0) { @($matched | ForEach-Object { $_.Value }) }
                else { @($defaults.OperatingSystems | ForEach-Object { $_.Value }) }
            }
            else { @($defaults.OperatingSystems | ForEach-Object { $_.Value }) })
        ContentPath     = (Join-Path $env.ContentShare $PackageName)
        ContentShare    = $env.ContentShare
        DistributionPointGroup = $env.DistributionPointGroup
        Category        = $defaults.Application.category
        InstallCommand  = $defaults.Commands.install
        UninstallCommand= $defaults.Commands.uninstall
        # Empty leaves the Repair command unset, which is what the old tool did.
        RepairCommand   = $(if ($defaults.Commands.HasAttribute('repair')) { $defaults.Commands.repair } else { '' })
        # The application's Distribution Settings tab.
        OnDemandDistribution = [bool]::Parse($defaults.Distribution.onDemand)
        PrestagedSetting     = $defaults.Distribution.prestaged
        # "Allow end users to attempt to repair this application", on the
        # deployment - not on the deployment type, which only holds the command.
        AllowUserRepair      = [bool]::Parse($defaults.Deployment.allowUserRepair)
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
