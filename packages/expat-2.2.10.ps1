function Build-Expat([string] $PrefixDir, [string] $DepsPrefixDir) {
    $Version = Get-CurrentFileVersion
    $Filename = "expat-${Version}.tar.bz2"
    $Url = "https://github.com/libexpat/libexpat/releases/download/R_$($Version.replace(".", "_"))/${Filename}"

    $SourceDir = Invoke-DownloadAndUnpack $Url $Filename
    $BuildDir = Join-Path $SourceDir .build

    # Remove any kind of postfix
    Edit-TextFile (Join-Path $SourceDir CMakeLists.txt) '^.*set\(\$\{postfix_var\}.*' ''
    # Remove version suffix from CMake package directory name
    Edit-TextFile (Join-Path $SourceDir CMakeLists.txt) '(cmake/expat)-\$\{PROJECT_VERSION\}' '$1'

    $ConfigOptions = @(
        '-DEXPAT_BUILD_EXAMPLES=OFF'
        '-DEXPAT_BUILD_TESTS=OFF'
        '-DEXPAT_BUILD_TOOLS=OFF'
    )

    Invoke-CMakeBuildAndInstall $SourceDir $BuildDir $PrefixDir $DepsPrefixDir $ConfigOptions
    Copy-Item -Path (Join-Path $BuildDir libexpat${LibraryPostfix}.pdb) -Destination (Join-Path $PrefixDir bin)

    Remove-JunkFiles $PrefixDir @(
        'share/doc/expat'
    )
}
