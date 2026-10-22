param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$Root,

    [string]$SearchRoot = '/ISO'
)

$ErrorActionPreference = 'Stop'

$json = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8)
$cfg = $json | ConvertFrom-Json
$aliases = @($cfg.menu_alias)
if ($aliases.Count -eq 0) {
    throw "No menu_alias entries in $ConfigPath"
}

$rootFull = [IO.Path]::GetFullPath($Root)
$missing = New-Object System.Collections.Generic.List[string]
$aliasSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$badPaths = New-Object System.Collections.Generic.List[string]

foreach ($a in $aliases) {
    if (-not $a.image -or -not $a.alias) {
        $badPaths.Add('ENTRY_WITHOUT_IMAGE_OR_ALIAS')
        continue
    }

    $rel = $a.image.TrimStart('/') -replace '/', '\'
    $full = [IO.Path]::GetFullPath((Join-Path $rootFull $rel))
    $aliasSet.Add($full) | Out-Null

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $missing.Add("$($a.image)  ->  $full")
    }
}

$dupAliases = @($aliases | Group-Object alias | Where-Object Count -gt 1)
$dupImages = @($aliases | Group-Object image | Where-Object Count -gt 1)

Write-Output "ALIASES=$($aliases.Count)"
Write-Output "MISSING=$($missing.Count)"
Write-Output "DUPLICATE_ALIASES=$($dupAliases.Count)"
Write-Output "DUPLICATE_IMAGES=$($dupImages.Count)"
Write-Output "BAD_ENTRIES=$($badPaths.Count)"

if ($missing.Count -gt 0) {
    Write-Output '--- MISSING PATHS ---'
    $missing | ForEach-Object { Write-Output $_ }
}

if ($dupAliases.Count -gt 0) {
    Write-Output '--- DUPLICATE ALIASES ---'
    $dupAliases | ForEach-Object { Write-Output ("{0} x {1}" -f $_.Name, $_.Count) }
}

if ($dupImages.Count -gt 0) {
    Write-Output '--- DUPLICATE IMAGES ---'
    $dupImages | ForEach-Object { Write-Output ("{0} x {1}" -f $_.Name, $_.Count) }
}

$searchRel = $SearchRoot.TrimStart('/') -replace '/', '\'
$searchPath = Join-Path $rootFull $searchRel
if (Test-Path -LiteralPath $searchPath -PathType Container) {
    $found = @(
        Get-ChildItem -LiteralPath $searchPath -File -Recurse |
            Where-Object { $_.Extension -match '^\.(iso|img)$' }
    )
    $unalised = @($found | Where-Object { -not $aliasSet.Contains($_.FullName) })
    Write-Output "UNALIASED_IMAGES=$($unalised.Count)"
    if ($unalised.Count -gt 0) {
        Write-Output '--- UNALIASED IMAGES (warning) ---'
        $unalised | ForEach-Object { Write-Output $_.FullName }
    }
}
else {
    Write-Output "SEARCH_ROOT_MISSING=$searchPath"
}

if ($missing.Count -gt 0 -or $dupAliases.Count -gt 0 -or $dupImages.Count -gt 0 -or $badPaths.Count -gt 0) {
    exit 1
}
exit 0
