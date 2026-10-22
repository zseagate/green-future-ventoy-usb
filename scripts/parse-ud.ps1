param(
    [Parameter(Mandatory = $true)]
    [int]$DiskNumber,

    [int64]$UdSize = 0,
    [int64]$TableOffset = 0x8800,
    [int]$MaxTable = 0x20000
)

$ErrorActionPreference = 'Stop'

$diskPath = '\\.\PhysicalDrive' + $DiskNumber
if ($UdSize -le 0) {
    $disk = Get-Disk -Number $DiskNumber
    $UdSize = [int64]$disk.Size
}

$fs = New-Object System.IO.FileStream(
    $diskPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite
)

try {
    $fs.Seek($TableOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
    $buf = New-Object byte[] $MaxTable
    $read = $fs.Read($buf, 0, $MaxTable)
}
finally {
    $fs.Dispose()
}

$p = 0
$entries = @()
while (($p + 14) -lt $read) {
    $flags = [BitConverter]::ToUInt16($buf, $p)
    $sector = [BitConverter]::ToUInt32($buf, $p + 2)
    $size = [BitConverter]::ToUInt32($buf, $p + 6)
    $mtime = [BitConverter]::ToUInt32($buf, $p + 10)

    $nameStart = $p + 14
    $nul = [Array]::IndexOf($buf, [byte]0, $nameStart)
    if ($nul -lt 0) { break }

    $nameLen = $nul - $nameStart
    if ($nameLen -le 0) { break }

    $name = [Text.Encoding]::UTF8.GetString($buf, $nameStart, $nameLen)
    $offset = [int64]$sector * 512
    $valid = ($size -gt 0) -and (($offset + $size) -le $UdSize)

    $entries += [pscustomobject]@{
        Index  = $entries.Count
        Flags  = ('0x{0:X4}' -f $flags)
        Sector = $sector
        Offset = $offset
        Size   = [int64]$size
        MTime  = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$mtime)).ToString('yyyy-MM-dd HH:mm:ss')
        Name   = $name
        Valid  = $valid
    }

    $p = $nul + 1
}

"TABLE_ENTRIES=$($entries.Count)"
"VALID_ENTRIES=$(($entries | Where-Object Valid).Count)"
$entries | Format-Table -AutoSize
