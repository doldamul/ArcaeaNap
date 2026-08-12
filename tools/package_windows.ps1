$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$originalLocation = Get-Location
$archive = $null

try {
    Set-Location -LiteralPath $projectRoot
    $python = (Get-Command python -ErrorAction Stop).Source

    $version = & $python -c @'
import re

from utils.app_build_info import APP_VERSION

if (
    not isinstance(APP_VERSION, str)
    or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", APP_VERSION)
    or ".." in APP_VERSION
):
    raise RuntimeError("APP_VERSION must be a filename-safe single-line version")
print(APP_VERSION)
'@
    if ($LASTEXITCODE -ne 0) { throw "Could not read APP_VERSION." }
    $version = [string]$version
    if (
        [string]::IsNullOrWhiteSpace($version) -or
        $version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        $version.Contains("..") -or
        $version.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        [System.IO.Path]::IsPathRooted($version) -or
        $version -match '^[A-Za-z]:'
    ) {
        throw "APP_VERSION must be a filename-safe single-line version."
    }

    $appDirectory = & $python -c @'
from pathlib import Path
from tools.build_postprocess import find_windows_build_root, verify_windows_artifact

root = find_windows_build_root(Path.cwd())
verify_windows_artifact(root)
print(root.resolve())
'@
    if ($LASTEXITCODE -ne 0) { throw "Windows artifact validation failed." }
    $appDirectory = ([string]$appDirectory).Trim()
    if (-not (Test-Path -LiteralPath $appDirectory -PathType Container)) {
        throw "Verified Windows artifact directory does not exist: $appDirectory"
    }

    $buildDirectory = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "build"))
    $expectedArchiveName = "ArcaeaNap-$version-win64.zip"
    $expectedZipPath = [System.IO.Path]::GetFullPath((Join-Path $buildDirectory $expectedArchiveName))
    $archiveParent = [System.IO.Path]::GetDirectoryName($expectedZipPath)
    $archiveName = [System.IO.Path]::GetFileName($expectedZipPath)
    if (
        -not [string]::Equals($archiveParent, $buildDirectory, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($archiveName, $expectedArchiveName, [System.StringComparison]::Ordinal)
    ) {
        throw "Refusing to write an unexpected archive path: $expectedZipPath"
    }

    if (Test-Path -LiteralPath $expectedZipPath) {
        Remove-Item -LiteralPath $expectedZipPath -Force
    }
    Compress-Archive -LiteralPath $appDirectory -DestinationPath $expectedZipPath -CompressionLevel Optimal

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($expectedZipPath)
    $required = @(
        "ArcaeaNap/ArcaeaNap.exe",
        "ArcaeaNap/lib/native/appwindow_titlebar_bridge.dll",
        "ArcaeaNap/lib/native/Microsoft.WindowsAppRuntime.Bootstrap.dll",
        "ArcaeaNap/resources/licenses/windows-app-sdk.txt",
        "ArcaeaNap/resources/licenses/cppwinrt-mit.txt"
    )
    $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace("\\", "/") })
    $missing = @($required | Where-Object { $names -notcontains $_ })
    $invalidRoots = @($names | Where-Object { -not $_.StartsWith("ArcaeaNap/", [System.StringComparison]::Ordinal) })
    $forbidden = @()
    foreach ($name in $names) {
        $relative = $name.Substring([Math]::Min("ArcaeaNap/".Length, $name.Length)).ToLowerInvariant()
        $parts = $relative.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)
        $extension = [System.IO.Path]::GetExtension($relative).ToLowerInvariant()
        $isForbidden = $extension -in @(".pdb", ".ilk", ".exp", ".lib") -or
            $relative -eq "client_secret.json" -or
            $relative -eq "native/cmakelists.txt" -or
            $relative -eq "native/generated" -or $relative.StartsWith("native/generated/") -or
            $relative -eq "native/third_party" -or $relative.StartsWith("native/third_party/") -or
            $parts -contains ".local-browsers"
        if ($isForbidden) { $forbidden += $name }
    }
    if ($missing.Count -gt 0 -or $invalidRoots.Count -gt 0 -or $forbidden.Count -gt 0) {
        $failures = @()
        if ($missing.Count -gt 0) { $failures += "missing required entries: $($missing -join ', ')" }
        if ($invalidRoots.Count -gt 0) { $failures += "entries outside ArcaeaNap/: $($invalidRoots -join ', ')" }
        if ($forbidden.Count -gt 0) { $failures += "forbidden entries: $($forbidden -join ', ')" }
        throw "Windows ZIP validation failed: $($failures -join '; ')"
    }

    Write-Output "[package] Windows ZIP ready: $expectedZipPath"
}
finally {
    if ($null -ne $archive) { $archive.Dispose() }
    Set-Location -LiteralPath $originalLocation
}
