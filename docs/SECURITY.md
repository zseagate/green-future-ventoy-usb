# 安全说明

## 1. GitHub Token

本项目在制作过程中可能使用过 GitHub Personal Access Token（PAT）。**Token 不应写入任何文件、提交、Issue 或截图。**

正确做法：

- 通过环境变量传给命令，不要硬编码；
- 使用 `git credential` 或临时 `http.extraheader`，不要把 token 拼进 remote URL；
- 使用最小权限，只给需要的仓库；
- 使用后立即撤销或轮换；
- 如果 token 曾出现在聊天、日志、命令历史中，视为已泄露。

示例（只演示思路，不要把真实 token 写进脚本）：

```powershell
$env:GH_TOKEN = '<YOUR_TOKEN>'
# 使用完后清除
Remove-Item Env:\GH_TOKEN
```

如果发现 token 泄露：

1. 打开 GitHub Settings -> Developer settings -> Personal access tokens；
2. 撤销对应 token；
3. 重新生成；
4. 检查仓库、提交历史、Actions 日志中是否出现 token；
5. 必要时强制推送清理历史。

## 2. 第三方镜像与工具

本仓库不包含、不推荐、不分发任何具体镜像或第三方工具。

你自己加入 U 盘的 PE、系统安装镜像、Linux Live 镜像和维护工具：

- 各有自己的许可条款；
- 可能涉及版权、商标或再分发限制；
- 可能包含安全风险；
- 只应在合法授权和隔离测试环境中使用；
- 不要上传到公开仓库或公开网盘。

## 3. 磁盘操作安全

- 先用 `Get-Disk` / `Get-Partition` 核对型号、容量、序列号和盘符；
- 不要按磁盘编号识别设备；
- 写入前确认目标盘不是系统盘、不是资料盘；
- 原盘在确认新盘可用前保持离线或只读；
- 备份完成前不要运行 `chkdsk /f`、`diskpart clean`、格式化或写 MBR；
- 不要在生产机器上首次测试新启动盘。

## 4. 镜像完整性

建议校验：

- Ventoy 安装包 SHA256；
- 镜像文件 SHA256；
- ISO9660 `CD001` 签名；
- MBR `55 AA` 签名；
- EFI 引导文件是否存在。

`scripts/validate-iso.ps1` 和 `scripts/validate-menu.ps1` 只做基础检查，不能替代实机启动测试。

## 5. 隐私

日志和清单可能包含：

- 磁盘序列号；
- 本机路径；
- 文件名；
- 镜像哈希。

发布到公开仓库前请脱敏：

- 删除序列号；
- 删除用户名/主机名；
- 删除含个人文件的路径；
- 不要把完整 `robocopy` 日志直接上传。

## 6. 许可证

- 本仓库的文档和脚本可按项目需要选择许可证；
- 第三方镜像、PE、工具不自动继承本仓库许可证；
- 引用第三方资源时保留来源和许可信息；
- 不提供任何镜像下载或分发。
