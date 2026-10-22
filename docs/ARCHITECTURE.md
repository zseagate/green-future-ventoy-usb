# 架构说明

## 1. 目标

把旧式 fbinst/Grub4DOS 启动 U 盘重做成标准 **Ventoy** 启动盘，保留自己的 PE、系统安装镜像和维护工具，并统一使用中文菜单。

目标不是原样克隆旧盘，而是：

- 用 Ventoy 直接映射 ISO/IMG；
- 不再维护 Grub4DOS `RUN` / `map` 主菜单；
- 把启动内容统一放入 `/ISO`；
- 支持 Legacy BIOS 和 UEFI；
- 用脚本校验菜单路径和镜像结构；
- 不把镜像、PE 或第三方工具提交到仓库。

## 2. 磁盘布局

目标盘为 MBR，512 字节扇区。

| 区域 | 起始 | 大小 | 文件系统 | 卷标 | 说明 |
|---|---:|---:|---|---|---|
| 保留区 | LBA 0 | 1 MiB | — | — | MBR、对齐保留 |
| P1 | LBA 2048 | 剩余空间 | exFAT | `Ventoy` | 镜像、数据、`/ventoy/ventoy.json` |
| P2 | P1 之后 | 32 MiB | FAT | `VTOYEFI` | Ventoy UEFI 引导文件 |

设计约束：

- P1 必须从 **LBA 2048（1 MiB）** 开始；
- P2 是 FAT 格式的 `VTOYEFI` 分区；
- 使用 MBR，兼容老机器 Legacy BIOS；
- P1 使用 exFAT，支持大于 4 GiB 的镜像；
- 启动镜像统一放入 `/ISO`。

## 3. 引导链

### 3.1 Legacy BIOS

```text
BIOS
  -> MBR
  -> Ventoy Legacy 引导核心
  -> GRUB2
  -> 选择 ISO/IMG
  -> Ventoy 映射为虚拟光驱/软盘
  -> 镜像内部引导器启动
```

### 3.2 UEFI

```text
UEFI Firmware
  -> P2 VTOYEFI/EFI/BOOT/BOOTX64.EFI（或 BOOTIA32.EFI）
  -> Ventoy UEFI 引导核心
  -> GRUB2
  -> 选择 ISO/IMG
  -> 映射并启动
```

### 3.3 和旧盘的区别

旧盘：

```text
fbinst MBR -> UD /GRLDR -> Grub4DOS 菜单
  -> RUN / map / chainloader
```

新盘：

```text
Ventoy MBR/UEFI -> Ventoy 菜单 -> 直接映射 ISO/IMG
```

因此不再需要外部的 `core.img`，也不需要把 Grub4DOS 菜单作为主菜单维护。

## 4. Ventoy 配置

配置文件：`/ventoy/ventoy.json`

关键控制项：

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

| 配置 | 值 | 作用 |
|---|---|---|
| `VTOY_MENU_LANGUAGE` | `zh_CN` | 中文菜单界面 |
| `VTOY_DEFAULT_MENU_MODE` | `1` | TreeView 目录树 |
| `VTOY_TREE_VIEW_MENU_STYLE` | `1` | 不显示 DIR/文件大小前缀 |
| `VTOY_DEFAULT_SEARCH_ROOT` | `/ISO` | 只扫描 `/ISO` 下的镜像 |

`menu_alias` 使用占位路径，复制模板后按自己的镜像修改。

## 5. `/ISO` 目录设计

```text
/ISO
├─ PE
│  └─ example-pe.iso
├─ Windows
│  └─ example-windows.iso
├─ Linux
│  └─ example-linux.iso
└─ Tools
   └─ example-tool.img
```

目录职责：

| 目录 | 内容 |
|---|---|
| `PE` | PE 维护镜像 |
| `Windows` | 系统安装镜像 |
| `Linux` | Linux Live 镜像 |
| `Tools` | 维护工具镜像 |

不要把资料、软件和镜像混在一起，也不要把真实镜像提交到仓库。

## 6. 旧 UD 提取结构

旧盘可能使用 fbinst UD，UD 区域位于磁盘起始，大小由原盘决定，不出现在 MBR 分区表中。

文件表经验结构：

```text
u16 flags
u32 sector        # 绝对扇区号
u32 size          # 字节数
u32 mtime         # Unix 时间戳
char name[]       # NUL 结尾，路径使用 '/'
```

注意：

- 表项头通常为 14 字节；
- 路径为 `/` 分隔；
- 部分记录可能损坏或错位，需要人工确认；
- ISO 有效性检查：读取偏移 `32768` 的 ISO9660 PVD，检查字节 1–5 是否为 `CD001`；
- 文件名可能带异常前缀，需要清理；
- 读取原始磁盘时每个文件使用新的 `FileStream`，并按 512 字节对齐读取。

详见脚本：[../scripts/parse-ud.ps1](../scripts/parse-ud.ps1) 和 [../scripts/extract-ud.ps1](../scripts/extract-ud.ps1)。

## 7. 数据迁移

使用 `robocopy` 复制原盘数据，排除系统目录和旧 Ventoy 残留：

```powershell
robocopy F:\ C:\USB_BACKUP\source /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NP `
  /XD "F:\System Volume Information" "F:\`$RECYCLE.BIN" "F:\ventoy" `
  /LOG:C:\USB_BACKUP\robocopy.log
```

校验：

- 文件数量；
- 总大小；
- 关键文件 SHA256；
- `robocopy` 日志中的失败项。

`robocopy` 退出码 `7` 通常表示“有复制 + 时间戳/属性差异”，不一定代表失败。

## 8. Live 镜像引导结构

不同 PE、Linux Live 和系统安装镜像的引导结构不同。加入菜单前建议检查：

- ISO9660 `CD001`；
- MBR `55 AA`；
- `isolinux/isolinux.bin`；
- `EFI/boot/bootx64.efi`；
- `EFI/boot/bootia32.efi`；
- `boot/grub/efi.img`。

判断：

| 结构 | 启动能力 |
|---|---|
| 只有 `isolinux` | 通常仅 Legacy |
| 有 `EFI/boot/bootx64.efi` | UEFI + Legacy |
| 有 `bootia32.efi` | 可能支持 32 位 UEFI |
| 引导文件不完整 | 需要进一步检查或更换镜像 |

## 9. 已知限制

- 部分旧系统镜像对 UEFI 支持有限，优先使用 Legacy。
- 部分 PE 镜像只支持 BIOS，UEFI 模式可能无法启动。
- 精简版/修改版镜像需要实机验证。
- Secure Boot 不是默认目标；如开启，按固件和 Ventoy 文档处理。
- 不提供任何镜像、PE 或第三方工具的下载。
