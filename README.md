## Qt Builds

Since Qt 5.15, no prebuilt Qt binaries are provided for open-source version, or at least not for free.
This repository contains scripts one could use to build their own binaries, and releases with pre-built binaries for those who doesn't want to waste their time.
Only Windows builds (x86 and x64, release and debug, shared) are currently supported with no immediate plans for other platforms and build types on my side, but PRs are surely welcome.

Provided Qt modules (subject to their presence in a particular Qt version):
* qtactiveqt
* qtbase (sql plugins: odbc, sqlite)
* qtcharts
* qtdeclarative
* qtgraphicaleffects
* qtimageformats
* qtquickcontrols
* qtquickcontrols2
* qtquicktimeline
* qtsvg
* qttools (without assistant and qdoc)
* qttranslations
* qtwebchannel
* qtwebengine (all exposed configuration features disabled)
* qtwebsockets
* qtwinextras
* qtxmlpatterns

Provided Qt dependencies:
* zlib
* dbus (+expat)
* openssl

Supported compilers:
* Visual Studio 2019 (any edition)
