param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$Recurse,

    [string]$SevenZip = ''
)

$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $files = @(Get-Item -LiteralPath $Path)
}
else {
    $files = @(
        Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse |
            Where-Object { $_.Extension -match '^\.(iso|img)$' }
    )
}

if ($files.Count -eq 0) {
    Write-Output 'No .iso/.img files found.'
    exit 0
}

$rows = foreach ($file in $files) {
    $iso9660 = $false
    $mbr = $false
    $efiX64 = $null
    $efiIa32 = $null
    $isolinux = $null
    $efiImg = $null

    $fs = New-Object System.IO.FileStream(
        $file.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        if ($file.Length -ge 32774 -and $file.Extension -match '^\.iso$') {
            $fs.Seek(32768, [System.IO.SeekOrigin]::Begin) | Out-Null
            $sig = New-Object byte[] 6
            $fs.Read($sig, 0, 6) | Out-Null
            $iso9660 = ([Text.Encoding]::ASCII.GetString($sig, 1, 5) -eq 'CD001')
        }

        if ($file.Length -ge 512) {
            $mbrBytes = New-Object byte[] 512
            $fs.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
            $fs.Read($mbrBytes, 0, 512) | Out-Null
            $mbr = ($mbrBytes[510] -eq 0x55 -and $mbrBytes[511] -eq 0xAA)
        }
    }
    finally {
        $fs.Dispose()
    }

    if ($SevenZip -and (Test-Path -LiteralPath $SevenZip)) {
        $listing = (& $SevenZip l $file.FullName 2>&1 | Out-String)
        $efiX64 = [bool]($listing -match 'EFI\\boot\\bootx64\.efi')
        $efiIa32 = [bool]($listing -match 'EFI\\boot\\bootia32\.efi')
        $isolinux = [bool]($listing -match 'isolinux\\isolinux\.bin')
        $efiImg = [bool]($listing -match 'boot\\grub\\efi\.img')
    }

    [pscustomobject]@{
        Name       = $file.Name
        SizeMB     = [math]::Round($file.Length / 1MB, 2)
        ISO9660    = $iso9660
        MBR55AA    = $mbr
        EFI_x64    = $efiX64
        EFI_ia32   = $efiIa32
        Isolinux   = $isolinux
        EfiImg     = $efiImg
        Path       = $file.FullName
    }
}

$rows | Format-Table Name, SizeMB, ISO9660, MBR55AA, EFI_x64, EFI_ia32, Isolinux, EfiImg -AutoSize
Write-Output "FILES=$($rows.Count)"
