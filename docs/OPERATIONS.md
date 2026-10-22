# 制作操作手册

> 以下命令是操作示例。执行前必须用 `Get-Disk`、`Get-Partition` 核对目标盘型号、容量、序列号和盘符。  
> **永远不要按磁盘编号识别设备**：U 盘重新插拔后，磁盘编号会变化。  
> 本仓库不提供任何镜像、PE 或第三方工具。

## 0. 前置条件

- Windows 10 / 11，管理员 PowerShell。
- Ventoy Windows 版。
- 一块容量足够的 U 盘。
- 本地备份空间。
- 可选：7-Zip，用于查看镜像内部结构。

## 1. 识别磁盘

```powershell
Get-Disk |
  Select-Object Number, FriendlyName, SerialNumber, Size, BusType, PartitionStyle |
  Format-Table -AutoSize

Get-Partition |
  Select-Object DiskNumber, PartitionNumber, DriveLetter, Size, Type |
  Format-Table -AutoSize

Get-Volume |
  Select-Object DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining |
  Format-Table -AutoSize
```

确认：

- 目标盘型号/容量正确；
- 序列号与实物一致；
- 盘符是目标盘；
- 不是系统盘、不是资料盘。

建议记录目标盘序列号：

```powershell
$targetSerial = '<TARGET-DISK-SERIAL>'
$target = Get-Disk | Where-Object SerialNumber -eq $targetSerial
$target | Format-List Number,FriendlyName,SerialNumber,Size,PartitionStyle
```

## 2. 备份原盘

先复制，不要先修复、格式化或运行 `chkdsk /f`。

```powershell
$src = 'F:\'
$dst = 'C:\USB_BACKUP\source'
New-Item -ItemType Directory -Force -Path $dst | Out-Null

robocopy $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NP `
  /XD "$src\System Volume Information" "$src\`$RECYCLE.BIN" `
  /LOG:C:\USB_BACKUP\robocopy.log
```

校验文件数量和总大小：

```powershell
$srcFiles = Get-ChildItem $src -Recurse -File -Force
$dstFiles = Get-ChildItem $dst -Recurse -File -Force

"SOURCE: $($srcFiles.Count) files, $([math]::Round(($srcFiles | Measure-Object Length -Sum).Sum / 1GB, 3)) GiB"
"TARGET: $($dstFiles.Count) files, $([math]::Round(($dstFiles | Measure-Object Length -Sum).Sum / 1GB, 3)) GiB"
```

`robocopy` 退出码说明：

| 退出码 | 含义 |
|---:|---|
| 0 | 无文件复制，无失败 |
| 1 | 有文件复制，无失败 |
| 2 | 有额外文件/目录，无失败 |
| 3 | 有复制 + 额外文件 |
| 7 | 有复制 + 时间戳/属性差异 |
| ≥8 | 有失败，需要检查日志 |

## 3. 安装 Ventoy

使用 Ventoy 的 `Ventoy2Disk.exe`：

1. 选择目标盘（再次核对序列号/容量）。
2. 分区类型选 **MBR**。
3. 文件系统选 **exFAT**。
4. 点击“安装”，确认会清空目标盘。
5. 安装完成后检查：

```powershell
Get-Partition -DiskNumber $target.Number |
  Select-Object PartitionNumber, DriveLetter, Offset, Size, Type |
  Format-Table -AutoSize
```

预期：

- P1 从 **LBA 2048（1 MiB）** 开始；
- P1 是 exFAT，卷标 `Ventoy`；
- P2 是 32 MiB FAT，卷标 `VTOYEFI`。

## 4. 复制数据

把备份数据复制到 P1，不要覆盖 Ventoy 自己的目录：

```powershell
$src = 'C:\USB_BACKUP\source'
$dst = 'G:\'

robocopy $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NP `
  /XD "$src\ventoy" `
  /LOG:C:\USB_BACKUP\restore.log
```

复制完成后再次核对文件数量和总大小。

## 5. 整理 `/ISO`

在 P1 根目录创建：

```text
/ISO
├─ PE
├─ Windows
├─ Linux
└─ Tools
```

把镜像按用途放入对应目录。不要把资料、软件和镜像混在一起。

## 6. 提取旧 UD

UD 不在 MBR 分区表里，需要读原始磁盘。先只读解析：

```powershell
# 先用 Get-Disk 找到原盘编号
.\scripts\parse-ud.ps1 -DiskNumber 1
```

确认表项和范围后，再提取：

```powershell
.\scripts\extract-ud.ps1 `
  -DiskNumber 1 `
  -OutRoot 'C:\USB_BACKUP\source\UD' `
  -Manifest 'C:\USB_BACKUP\source\UD_MANIFEST.csv'
```

如遇到损坏记录，可在确认后使用 `-SkipIndexes` 跳过。

注意：

- 读取原始磁盘需要管理员权限；
- 每个文件使用新的 `FileStream`；
- 按 512 字节对齐读取；
- 先确认 `CD001` 再判断 ISO 有效；
- 不要覆盖已有备份。

## 7. 写入 `ventoy.json`

把本仓库的 `config/ventoy.example.json` 复制到：

```text
G:\ventoy\ventoy.json
```

然后按自己的镜像修改 `menu_alias`。核心控制项：

```json
{
  "control": [
    { "VTOY_MENU_LANGUAGE": "zh_CN" },
    { "VTOY_DEFAULT_MENU_MODE": "1" },
    { "VTOY_TREE_VIEW_MENU_STYLE": "1" },
    { "VTOY_DEFAULT_SEARCH_ROOT": "/ISO" }
  ]
}
```

如果盘符不是 `G:`，只改复制的目标路径，不要改 JSON 内的 `/ISO/...` 路径。

## 8. 校验菜单

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-menu.ps1 `
  -ConfigPath G:\ventoy\ventoy.json `
  -Root G:\
```

期望输出：

```text
MISSING=0
DUPLICATE_ALIASES=0
DUPLICATE_IMAGES=0
```

检查 ISO/IMG 头：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-iso.ps1 `
  -Path G:\ISO -Recurse -SevenZip 'C:\Program Files\7-Zip\7z.exe'
```

## 9. 测试

按 [TESTING.md](TESTING.md) 执行。至少覆盖：

- Legacy 主菜单；
- UEFI 主菜单；
- 一个 PE 镜像；
- 一个系统安装镜像；
- 一个 Linux Live 镜像；
- 一个维护工具镜像。

## 10. 常见问题

### 菜单里看不到某个镜像

- 确认文件在 `/ISO` 下；
- 确认 `VTOY_DEFAULT_SEARCH_ROOT=/ISO`；
- 确认文件名没有特殊字符；
- 在 Ventoy 菜单按 `F5` 重新扫描，或重启。

### 菜单名称还是英文文件名

- `ventoy.json` 路径不对；
- JSON 语法错误，Ventoy 回退到默认菜单；
- `menu_alias` 的 `image` 路径大小写/斜杠不一致。

### UEFI 启动失败

- 检查 `VTOYEFI` 分区是否完整；
- 检查镜像是否有 `EFI/boot/bootx64.efi`；
- 部分镜像只支持 Legacy，属正常现象。

### 旧系统 UEFI 启动失败

部分旧版系统对 UEFI 支持有限，优先使用 Legacy 安装。

## 11. 回滚

如果新盘制作失败：

1. 不要动原盘；
2. 用备份数据重新复制；
3. 重新运行 Ventoy 安装；
4. 恢复 `/ISO` 和 `ventoy.json`；
5. 重新测试。

原盘在确认新盘可用前应保持离线或只读。
