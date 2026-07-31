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

    $parts = @($result.Document.SelectNodes('/Defaults/PackageName/Part')) |
        ForEach-Object {
            [pscustomobject]@{
                Name         = $_.name
                Index        = $(if ($_.HasAttribute('index'))        { [int]$_.index }        else { $null })
                IndexFromEnd = $(if ($_.HasAttribute('indexFromEnd')) { [int]$_.indexFromEnd } else { $null })
                Remainder    = $(if ($_.HasAttribute('remainder'))    { [bool]::Parse($_.remainder) } else { $false })
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

    $script:AudiDefaultsCache = [pscustomobject]@{
        SchemaVersion    = $d.schemaVersion
        Commands         = $d.Commands
        Naming           = $d.Naming
        Application      = $d.Application
        Detection        = $d.Detection
        DeploymentType   = $d.DeploymentType
        Comments         = $d.Comments
        OperatingSystems = $osList
        PackageName      = [pscustomobject]@{
            Separator         = $d.PackageName.separator
            MinimumParts      = [int]$d.PackageName.minimumParts
            BrandingKeyFormat = $d.PackageName.brandingKeyFormat
            Parts             = $parts
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
        Path             = $path
    }
    return $script:AudiDefaultsCache
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
        Service           = $e.Service
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
    <#  Splits a package name into its parts using the layout in Defaults.xml.

        The tool being replaced did this with a text replacement, which corrupted
        any name whose site code appeared again later - ADO_ADOBE_Reader became
        INA_INABE_Reader. Parts are located by position instead, counting from
        the front for the leading parts and from the back for the trailing ones,
        so a product name containing the separator still parses.  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [string]$Root
    )

    $defaults = Get-AudiDefaults -Root $Root
    $spec     = $defaults.PackageName
    $tokens   = @($PackageName.Split($spec.Separator))

    if ($tokens.Count -lt $spec.MinimumParts) {
        throw ("Package name '{0}' has {1} parts; at least {2} are expected ({3})." -f `
               $PackageName, $tokens.Count, $spec.MinimumParts,
               (($spec.Parts | ForEach-Object { $_.Name }) -join $spec.Separator))
    }

    $result   = [ordered]@{}
    $leading  = 0
    $trailing = 0

    foreach ($part in $spec.Parts) {
        if ($null -ne $part.Index)        { $result[$part.Name] = $tokens[$part.Index]; $leading  = [Math]::Max($leading,  $part.Index + 1) }
        elseif ($null -ne $part.IndexFromEnd) { $result[$part.Name] = $tokens[$tokens.Count - $part.IndexFromEnd]; $trailing = [Math]::Max($trailing, $part.IndexFromEnd) }
    }

    foreach ($part in $spec.Parts) {
        if ($part.Remainder) {
            $count = $tokens.Count - $trailing - $leading
            if ($count -lt 1) { throw "Package name '$PackageName' leaves nothing for '$($part.Name)'." }
            $result[$part.Name] = ($tokens[$leading..($leading + $count - 1)] -join $spec.Separator)
        }
    }

    $result['PackageName'] = $PackageName
    return [pscustomobject]$result
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

function Get-AudiDocumentText {
    <#  Plain text out of a .docx, without needing Word installed.  #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = $null
    try {
        $zip   = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' } | Select-Object -First 1
        if (-not $entry) { return '' }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    catch { return '' }
    finally { if ($zip) { $zip.Dispose() } }

    # paragraph and line breaks become newlines, then drop the remaining markup
    $text = $xml -replace '</w:p>', "`r`n" -replace '<w:br[^>]*/>', "`r`n"
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
    if (-not $scriptPath) { $notes.Add('No PSADT deployment script found in the package.') }

    # ---- the install instruction document -------------------------------------
    $documentPath = $null
    if ($source.Document) {
        $doc = Get-ChildItem -LiteralPath $PackagePath -Filter $source.Document.Filter -File -Recurse -Depth $source.SearchDepth -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '~$*' } |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($doc) {
            $documentPath = $doc.FullName
            $text = Get-AudiDocumentText -Path $doc.FullName
            if ($text) {
                foreach ($field in $source.Document.Fields) {
                    $m = [regex]::Match($text, $field.Pattern)
                    if ($m.Success) {
                        $value = $m.Groups[1].Value.Trim()
                        if ($value -and -not $fields.Contains($field.Name)) {
                            $fields[$field.Name] = $value; $origin[$field.Name] = 'document'
                        }
                    }
                }
            } else { $notes.Add("Instruction document found but no text could be read: $($doc.Name)") }
        } else { $notes.Add('No install instruction document found in the package.') }
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
        [string]$Requester = "$env:USERDOMAIN\$env:USERNAME",
        [string]$Rfc = '',
        [string]$JobId,
        [string]$Root,
        # What the packager types, or what Read-AudiPackageDetail found for them.
        [string]$LocalizedName,
        [string]$LocalizedDescription
    )

    if ([string]::IsNullOrWhiteSpace($JobId)) { $JobId = [guid]::NewGuid().ToString() }

    $defaults = Get-AudiDefaults -Root $Root
    $env      = Get-AudiEnvironment -Code $EnvironmentCode -Root $Root
    $parts    = Split-AudiPackageName -PackageName $PackageName -Root $Root
    $branding = Get-AudiBrandingKey -PackageName $PackageName -Root $Root

    $tokens = @{
        package   = $PackageName
        jobId     = $JobId
        requester = $Requester
        rfc       = $(if ($Rfc) { $Rfc } else { 'none' })
    }
    $collectionComment = Expand-AudiTemplate -Template $defaults.Comments.collection -Values $tokens

    $collections = @($env.Collections | ForEach-Object {
        [pscustomobject]@{
            Name                 = "$($_.Prefix)$PackageName$($_.Suffix)"
            LimitingCollectionId = $_.LimitingCollectionId
            Folder               = $_.Folder
            DeploymentAction     = $_.DeploymentAction
            Comment              = $collectionComment
        }
    })

    if (-not $LocalizedName)        { $LocalizedName = "$($parts.Publisher) - $($parts.Product) - $($parts.Version)" }
    if (-not $LocalizedDescription) { $LocalizedDescription = $LocalizedName }

    return [pscustomobject]@{
        JobId           = $JobId
        Requester       = $Requester
        Executor        = $env.Service.account
        Rfc             = $Rfc
        Environment     = $env.Code
        Verified        = $env.Verified
        SiteCode        = $env.SiteCode
        SiteServer      = $env.SiteServer
        ServiceAddress  = $env.Service.address
        ServiceConfigurationName = $env.Service.configurationName
        PackageName     = $PackageName
        Parts           = $parts
        ApplicationName = $PackageName
        LocalizedName        = $LocalizedName
        LocalizedDescription = $LocalizedDescription
        InstallationBehaviorType = $defaults.DeploymentType.installationBehaviorType
        LogonRequirementType     = $defaults.DeploymentType.logonRequirementType
        MaxRuntimeMinutes        = [int]$defaults.Application.maxRuntimeMinutes
        EstimatedInstallMinutes  = [int]$defaults.Application.estimatedInstallMinutes
        DeploymentType  = "$PackageName$($defaults.Naming.deploymentTypeSuffix)"
        BrandingKey     = $branding
        DetectionKey    = "$($defaults.Naming.brandingRegistryRoot)$branding"
        DetectionValue  = $defaults.Detection.valueName
        DetectionData   = $parts.Revision
        ContentPath     = (Join-Path $env.ContentShare $PackageName)
        DistributionPointGroup = $env.DistributionPointGroup
        Category        = $defaults.Application.category
        InstallCommand  = $defaults.Commands.install
        UninstallCommand= $defaults.Commands.uninstall
        ApplicationFolder = $env.ApplicationFolder
        Collections     = $collections
        SecurityScopes  = $env.SecurityScopes
        ArsGroupName    = "$($defaults.Naming.arsGroupPrefix)$PackageName"
        ArsGroupOu      = $env.ArsGroupOu
        ArsProviderUrl  = $env.ArsProviderUrl
        ArsDescription  = "$($defaults.Naming.arsDescriptionPrefix)$PackageName"
    }
}
