# 菜单设计模板

本文件说明 Ventoy 中文菜单的结构和配置方法。实际镜像名称、路径和菜单项请按自己的盘修改。

> 仓库不包含真实镜像，也不提供任何 PE、系统安装盘或工具下载。

## 1. 配置位置

```text
P1:\ventoy\ventoy.json
```

模板文件：

```text
config/ventoy.example.json
```

## 2. 控制项

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

| 配置 | 作用 |
|---|---|
| `VTOY_MENU_LANGUAGE=zh_CN` | 中文界面 |
| `VTOY_DEFAULT_MENU_MODE=1` | TreeView 目录树 |
| `VTOY_TREE_VIEW_MENU_STYLE=1` | 隐藏目录/文件大小前缀 |
| `VTOY_DEFAULT_SEARCH_ROOT=/ISO` | 只扫描 `/ISO` |

## 3. 目录模板

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

## 4. 菜单别名

```json
{
  "menu_alias": [
    { "image": "/ISO/PE/example-pe.iso", "alias": "PE 维护镜像（示例）" },
    { "image": "/ISO/Windows/example-windows.iso", "alias": "系统安装镜像（示例）" },
    { "image": "/ISO/Linux/example-linux.iso", "alias": "Linux Live 镜像（示例）" },
    { "image": "/ISO/Tools/example-tool.img", "alias": "维护工具镜像（示例）" }
  ]
}
```

修改规则：

1. `image` 必须是 `/ISO` 下的绝对路径，使用 `/` 分隔；
2. `alias` 是菜单显示名称；
3. 不要使用重复别名；
4. 不要使用不存在的路径；
5. 不要把真实镜像提交到仓库。

## 5. 新增菜单项

1. 把镜像放入 `/ISO` 对应分类；
2. 在 `menu_alias` 中增加一条记录；
3. 运行校验：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-menu.ps1 `
  -ConfigPath G:\ventoy\ventoy.json -Root G:\
```

期望：

```text
MISSING=0
DUPLICATE_ALIASES=0
DUPLICATE_IMAGES=0
```

4. 重启到 Ventoy 菜单确认显示。

## 6. 菜单设计建议

- 按用途分类，不按下载来源分类；
- 目录名保持简短，避免特殊字符；
- 菜单别名写清楚“用途 + 启动模式”，例如 `PE 维护镜像（UEFI/BIOS）`；
- 不把资料、软件和镜像混在同一目录；
- 不展示与启动无关的文件。

## 7. 校验脚本

`scripts/validate-menu.ps1` 会检查：

- JSON 是否能解析；
- `menu_alias` 是否为空；
- `image` 路径是否存在；
- 是否有重复别名；
- 是否有重复镜像；
- `/ISO` 下是否有未加入菜单的镜像（警告）。

`scripts/validate-iso.ps1` 会检查：

- ISO9660 `CD001`；
- MBR `55 AA`；
- EFI 引导文件；
- `isolinux`；
- `efi.img`。
