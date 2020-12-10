function Build-Dbus([string] $PrefixDir, [string] $DepsPrefixDir) {
    $Version = Get-CurrentFileVersion
    $Filename = "dbus-${Version}.tar.gz"
    $Url = "https://dbus.freedesktop.org/releases/dbus/${Filename}"

    $SourceDir = Invoke-DownloadAndUnpack $Url $Filename
    $BuildDir = Join-Path $SourceDir .build

    # Use package (not find module) when searching for expat
    Edit-TextFile (Join-Path $SourceDir cmake CMakeLists.txt) 'find_package\(EXPAT\)' 'find_package(EXPAT CONFIG)'
    # Link to expat target
    Edit-TextFile (Join-Path $SourceDir cmake bus CMakeLists.txt) '\$\{EXPAT_INCLUDE_DIR\}' ''
    Edit-TextFile (Join-Path $SourceDir cmake bus CMakeLists.txt) '\$\{EXPAT_LIBRARIES\}' 'expat::expat'
    # Don't test if expat.h is there (it is)
    Edit-TextFile (Join-Path $SourceDir cmake ConfigureChecks.cmake) 'check_include_file\(expat\.h.*' 'set(HAVE_EXPAT_H TRUE)'
    # Remove "-3" (or whatever) revision suffix part from DLL name since Qt doesn't seem to support that and we don't really need it
    Edit-TextFile (Join-Path $SourceDir cmake modules MacrosAutotools.cmake) '^.*_LIBRARY_REVISION.*' ''

    $ConfigOptions = @(
        '-DDBUS_BUILD_TESTS=OFF'
        "-DDBUS_DISABLE_ASSERT=$(if ($BuildType -eq 'release') { 'ON' } else { 'OFF' }))"
    )

    Invoke-CMakeBuildAndInstall (Join-Path $SourceDir cmake) $BuildDir $PrefixDir $DepsPrefixDir $ConfigOptions
    Copy-Item -Path (Join-Path $BuildDir bin dbus-1${LibraryPostfix}.pdb) -Destination (Join-Path $PrefixDir bin)

    Remove-JunkFiles $PrefixDir @(
        'etc/dbus-1'
        'share/dbus-1'
        'var/lib/dbus'
    )
}
