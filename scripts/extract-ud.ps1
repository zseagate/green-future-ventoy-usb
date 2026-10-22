param(
    [Parameter(Mandatory = $true)]
    [int]$DiskNumber,

    [Parameter(Mandatory = $true)]
    [string]$OutRoot,

    [string]$Manifest = '',
    [int64]$UdSize = 0,
    [int64]$TableOffset = 0x8800,
    [int]$MaxTable = 0x20000,
    [int[]]$SkipIndexes = @(),
    [string]$ExpectedSerial = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($UdSize -le 0) {
    $disk = Get-Disk -Number $DiskNumber
    $UdSize = [int64]$disk.Size
}

if ($ExpectedSerial) {
    $disk = Get-Disk -Number $DiskNumber
    if ($disk.SerialNumber -ne $ExpectedSerial) {
        throw "Disk $DiskNumber serial mismatch: expected '$ExpectedSerial', got '$($disk.SerialNumber)'"
    }
}

if (-not $Manifest) {
    $Manifest = Join-Path $OutRoot 'UD_MANIFEST.csv'
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$manifestParent = Split-Path -Parent $Manifest
if ($manifestParent) {
    New-Item -ItemType Directory -Force -Path $manifestParent | Out-Null
}

$diskPath = '\\.\PhysicalDrive' + $DiskNumber
Write-Output "SOURCE DISK: $diskPath"
Write-Output "UD SIZE: $UdSize bytes"
Write-Output "TABLE OFFSET: 0x$($TableOffset.ToString('X'))"

$fs = New-Object System.IO.FileStream(
    $diskPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite
)

try {
    $fs.Seek($TableOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
    $table = New-Object byte[] $MaxTable
    $tableRead = $fs.Read($table, 0, $MaxTable)
}
finally {
    $fs.Dispose()
}

$entries = @()
$p = 0
while (($p + 14) -lt $tableRead) {
    $flags = [BitConverter]::ToUInt16($table, $p)
    $sector = [BitConverter]::ToUInt32($table, $p + 2)
    $size = [BitConverter]::ToUInt32($table, $p + 6)
    $mtime = [BitConverter]::ToUInt32($table, $p + 10)

    $nameStart = $p + 14
    $nul = [Array]::IndexOf($table, [byte]0, $nameStart)
    if ($nul -lt 0) { break }

    $nameLen = $nul - $nameStart
    if ($nameLen -le 0) { break }

    $entries += [pscustomobject]@{
        Index  = $entries.Count
        Flags  = $flags
        Sector = $sector
        Offset = [int64]$sector * 512
        Size   = [int64]$size
        MTime  = $mtime
        Name   = [Text.Encoding]::UTF8.GetString($table, $nameStart, $nameLen)
    }

    $p = $nul + 1
}

Write-Output "TABLE_ENTRIES=$($entries.Count)"

$results = New-Object System.Collections.Generic.List[object]
$buffer = New-Object byte[] (4 * 1024 * 1024 + 512)
$rootFull = [IO.Path]::GetFullPath($OutRoot)

foreach ($e in $entries) {
    $status = 'OK'
    $name = $e.Name
    $rel = ''
    $hash = ''
    $isoValid = $false
    $mbrValid = $false

    if ($SkipIndexes -contains $e.Index) {
        $status = 'SKIP_CORRUPT_INDEX'
    }
    elseif ([string]::IsNullOrWhiteSpace($name)) {
        $status = 'SKIP_EMPTY_NAME'
    }
    elseif ($name.Contains('?')) {
        $status = 'SKIP_QUESTION_MARK'
    }
    elseif (($e.Offset + $e.Size) -gt $UdSize -or $e.Size -le 0) {
        $status = 'SKIP_BAD_RANGE'
    }
    else {
        $name = $name.TrimStart('/')
        if ($name -match '(^|/)\.\.(/|$)' -or $name -match '^[A-Za-z]:') {
            $status = 'SKIP_BAD_NAME'
        }
        else {
            $rel = $name -replace '/', '\'
            $outPath = Join-Path $OutRoot $rel
            $outFull = [IO.Path]::GetFullPath($outPath)
            if (-not $outFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                $status = 'SKIP_OUTSIDE_ROOT'
            }
            elseif ((Test-Path -LiteralPath $outFull) -and -not $Force) {
                $status = 'SKIP_EXISTS'
            }
        }
    }

    if ($status -ne 'OK') {
        $results.Add([pscustomobject]@{
            Index = $e.Index; Name = $e.Name; Size = $e.Size; Offset = $e.Offset;
            Status = $status; Sha256 = ''; IsoValid = ''; MbrValid = ''
        })
        Write-Output ("[{0}] {1} ({2} bytes) -> {3}" -f $e.Index, $e.Name, $e.Size, $status)
        continue
    }

    $outPath = [IO.Path]::GetFullPath((Join-Path $OutRoot $rel))
    $parent = Split-Path -Parent $outPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $out = [System.IO.File]::Open($outPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $src = New-Object System.IO.FileStream(
        $diskPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    try {
        $remaining = $e.Size
        $pos = 0
        while ($remaining -gt 0) {
            $toRead = [int][Math]::Min([int64](4 * 1024 * 1024), $remaining)
            $aligned = [int]([Math]::Ceiling($toRead / 512.0) * 512)

            $src.Seek($e.Offset + $pos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $got = 0
            while ($got -lt $aligned) {
                $n = $src.Read($buffer, $got, $aligned - $got)
                if ($n -le 0) { break }
                $got += $n
            }
            if ($got -lt $toRead) {
                throw "Short read at offset $($e.Offset + $pos): wanted $toRead, got $got"
            }

            $out.Write($buffer, 0, $toRead)
            $sha.TransformBlock($buffer, 0, $toRead, $null, 0) | Out-Null
            $pos += $toRead
            $remaining -= $toRead
        }

        $sha.TransformFinalBlock($buffer, 0, 0) | Out-Null
        $hash = ($sha.Hash | ForEach-Object { $_.ToString('X2') }) -join ''
    }
    finally {
        $src.Dispose()
        $out.Dispose()
        $sha.Dispose()
    }

    # ISO9660 PVD: sector 16 at 32768, bytes 1..5 are "CD001".
    if ($e.Size -gt 32773 -and $rel -match '\.iso$') {
        $tmp = New-Object System.IO.FileStream($outPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $tmp.Seek(32768, [System.IO.SeekOrigin]::Begin) | Out-Null
            $sig = New-Object byte[] 6
            $tmp.Read($sig, 0, 6) | Out-Null
            $isoValid = ([Text.Encoding]::ASCII.GetString($sig, 1, 5) -eq 'CD001')
        }
        finally { $tmp.Dispose() }
    }

    $tmp = New-Object System.IO.FileStream($outPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($tmp.Length -ge 512) {
            $mbr = New-Object byte[] 512
            $tmp.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
            $tmp.Read($mbr, 0, 512) | Out-Null
            $mbrValid = ($mbr[510] -eq 0x55 -and $mbr[511] -eq 0xAA)
        }
    }
    finally { $tmp.Dispose() }

    $results.Add([pscustomobject]@{
        Index = $e.Index; Name = $rel; Size = $e.Size; Offset = $e.Offset;
        Status = 'OK'; Sha256 = $hash; IsoValid = $isoValid; MbrValid = $mbrValid
    })
    Write-Output ("[{0}] {1} ({2} bytes) -> OK" -f $e.Index, $rel, $e.Size)
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Manifest
$ok = @($results | Where-Object Status -eq 'OK')
$bytes = ($ok | Measure-Object Size -Sum).Sum
Write-Output "MANIFEST: $Manifest"
Write-Output ("EXTRACTED: {0} files, {1} bytes" -f $ok.Count, $bytes)
