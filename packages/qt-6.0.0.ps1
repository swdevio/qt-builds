function Build-Qt([string] $PrefixDir, [string] $DepsPrefixDir, [scriptblock] $ModuleCallback) {
    # In order of appearance in https://raw.githubusercontent.com/qt/qt5/dev/.gitmodules
    $ModuleNames = @(
        'qtbase'
        'qtsvg'
        'qtdeclarative'
        # 'qtactiveqt' (not there yet)
        'qttools'
        # 'qtxmlpatterns' (not there yet)
        'qttranslations'
        # 'qtimageformats' (not there yet)
        # 'qtgraphicaleffects' (not there yet)
        # 'qtquickcontrols' (not there yet)
        # 'qtwinextras' (not there yet)
        # 'qtwebsockets' (not there yet)
        # 'qtwebchannel' (not there yet)
        # 'qtwebengine' (not there yet)
        'qtquickcontrols2'
        # 'qtcharts' (not there yet)
        'qtquicktimeline'
        'qt5compat'
    )

    foreach ($ModuleName in $ModuleNames) {
        Build-QtModule $PrefixDir $DepsPrefixDir $ModuleName $ModuleCallback
    }
}

function Build-QtModule([string] $PrefixDir, [string] $DepsPrefixDir, [string] $ModuleName, [scriptblock] $ModuleCallback) {
    $Version = Get-CurrentFileVersion
    $Filename = "${ModuleName}-everywhere-src-${Version}.zip" # tar.xz has some names truncated (e.g. .../double-conversion.h -> .../double-conv)
    $Url = "http://download.qt.io/archive/qt/$($Version -replace '\.\d+$', '')/${Version}/submodules/${Filename}"

    $SourceDir = Invoke-DownloadAndUnpack $Url $Filename
    $BuildDir = Join-Path $SourceDir .build

    $StageDir = Join-Path $SourceDir .stage (Split-Path $PrefixDir -Leaf)

    $ConfigOptions = @()
    $JunkFiles = @()

    switch ($ModuleName) {
        'qtbase' {
            $ConfigOptions += @(
                '-cmake'
                '-prefix'; $StageDir
                "-${BuildType}"
                '-force-debug-info'
                '-opengl'; 'desktop'
                '-dbus-linked'
                '-ssl'
                '-openssl-linked'
                '-system-zlib'
                '-qt-pcre'
                '-qt-libpng'
                '-qt-libjpeg'
                '-qt-harfbuzz'
                '-nomake'; 'examples'
                '-nomake'; 'tests'
                "-DCMAKE_PREFIX_PATH=${DepsPrefixDir}"
            )

            $JunkFiles += @(
                'doc'
            )
        }
        'qttools' {
            $ConfigOptions += @(
                '-no-feature-assistant'
                # '-no-feature-qdoc' (not there yet)
            )
        }
        'qtwebengine' {
            # (not there yet)
        }
    }

    $OldPath = $env:PATH
    $env:PATH = @(
        (Join-Path $PrefixDir bin)
        (Join-Path $DepsPrefixDir bin)
        (Join-Path $BuildDir qtbase lib)
        $env:PATH
    ) -join [System.IO.Path]::PathSeparator

    New-Item -Path $BuildDir -ItemType Directory -ErrorAction Ignore | Out-Null
    Push-Location -Path $BuildDir

    if ($ModuleName -eq 'qtbase') {
        Invoke-ToolchainEnvCommand (Join-Path $SourceDir configure) @ConfigOptions
    } else {
        Invoke-ToolchainEnvCommand qt-configure-module $SourceDir `
            @ConfigOptions `
            '--' `
            "-DCMAKE_INSTALL_PREFIX=${StageDir}" `
            "-DCMAKE_PREFIX_PATH=${DepsPrefixDir}"
    }

    Invoke-ToolchainEnvCommand cmake --build .
    Invoke-ToolchainEnvCommand cmake --install .

    Pop-Location

    $env:PATH = $OldPath

    Remove-JunkFiles $StageDir $JunkFiles

    if ($ModuleName -eq 'qtbase') {
        # Fixup install prefix as there's no real staging support now
        Edit-TextFile (Join-Path $StageDir lib cmake Qt6BuildInternals QtBuildInternalsExtra.cmake) '(set\(CMAKE_INSTALL_PREFIX ").*(" CACHE)' "`$1`${QT_BUILD_INTERNALS_RELOCATABLE_INSTALL_PREFIX}`$2"
        Edit-TextFile (Join-Path $StageDir bin qt-internal-configure-tests.bat) '^.*/(qt-cmake.bat)' '"%~dp0$1"'
    }

    if ($ModuleCallback) {
        Invoke-Command -ScriptBlock $ModuleCallback -ArgumentList @(
            $ModuleName
            $StageDir
        )
    }

    Copy-Item $StageDir (Split-Path $PrefixDir -Parent) -Recurse -Force
}
