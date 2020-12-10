$CompilerFlags = @(
    '/FS'
)
$env:CFLAGS = $CompilerFlags -join ' '
$env:CXXFLAGS = $CompilerFlags -join ' '

$LinkerFlags = @(
    '/LTCG'
    '/INCREMENTAL:NO'
    '/OPT:REF'
    '/DEBUG'
    '/PDBALTPATH:%_PDB%'
)
$env:LDFLAGS = $LinkerFlags -join ' '

$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio' Installer vswhere

$ToolchainId = 'vs_2019'
$VsInstallPrefix = (& $VsWhere -all -products * -version "[16,17)" -sort -property installationPath).Split([Environment]::NewLine)[0]
$VcVarsScript = Join-Path $VsInstallPrefix VC Auxiliary Build vcvarsall.bat

$ToolChainCMakeConfigOptions = @(
    "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$(if ($BuildType -eq 'release') { '' } else { 'Debug' })DLL"
)

function Invoke-ToolchainEnvCommand() {
    $VcEnvScript = Join-Path $TempDir "vcenv.cmd"

    if (-not (Test-Path $VcEnvScript)) {
        New-Item -Path $TempDir -ItemType Directory -ErrorAction Ignore | Out-Null
        # Building 32-bit QtWebEngine requires a x64->x86 cross-compiler
        Set-Content $VcEnvScript (@"
            @pushd .
            @call "${VcVarsScript}" $(if ($BuildArch -eq 'x86') { 'x64_x86' } else { $BuildArch }) || exit /b 1
            @popd
            @%* 2>&1
"@ -replace '(^|[\r\n])\s+', '$1')
    }

    Invoke-NativeCommand $VcEnvScript @args
}
