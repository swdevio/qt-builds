function Invoke-NativeCommand() {
    $Command = $Args[0]
    $CommandArgs = @()
    if ($Args.Count -gt 1) {
        $CommandArgs = $Args[1..($Args.Count - 1)]
    }

    Write-Debug "Executing native command: $Command $CommandArgs"
    & $Command $CommandArgs
    $Result = $LastExitCode

    if ($Result -ne 0) {
        throw "$Command $CommandArgs exited with code $Result."
    }
}

function Invoke-Download([string] $Url, [string] $OutFile) {
    if (-not (Test-Path $OutFile)) {
        Write-Information "Downloading ${Url} to ${OutFile}" -InformationAction Continue
        $OldProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile
        $ProgressPreference = $OldProgressPreference
    }
}

function Invoke-DownloadAndUnpack([string] $Url, [string] $Filename) {
    $ArchivePath = Join-Path $CacheDir $Filename
    $SubArchiveType = $null

    if ($ArchivePath -match '^(.+)(\.tar\.(gz|bz2|xz))$') {
        $ResultDir = Join-Path $TempDir (Split-Path -Path $Matches[1] -Leaf)
        $SubArchiveType = 'tar'
    } elseif ($ArchivePath -match '^(.+)(\.(7z|zip))$') {
        $ResultDir = Join-Path $TempDir (Split-Path -Path $Matches[1] -Leaf)
    } else {
        throw "Archive type is not supported: ${ArchivePath}"
    }

    New-Item -Path $CacheDir -ItemType Directory -ErrorAction Ignore | Out-Null
    Invoke-Download $Url $ArchivePath

    New-Item -Path $TempDir -ItemType Directory -ErrorAction Ignore | Out-Null
    Push-Location -Path $TempDir

    Write-Information "Unpacking archive ${ArchivePath} to ${TempDir}" -InformationAction Continue

    if ($SubArchiveType) {
        Invoke-NativeCommand cmd.exe /c "7z x -so -y `"${ArchivePath}`" | 7z x -aoa -si -t${SubArchiveType} -y" | Out-Host
    } else {
        Invoke-NativeCommand 7z x -y $ArchivePath | Out-Host
    }

    Pop-Location

    return $ResultDir
}

function Add-DirectoryToArchive([string] $ArchivePath, [string] $DirPath) {
    Write-Information "Adding to archive ${ArchivePath} from ${DirPath}" -InformationAction Continue
    Invoke-NativeCommand cmake -E chdir (Split-Path $DirPath -Parent) 7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -y $ArchivePath (Split-Path $DirPath -Leaf)
}

function Edit-TextFile([string] $PatchedFile, [string] $MatchPattern, [string] $ReplacementString) {
    (Get-Content $PatchedFile) -replace $MatchPattern, $ReplacementString | Out-File "${PatchedFile}_new" -Encoding ascii
    Move-Item -Path "${PatchedFile}_new" -Destination $PatchedFile -Force
}

function Invoke-CMakeBuildAndInstall([string] $SourceDir, [string] $BuildDir, [string] $PrefixDir, [string] $DepsPrefixDir, [string[]] $ConfigOptions = @()) {
    $ImplicitConfigOptions = @(
        "-DCMAKE_BUILD_TYPE=$(if ($BuildType -eq 'release') { 'RelWithDebInfo' } else { 'Debug' })"
        "-DCMAKE_DEBUG_POSTFIX=${LibraryPostfix}"
        "-DCMAKE_RELWITHDEBINFO_POSTFIX=${LibraryPostfix}"
        "-DCMAKE_INSTALL_PREFIX=${PrefixDir}"
        "-DCMAKE_PREFIX_PATH=${DepsPrefixDir}"
        "-DBUILD_SHARED_LIBS=ON"
    )
    Invoke-ToolchainEnvCommand cmake -S $SourceDir -B $BuildDir -G Ninja @ImplicitConfigOptions @ToolChainCMakeConfigOptions @ConfigOptions
    Invoke-ToolchainEnvCommand cmake --build $BuildDir
    Invoke-ToolchainEnvCommand cmake --build $BuildDir --target install
}

function Invoke-Build([string] $Name, [string] $Version, $MoreArguments = @()) {
    . (Join-Path $ScriptDir packages "$($Name.ToLower())-${Version}.ps1")

    $Builder = (Get-Command "Build-${Name}" -CommandType Function).ScriptBlock

    $TempPrefixDir = $PrefixDir # Join-Path $TempDir "${Name}-Prefix"
    $BuilderArguments = @($TempPrefixDir, $PrefixDir) + $MoreArguments
    Write-Information "Running build for ${Name}" -InformationAction Continue
    Invoke-Command -ScriptBlock $Builder -ArgumentList $BuilderArguments
}

function Get-QtModuleArchiveName([string] $ModuleName) {
    return "$($BuildId -replace '^qt_', "${ModuleName}_").7z"
}

function Get-CurrentFileVersion() {
    (Split-Path $MyInvocation.ScriptName -LeafBase).Split('-', 2)[1]
}

function Remove-JunkFiles([string] $BaseDir, [string[]] $SubPaths) {
    foreach ($SubPath in $SubPaths) {
        while ($true) {
            $JunkPath = Join-Path $BaseDir $SubPath
            Write-Debug "Removing junk: ${JunkPath}"
            Remove-Item $JunkPath -Recurse -Force
            $SubPath = Split-Path $SubPath -Parent
            if ($SubPath -eq '') {
                break
            }
            if (Get-ChildItem (Join-Path $BaseDir $SubPath)) {
                break
            }
        }
    }
}
