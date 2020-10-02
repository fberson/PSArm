[CmdletBinding()]
param(
    [Parameter()]
    [string]
    $PluginPath = $PSScriptRoot,

    [Parameter()]
    [string]
    $OutputPath = "$PSScriptRoot/out",

    [Parameter()]
    [string]
    $SpecRootPath = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'azure-api-rest-specs'),

    [switch]
    $WaitSputnikDebugger
)

function Get-ArmReadmes
{
    param(
        [Parameter(Mandatory)]
        [string]
        $SpecRootPath
    )

    Get-ChildItem -LiteralPath "$SpecRootPath/specification" |
        ForEach-Object { "$($_.FullName)/resource-manager/readme.azureresourceschema.md" } |
        Where-Object { Test-Path -LiteralPath $_ }
}

filter Get-AutorestConfigFromReadme
{
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $ReadmePath
    )

    $basePath = Split-Path -Path $ReadmePath -Parent

    $resourceName = Split-Path -Path (Split-Path -Path $basePath -Parent) -Leaf

    $markdown = Get-Content -Raw -LiteralPath $ReadmePath | ConvertFrom-Markdown
    $codeblocks = $markdown.Tokens | Where-Object { $_ -is [Markdig.Syntax.CodeBlock] }

    $tags = ($codeblocks[0].Lines.ToString() | ConvertFrom-Yaml).batch.tag
    $batches = @{}
    foreach ($block in $codeblocks)
    {
        if ($block.Arguments -match '\$\(tag\) == ''(.*)''')
        {
            $currTag = $Matches[1]
        }

        if (-not $currTag -or $tags -notcontains $currTag)
        {
            continue
        }

        $currBatch = $block.Lines.ToString() | ConvertFrom-Yaml
        $inputPath = $currBatch['input-file'] |
            ForEach-Object { if (-not [System.IO.Path]::IsPathRooted($_)) { Join-Path -Path $basePath -ChildPath $_ } else { $_ } }
        $currBatch['input-file'] = $inputPath
        $currBatch.Remove('output-folder')

        $batches[$currTag] = $currBatch
    }

    @{
        Resource = $resourceName
        Batches = $batches
    }
}

function New-AutorestLiterateConfig
{
    param(
        [Parameter(ValueFromPipeline)]
        [hashtable]
        $ResourceConfig,

        [Parameter(Mandatory)]
        [string]
        $PluginPath,

        [Parameter(Mandatory)]
        [string]
        $OutputPath,

        [switch]
        $NoFlattening
    )

    begin
    {
        $generalConfig = @{
            'use' = $PluginPath
            'output-folder' = $OutputPath
        }

        if (-not $NoFlattening)
        {
            $generalConfig['modelerfour'] = @{
                'lenient-model-deduplication' = $true
                'flatten-models' = $true
                'flatten-payloads' = $true
                'resolve-schema-name-collisions' = $true
            }
        }
    }


    process
    {
        $ResourceConfig.Batches.GetEnumerator() |
            ForEach-Object {
                [PSCustomObject]@{
                    ResourceName = $ResourceConfig.Resource
                    ApiVersion = $_.Key
                    YamlConfig = $generalConfig + $_.Value | ConvertTo-Yaml
                }
            }
    }
}

function Invoke-Autorest
{
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $YamlConfig,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ResourceName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ApiVersion,

        [switch]
        $WaitDebugger
    )

    process
    {
        Write-Host "Generating output for '$ResourceName' ($ApiVersion)"
        Write-Verbose "Running autorest with config:`n$YamlConfig"

        try
        {
            $configPath = Join-Path ([System.IO.Path]::GetTempPath()) "psarm_autorest_config.yaml"
            $null = New-Item -Path $configPath -Value $YamlConfig -Force

            $params = @(
                $configPath
                if ($VerbosePreference) { '--debug' }
                if ($WaitDebugger) { '--sputnik.debugger' }
            )
            autorest @params
        }
        finally
        {
            Remove-Item -LiteralPath $configPath -Force
        }
    }
}

if (-not (Test-Path $OutputPath))
{
    $null = New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop
}

if (-not (Test-Path $SpecRootPath))
{
    if (-not (Get-Command -Name git -ErrorAction Ignore))
    {
        throw "'git' not found. Please install 'git' to continue"
    }

    git clone 'https://github.com/Azure/azure-rest-api-specs.git' $SpecRootPath

    if ($LASTEXITCODE -ne 0)
    {
        throw "Clone of spec repo failed. See above for error details"
    }
}

$OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path

Get-ArmReadmes -SpecRootPath $SpecRootPath |
    Get-AutorestConfigFromReadme |
    New-AutorestLiterateConfig -PluginPath $PluginPath -OutputPath $OutputPath |
    Invoke-Autorest -WaitDebugger:$WaitSputnikDebugger