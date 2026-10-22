# 绿启未来 Ventoy 启动 U 盘制作模板

本项目记录一套 **Ventoy 启动 U 盘** 的制作架构、中文菜单配置、操作流程和校验脚本，适合用来整理自己的 PE、系统安装镜像和维护工具。

> 本仓库只包含文档、配置模板和 PowerShell 脚本，**不包含任何镜像、PE、WIM、工具二进制或第三方资源**。  
> 文档中的镜像名称、路径和菜单项均为占位示例，不代表任何具体发行版或工具。

## 项目特点

- Ventoy 1.1.x，MBR 分区表。
- P1 从 LBA 2048（1 MiB）开始，exFAT，卷标 `Ventoy`。
- P2 为 32 MiB FAT 分区，卷标 `VTOYEFI`，用于 UEFI 引导。
- 支持 Legacy BIOS + UEFI。
- 中文 TreeView 菜单。
- 只扫描 `/ISO` 目录，避免资料目录进入启动菜单。
- 提供磁盘识别、数据备份、菜单校验和镜像结构检查脚本。
- 提供 fbinst UD 文件表的只读解析与提取脚本。

## 目标盘布局

| 区域 | 起始 | 大小 | 文件系统 | 用途 |
|---|---:|---:|---|---|
| 保留区 | LBA 0 | 1 MiB | — | MBR / 对齐保留 |
| P1 | LBA 2048 | 剩余空间 | exFAT，`Ventoy` | 镜像、数据、`ventoy.json` |
| P2 | P1 之后 | 32 MiB | FAT，`VTOYEFI` | Ventoy UEFI 引导文件 |

- 分区表：MBR
- 扇区：512 字节
- 固件：Legacy BIOS + UEFI
- Secure Boot：未作为默认目标要求，按固件和 Ventoy 文档处理

## 启动流程

### Legacy BIOS

```text
MBR -> Ventoy 引导核心 -> GRUB2 -> 映射 ISO/IMG -> 启动
```

### UEFI

```text
P2 VTOYEFI/EFI/BOOT/BOOTX64.EFI
  -> Ventoy UEFI 引导核心
  -> GRUB2
  -> 映射 ISO/IMG
  -> 启动
```

Ventoy 直接映射镜像，不需要旧 Grub4DOS 的 `RUN` / `map`，也不依赖外部的 `core.img`。

## 菜单架构

配置模板：[`config/ventoy.example.json`](config/ventoy.example.json)

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

- `VTOY_DEFAULT_SEARCH_ROOT=/ISO`：只扫描 `/ISO`。
- `VTOY_DEFAULT_MENU_MODE=1`：目录树模式。
- `VTOY_TREE_VIEW_MENU_STYLE=1`：隐藏目录/文件大小前缀。
- `menu_alias` 使用占位路径，复制后按自己的镜像修改。

## `/ISO` 目录模板

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

建议按类别分目录，不要把资料、软件和镜像混在一起。

## 仓库结构

```text
.
├─ README.md
├─ .gitignore
├─ config/
│  └─ ventoy.example.json      # 通用菜单模板，不含真实镜像名
├─ docs/
│  ├─ ARCHITECTURE.md          # 磁盘布局、引导链、UD 表结构
│  ├─ MENU.md                  # 菜单设计模板与配置说明
│  ├─ OPERATIONS.md            # 从识别磁盘到写入 Ventoy 的操作步骤
│  ├─ TESTING.md               # Legacy/UEFI 测试矩阵
│  └─ SECURITY.md              # Token、第三方内容和磁盘安全
└─ scripts/
   ├─ parse-ud.ps1             # 只读解析 fbinst UD 文件表
   ├─ extract-ud.ps1           # 提取 UD 文件并校验 SHA256
   ├─ validate-iso.ps1         # 检查 ISO/IMG 引导结构
   └─ validate-menu.ps1        # 校验 ventoy.json 路径和菜单覆盖
```

## 快速使用

1. 按 [docs/OPERATIONS.md](docs/OPERATIONS.md) 识别磁盘、备份并安装 Ventoy。
2. 将 `config/ventoy.example.json` 复制到 U 盘 P1 的 `\ventoy\ventoy.json`。
3. 按自己的镜像修改 `menu_alias` 中的占位路径和中文名称。
4. 运行校验：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-menu.ps1 `
  -ConfigPath G:\ventoy\ventoy.json -Root G:\
```

5. 按 [docs/TESTING.md](docs/TESTING.md) 做 Legacy + UEFI 实机测试。

## 安全与免责声明

- 制作前必须备份目标盘；不要按磁盘编号识别设备，按序列号/型号识别。
- 不要对来源不明的磁盘运行 `chkdsk`、`diskpart clean`、格式化或写入 MBR。
- 仓库不包含 PE 镜像、系统安装镜像或第三方工具。
- 第三方 PE/工具可能涉及许可、版权或安全风险；请只在合法授权和隔离环境中使用。
- 实机启动前请先在测试机验证，避免误装系统或误分区。
- 本仓库只提供技术模板，不提供任何镜像下载或分发。

## 相关文档

- [架构说明](docs/ARCHITECTURE.md)
- [菜单模板](docs/MENU.md)
- [制作操作](docs/OPERATIONS.md)
- [测试清单](docs/TESTING.md)
- [安全说明](docs/SECURITY.md)
