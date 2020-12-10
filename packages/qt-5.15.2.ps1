function Build-Qt([string] $PrefixDir, [string] $DepsPrefixDir, [scriptblock] $ModuleCallback) {
    # In order of appearance in https://raw.githubusercontent.com/qt/qt5/dev/.gitmodules
    $ModuleNames = @(
        'qtbase'
        'qtsvg'
        'qtdeclarative'
        'qtactiveqt'
        'qttools'
        'qtxmlpatterns'
        'qttranslations'
        'qtimageformats'
        'qtgraphicaleffects'
        'qtquickcontrols'
        'qtwinextras'
        'qtwebsockets'
        'qtwebchannel'
        'qtwebengine'
        'qtquickcontrols2'
        'qtcharts'
        'qtquicktimeline'
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

    $StageDir = Join-Path $SourceDir .stage
    $StagedPrefixDir = Join-Path $StageDir (Split-Path $PrefixDir -NoQualifier)

    $ConfigOptions = @()
    $JunkFiles = @()

    switch ($ModuleName) {
        'qtbase' {
            # Adjust library names
            Edit-TextFile (Join-Path $SourceDir configure.json) '"-lzlib"' "`"-lzlib1${LibraryPostfix}`""
            Edit-TextFile (Join-Path $SourceDir configure.json) '"-ldbus-1d?"' "`"-ldbus-1${LibraryPostfix}`""

            if ($env:LDFLAGS) {
                # Patch to add our linker flags, mainly /PDBALTPATH
                Edit-TextFile (Join-Path $SourceDir mkspecs win32-msvc qmake.conf) '(^QMAKE_CXXFLAGS\b.*)' "`$1`nQMAKE_LFLAGS += ${env:LDFLAGS}"
            }

            $ConfigOptions += @(
                '-platform'; 'win32-msvc'
                '-mp'
                # '-ltcg' # error C1002 on VS 2019 16.5.4
                '-opensource'
                '-confirm-license'
                '-prefix'; $PrefixDir
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
                '-no-freetype'
                # '-no-feature-sql'
                '-nomake'; 'examples'
                '-nomake'; 'tests'
                '-I'; (Join-Path $DepsPrefixDir include)
                '-I'; (Join-Path $DepsPrefixDir include dbus-1.0)
                '-I'; (Join-Path $DepsPrefixDir lib dbus-1.0 include)
                '-L'; (Join-Path $DepsPrefixDir lib)
                "OPENSSL_LIBS=-llibcrypto${LibraryPostfix} -llibssl${LibraryPostfix}"
            )

            $JunkFiles += @(
                'doc'
            )
        }
        'qttools' {
            $ConfigOptions += @(
                '-no-feature-assistant'
                '-no-feature-qdoc'
            )
        }
        'qtwebengine' {
            $ChromiumThirdPartyDir = Join-Path $SourceDir src 3rdparty chromium third_party

            # Support winflexbison binaries naming
            Edit-TextFile (Join-Path $SourceDir configure.pri) '"((bison|flex)[$][$]EXE_SUFFIX)"' '"win_$1"'
            # Disable warnings which lead to errors with vs-2019
            Edit-TextFile (Join-Path $ChromiumThirdPartyDir angle BUILD.gn) '/we4244' '/wd4244'
            # https://github.com/google/perfetto/commit/c81e804f8d37823aac9cf9d6d4ca92363284bf3b
            Edit-TextFile (Join-Path $ChromiumThirdPartyDir perfetto include perfetto ext base circular_queue.h) '= const (T[*&];)' '= $1'
            Edit-TextFile (Join-Path $ChromiumThirdPartyDir perfetto src trace_processor timestamped_trace_piece.h) '^\s*~(TimestampedTracePiece)' "`$1(const `$1&) = delete; `$1& operator=(const `$1&) = delete; ~`$1"
            # STL bug (VS 2019 / 16.8.2 / 14.28.29333)? `_Insertion_sort_unchecked` has 1st argument iterator argument marked as const, then tries to dereference it (getting a const& in return) and assign a new value
            Edit-TextFile (Join-Path $ChromiumThirdPartyDir perfetto include perfetto ext base circular_queue.h) 'const T& operator[*].*' 'T& operator*() const { return *(const_cast<Iterator&>(*this).operator->()); }'
            # error C2398: Element '1': conversion from 'double' to 'float' requires a narrowing conversion
            Edit-TextFile (Join-Path $ChromiumThirdPartyDir blink renderer platform graphics lab_color_space.h) '(auto invf = \[\]\(float x\)) \{' '$1 -> float {'

            $ConfigOptions += @(
                '-no-feature-webengine-geolocation'
                '-no-feature-webengine-kerberos'
                '-no-feature-webengine-pepper-plugins'
                '-no-feature-webengine-printing-and-pdf'
                '-no-feature-webengine-proprietary-codecs'
                '-no-feature-webengine-sanitizer'
                '-no-feature-webengine-spellchecker'
                '-no-feature-webengine-testsupport'
                '-no-feature-webengine-ui-delegates'
                '-no-feature-webengine-v8-snapshot-support'
                '-no-feature-webengine-webchannel'
                '-no-feature-webengine-webrtc'
            )
        }
    }

    $OldMake = $env:MAKE
    $env:MAKE = 'jom'
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
        Invoke-ToolchainEnvCommand qmake $SourceDir `
            "CONFIG+=${BuildType}" `
            "CONFIG-=$(if ($BuildType -eq 'release') { 'debug' } else { 'release' })" `
            '--' `
            @ConfigOptions
    }

    Invoke-ToolchainEnvCommand $env:MAKE
    Invoke-ToolchainEnvCommand $env:MAKE install "INSTALL_ROOT=$(Split-Path $StageDir -NoQualifier)"

    Pop-Location

    $env:PATH = $OldPath
    $env:MAKE = $OldMake

    Remove-JunkFiles $StagedPrefixDir $JunkFiles

    if ($ModuleCallback) {
        Invoke-Command -ScriptBlock $ModuleCallback -ArgumentList @(
            $ModuleName
            $StagedPrefixDir
        )
    }

    Copy-Item $StagedPrefixDir (Split-Path $PrefixDir -Parent) -Recurse -Force
}

#    Invoke-ToolchainEnvCommand $env:MAKE install
#
#    Remove-JunkFiles $PrefixDir $JunkFiles
#
#    if ($ModuleCallback) {
#        if ($ModuleName -eq 'qtbase') {
#            # Stage will include all qtbase (built first) dependencies as well
#            $StagedPrefixDir = $PrefixDir
#        } else {
#            $StageDir = Join-Path $SourceDir .stage
#            Invoke-ToolchainEnvCommand $env:MAKE install "INSTALL_ROOT=$(Split-Path $StageDir -NoQualifier)"
#            $StagedPrefixDir = Join-Path $StageDir (Split-Path $PrefixDir -NoQualifier)
#        }
#
#        Invoke-Command -ScriptBlock $ModuleCallback -ArgumentList @(
#            $ModuleName
#            $StagedPrefixDir
#        )
#    }
