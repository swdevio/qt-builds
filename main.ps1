using namespace System.Collections.ObjectModel
using namespace System.Management.Automation
using namespace System.Net

param(
    [Parameter(Mandatory)]
    [ArgumentCompleter({ (Get-ChildItem (Join-Path (Split-Path -Path $PSCommandPath -Parent) toolchains) -File -Filter '*.ps1').BaseName })]
    [ValidateScript({ $_ -in ((Get-ChildItem (Join-Path (Split-Path -Path $PSCommandPath -Parent) toolchains) -File -Filter '*.ps1').BaseName) })]
    [string] $Toolchain,

    [Parameter(Mandatory)]
    [ValidateSet('x86', 'x64')]
    [string] $BuildArch,

    [Parameter(Mandatory)]
    [ValidateSet('release', 'debug')]
    [string] $BuildType
)

DynamicParam {
    Set-StrictMode -Version 3.0

    $PackageVersions = @{}

    Get-ChildItem (Join-Path (Split-Path -Path $PSCommandPath -Parent) packages) -File -Filter '*-*.ps1' | ForEach-Object {
        $PackageVersion = $_.BaseName.Split('-', 2)
        if (-not $PackageVersions.ContainsKey($PackageVersion[0])) {
            $PackageVersions[$PackageVersion[0]] = @()
        }
        $PackageVersions[$PackageVersion[0]] += $PackageVersion[1]
    }

    $Params = New-Object RuntimeDefinedParameterDictionary

    $PackageVersions.GetEnumerator() | ForEach-Object {
        $Name = "$([regex]::Replace($_.Key, '\b(\w)', { $args[0].Value.ToUpper() }))Version"
        $Values = @($_.Value | Sort-Object -Descending { [regex]::Replace($_, '\d+', { $args[0].Value.PadLeft(10, '0') }) })

        $ParameterAttribute = New-Object ParameterAttribute
        $ValidateSetAttribute = New-Object ValidateSetAttribute ($Values)

        $ParamAttributes = New-Object Collection[Attribute]
        $ParamAttributes.Add($ParameterAttribute)
        $ParamAttributes.Add($ValidateSetAttribute)

        $Param = New-Object RuntimeDefinedParameter ($Name, [string], $ParamAttributes)
        $Params.Add($Param.Name, $Param)

        # Set default value
        $PSBoundParameters[$Name] = $Values[0]
    }

    return $Params
}

Process {
    Set-StrictMode -Version 3.0

    $ErrorActionPreference = 'Stop'
    $PSDefaultParameterValues['*:ErrorAction'] = $ErrorActionPreference

    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        Set-Variable $_.Key $_.Value
    }

    $ScriptDir = Split-Path -Path $PSCommandPath -Parent

    $LibraryPostfix = if ($BuildType -eq 'release') { '' } else { 'd' }

    [ServicePointManager]::SecurityProtocol = [SecurityProtocolType]::Tls12

    . (Join-Path $ScriptDir functions.ps1)
    . (Join-Path $ScriptDir toolchains "${Toolchain}.ps1")

    $BuildId = "qt_${QtVersion}-${ToolchainId}-${BuildArch}-$($BuildType -replace '[aeiouy]', '')"

    $RootDir = Join-Path (Get-Item $ScriptDir).Root.Name Qt
    $PrefixDir = Join-Path $RootDir $BuildId
    $TempDir = Join-Path $RootDir ".${BuildId}"
    $CacheDir = Join-Path $RootDir .cache

    Invoke-Build Expat $ExpatVersion
    Invoke-Build Dbus $DbusVersion
    Invoke-Build Zlib $ZlibVersion
    Invoke-Build Openssl $OpensslVersion

    $QtBaseDepsArchivePath = Join-Path $RootDir (Get-QtModuleArchiveName 'qtbasedeps')
    Add-DirectoryToArchive $QtBaseDepsArchivePath $PrefixDir

    Invoke-Build Qt $QtVersion @({
        param([string] $ModuleName, [string] $StagedPrefixDir)

        $ArchivePath = Join-Path $RootDir (Get-QtModuleArchiveName $ModuleName)

        if ($ModuleName -eq 'qtbase') {
            # Merge in qtbase deps (deps archive itself is not meant to be distributed)
            Copy-Item $QtBaseDepsArchivePath $ArchivePath -Force
        }

        Add-DirectoryToArchive $ArchivePath $StagedPrefixDir
    })
}
