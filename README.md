# browse MCP + open_cr Skill 安装脚本

一键安装 **browse MCP 服务** 与 **open_cr Code Review 技能**，用于 OpenCode 智能代码评审。

## 功能介绍

### browse MCP 服务
- 智能抓取需要鉴权的 Wiki 页面（如内部 Wiki）
- 自动检测登录状态，鉴权过期时弹窗提示扫码登录
- 登录凭证本地缓存，无需重复登录

### open_cr Code Review 技能
- 结合需求文档 URL 与代码进行深度 Code Review
- 自动抓取 Wiki、GitLab Issue 等背景信息
- 交叉比对代码实现与业务逻辑
- 输出结构化的 Review 报告

## 环境要求

- [Node.js](https://nodejs.org/) (v16+)
- [npm](https://www.npmjs.com/)
- [Chrome 浏览器](https://www.google.com/chrome/) (用于页面抓取)

## 快速安装

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/ghwswywps/opencode_codereview_skill/master/install.sh | bash
```

或使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/ghwswywps/opencode_codereview_skill/master/install.sh | bash
```

### Windows (PowerShell)

```powershell
curl -o install.ps1 https://raw.githubusercontent.com/ghwswywps/opencode_codereview_skill/master/install.ps1 && powershell -ExecutionPolicy Bypass -File install.ps1
```

或者直接在 PowerShell 中运行：

```powershell
irm https://raw.githubusercontent.com/ghwswywps/opencode_codereview_skill/master/install.ps1 | iex
```

## 手动安装

如果自动安装失败，可以手动执行：

### 1. 克隆仓库

```bash
git clone https://github.com/ghwswywps/opencode_codereview_skill/master.git
cd skill_cr
```

### 2. 运行安装脚本

**macOS / Linux:**
```bash
chmod +x install.sh
./install.sh
```

**Windows:**
```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

## 安装路径

| 组件 | 路径 |
|------|------|
| MCP 服务 | `~/.opencode-mcp/browse/` |
| 技能配置 | `~/.config/opencode/skills/open_cr/SKILL.md` |
| OpenCode 配置 | `~/.config/opencode/opencode.json` |

## 使用方法

安装完成后，在 OpenCode 中直接对话：

```
帮我用 open_cr 审核一下这段代码，需求在 https://wiki.xxx.com/pricing-engine-v2
```

或提供代码地址：

```
帮我用 open_cr 审核 https://gitlab.xxx.com/pricing-engine/blob/main/src/PriceInterceptor.java
需求文档：https://wiki.xxx.com/pricing-engine-v2
```

## 常见问题

### Q: 提示 "未检测到 Node.js"
A: 请先安装 [Node.js](https://nodejs.org/)，建议安装 LTS 版本。

### Q: 抓取页面时弹窗要求登录
A: 这是正常行为。首次访问需要鉴权的页面时，会弹出浏览器窗口供您扫码登录。登录成功后，凭证会保存在本地，下次无需重复登录。

### Q: 登录超时
A: 登录等待时间为 5 分钟。如果超时，请重新执行命令，脚本会再次弹出登录窗口。

### Q: Windows 上执行脚本报错
A: 确保使用 PowerShell 运行脚本，并以 `-ExecutionPolicy Bypass` 参数绕过执行策略限制。

## 卸载

删除以下目录即可：

```bash
# macOS / Linux
rm -rf ~/.opencode-mcp/browse
rm -rf ~/.config/opencode/skills/open_cr

# Windows (PowerShell)
Remove-Item -Recurse -Force "$env:USERPROFILE\.opencode-mcp\browse"
Remove-Item -Recurse -Force "$env:USERPROFILE\.config\opencode\skills\open_cr"
```

并手动编辑 `~/.config/opencode/opencode.json`，移除 `mcp.browse` 配置项。

## License

MIT
