function Build-Zlib([string] $PrefixDir, [string] $DepsPrefixDir) {
    $Version = Get-CurrentFileVersion
    $Filename = "zlib-${Version}.tar.gz"
    $Url = "https://zlib.net/fossils/${Filename}"

    $SourceDir = Invoke-DownloadAndUnpack $Url $Filename
    $BuildDir = Join-Path $SourceDir .build

    # Remove debug postfix
    Edit-TextFile (Join-Path $SourceDir CMakeLists.txt) '^.*CMAKE_DEBUG_POSTFIX.*' ''
    # Fix files naming for debug builds (zlibd1.dll -> zlib1d.dll)
    Edit-TextFile (Join-Path $SourceDir CMakeLists.txt) 'SUFFIX "1.dll"' 'OUTPUT_NAME zlib1'

    Invoke-CMakeBuildAndInstall $SourceDir $BuildDir $PrefixDir $DepsPrefixDir
    Copy-Item -Path (Join-Path $BuildDir "zlib1${LibraryPostfix}.pdb") -Destination (Join-Path $PrefixDir bin)

    Remove-JunkFiles $PrefixDir @(
        "lib/zlibstatic${LibraryPostfix}.lib"
        'share/man/man3/zlib.3'
        'share/pkgconfig/zlib.pc'
    )
}
