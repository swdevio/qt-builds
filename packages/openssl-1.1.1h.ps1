function Build-Openssl([string] $PrefixDir, [string] $DepsPrefixDir) {
    $Version = Get-CurrentFileVersion
    $Filename = "openssl-${Version}.tar.gz"
    $Url = "https://www.openssl.org/source/${Filename}"

    $SourceDir = Invoke-DownloadAndUnpack $Url $Filename
    $BuildDir = $SourceDir

    # Add debug postfix
    Edit-TextFile (Join-Path $SourceDir build.info) '(SHARED_NAME\[lib(crypto|ssl)\]=.*\})' "`$1${LibraryPostfix}"

    $ConfigName = if ($BuildArch -eq 'x86') { 'VC-WIN32' } else { 'VC-WIN64A' }
    $ConfigOptions = @(
        "--prefix=${PrefixDir}"
        "--${BuildType}"
        $ConfigName
        'shared'
        'no-comp'
        'no-dso'
        'no-engine'
        'no-hw'
        'no-stdio'
        'no-tests'
    )

    Push-Location -Path $BuildDir
    Invoke-ToolchainEnvCommand perl Configure @ConfigOptions
    Invoke-ToolchainEnvCommand jom install_dev
    Pop-Location

    foreach ($LibName in @('crypto'; 'ssl')) {
        Move-Item (Join-Path $PrefixDir lib "lib${LibName}.lib") (Join-Path $PrefixDir lib "lib${LibName}${LibraryPostfix}.lib") -Force
    }
}
