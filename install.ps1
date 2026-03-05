$ErrorActionPreference = "Stop"

Write-Host "🚀 开始安装 browse MCP 与 Code Review 技能..." -ForegroundColor Cyan

# 1. 环境检查 & 自动安装 Node.js
function Install-NodeJS {
    param(
        [string]$Version = "20.11.0"
    )
    
    Write-Host "📦 正在通过国内镜像安装 Node.js v$Version..." -ForegroundColor Yellow
    
    # 检测系统架构
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $nodeUrl = "https://npmmirror.com/mirrors/node/v$Version/node-v$Version-win-$arch.zip"
    $tempDir = [System.IO.Path]::GetTempPath()
    $zipFile = Join-Path $tempDir "node.zip"
    $extractDir = Join-Path $tempDir "node-extract"
    $installDir = Join-Path $env:LOCALAPPDATA "NodeJS"
    
    try {
        # 下载 Node.js
        Write-Host "  ⬇️ 正在从 npmmirror.com 下载 Node.js..." -ForegroundColor Gray
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $nodeUrl -OutFile $zipFile -UseBasicParsing
        
        # 解压
        Write-Host "  📂 正在解压..." -ForegroundColor Gray
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
        
        # 移动到安装目录
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
        Move-Item -Path (Join-Path $extractDir "node-v$Version-win-$arch") -Destination $installDir -Force
        
        # 添加到 PATH (用户级别)
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $nodePath = $installDir
        if ($userPath -notlike "*$nodePath*") {
            [Environment]::SetEnvironmentVariable("PATH", "$nodePath;$userPath", "User")
            $env:PATH = "$nodePath;$env:PATH"
        }
        
        # 清理临时文件
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Host "  ✅ Node.js 安装完成！" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ❌ 自动安装失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  💡 请手动安装 Node.js: https://npmmirror.com/mirrors/node/" -ForegroundColor Yellow
        return $false
    }
}

if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    Write-Host "⚠️ 未检测到 Node.js，正在尝试自动安装..." -ForegroundColor Yellow
    
    # 尝试使用 winget 安装 (如果可用)
    if (Get-Command "winget" -ErrorAction SilentlyContinue) {
        Write-Host "📦 检测到 winget，正在通过 winget 安装 Node.js..." -ForegroundColor Yellow
        try {
            winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
            # 刷新环境变量
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        }
        catch {
            Write-Host "⚠️ winget 安装失败，尝试通过国内镜像手动安装..." -ForegroundColor Yellow
            if (-not (Install-NodeJS)) { exit 1 }
        }
    }
    else {
        # 直接通过国内镜像安装
        if (-not (Install-NodeJS)) { exit 1 }
    }
    
    # 再次检查
    if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Node.js 安装后仍无法检测到，请重启终端后再试" -ForegroundColor Red
        exit 1
    }
}

if (-not (Get-Command "npm" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 错误: 未检测到 npm。请检查 Node.js 安装是否完整。" -ForegroundColor Red
    exit 1
}

# 配置 npm 使用国内镜像
Write-Host "🔧 配置 npm 使用国内镜像 (npmmirror)..." -ForegroundColor Yellow
npm config set registry https://registry.npmmirror.com --silent 2>$null

Write-Host "✅ 环境检查通过: Node.js $(node -v), npm $(npm -v)" -ForegroundColor Green

# 2. 定义路径 (自动获取 Windows 用户目录)
$HOME_DIR = [System.Environment]::GetFolderPath('UserProfile')
$INSTALL_DIR = Join-Path $HOME_DIR ".opencode-mcp\browse"
$CONFIG_DIR = Join-Path $HOME_DIR ".config\opencode"
$CONFIG_FILE = Join-Path $CONFIG_DIR "opencode.json"
$SKILL_DIR = Join-Path $CONFIG_DIR "skills\open_cr"

# 3. 创建 MCP 项目目录并写入代码
Write-Host "📦 初始化 MCP 服务环境..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Set-Location -Path $INSTALL_DIR

# 写入 package.json
$packageJson = @'
{
  "name": "browse",
  "version": "6.0.0",
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.1",
    "playwright-core": "^1.40.0"
  }
}
'@
Set-Content -Path "package.json" -Value $packageJson -Encoding UTF8

# 写入 MCP 核心代码 (index.js)
$indexJs = @'
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { chromium, firefox, webkit } from "playwright-core";
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// ── 常量 & 配置 (修改版) ──────────────────────────────────────────────
const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const AUTH_PATH  = path.join(__dirname, 'auth.json');

const BROWSER_TYPE    = process.env.BROWSER_TYPE    || 'chromium';
const BROWSER_CHANNEL = process.env.BROWSER_CHANNEL || 'chrome';

// 建议将英文关键词全部改为小写，方便做忽略大小写的匹配
const LOGIN_KEYWORDS = [
  // 中文登录关键词
  '企微扫码', '密码登录', '验证码登录', '企业微信登录', '扫描二维码登录', '单点登录', '账号登录', '账号密码登录',
  // 英文登录关键词 (全部小写)
  'sign in', 'sign up', 'username', 'password', 'remember me', 'ldap', 'login'
];

// 增加了 sign_in (GitLab 常用) 和 oauth
const LOGIN_URL_RE   = /(login|sso|auth|sign_in|oauth)/i;

// ── 工具函数 (修改版) ──────────────────────────────────────────────────
function getBrowserEngine() {
  switch (BROWSER_TYPE) {
    case 'firefox': return firefox;
    case 'webkit':  return webkit;
    default:        return chromium;
  }
}

function isLoginPage(content, url) {
  const lowerContent = content.toLowerCase();
  
  // 1. URL 命中登录特征
  if (LOGIN_URL_RE.test(url)) return true;
  
  // 2. 页面内容过短（通常是空白页或跳转页）
  if (content.trim().length < 150) return true;
  
  // 3. 忽略大小写匹配登录关键词
  return LOGIN_KEYWORDS.some(kw => lowerContent.includes(kw));
}

function isLoggedInContent(content, url) {
  const lowerContent = content.toLowerCase();
  
  // 通用登录成功判断：URL 无登录特征 + 内容足够长 + 无登录关键词
  return !LOGIN_URL_RE.test(url)
    && content.trim().length > 500
    && !LOGIN_KEYWORDS.some(kw => lowerContent.includes(kw));
}

// ── MCP Server ───────────────────────────────────────────────
const server = new Server(
  { name: "browse", version: "6.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "fetch_page",
    description: "抓取途虎 Wiki 等需要鉴权的网页。如果鉴权过期，会自动弹窗要求用户扫码登录。",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "要抓取的 Wiki 页面 URL" }
      },
      required: ["url"],
    },
  }],
}));

// ── 核心抓取逻辑 ─────────────────────────────────────────────
async function launchBrowser(headless) {
  const engine = getBrowserEngine();
  const launchOpts = { headless };
  if (BROWSER_CHANNEL) {
    launchOpts.channel = BROWSER_CHANNEL;
  }
  return engine.launch(launchOpts);
}

async function waitForLoginComplete(page) {
  console.error("🌐 监测到登录拦截，请在弹出的浏览器中扫码...");

  const MAX_WAIT_MS = 5 * 60 * 1000; // 最多等 5 分钟
  const POLL_INTERVAL = 2000;
  const STABLE_REQUIRED = 2;

  let stableCount = 0;
  const deadline = Date.now() + MAX_WAIT_MS;

  while (Date.now() < deadline) {
    // waitForTimeout 也放进 try/catch，防止页面导航时抛异常导致浏览器被关闭
    try {
      await page.waitForTimeout(POLL_INTERVAL);
      const checkContent = await page.evaluate(() => document.body.innerText);
      const checkUrl = page.url();

      if (isLoggedInContent(checkContent, checkUrl)) {
        stableCount++;
        console.error(`✅ 正在确认正文稳定性... (${stableCount}/${STABLE_REQUIRED})`);
        if (stableCount >= STABLE_REQUIRED) return;
      } else {
        stableCount = 0;
      }
    } catch {
      // 页面正在跳转时 evaluate / waitForTimeout 可能报错，忽略即可
      stableCount = 0;
    }
  }

  throw new Error('等待扫码登录超时（5 分钟）');
}

async function fetchPage(url, headless) {
  const hasAuth = fs.existsSync(AUTH_PATH);
  console.error(`[DEBUG] fetchPage called: headless=${headless}, hasAuth=${hasAuth}, url=${url}`);
  
  const browser = await launchBrowser(headless);

  try {
    const context = await browser.newContext(hasAuth ? { storageState: AUTH_PATH } : {});
    const page = await context.newPage();

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(3000);

    let content = await page.evaluate(() => document.body.innerText);
    const currentUrl = page.url();
    
    console.error(`[DEBUG] Page loaded: url=${currentUrl}, contentLen=${content.trim().length}`);
    console.error(`[DEBUG] isLoginPage result: ${isLoginPage(content, currentUrl)}`);

    if (isLoginPage(content, currentUrl)) {
      console.error(`[DEBUG] Detected login page! headless=${headless}`);
      if (headless) {
        console.error(`[DEBUG] Throwing NEEDS_LOGIN error`);
        await browser.close();
        throw new Error('NEEDS_LOGIN');
      }

      // 非 headless：等待用户扫码
      await waitForLoginComplete(page);

      console.error("🎉 登录成功！正在保存凭证并抓取...");
      await page.waitForTimeout(2000);
      await context.storageState({ path: AUTH_PATH });
      content = await page.evaluate(() => document.body.innerText);
    }

    await browser.close();
    return content;
  } catch (err) {
    await browser.close().catch(() => {});
    throw err;
  }
}

// ── 工具请求处理 ─────────────────────────────────────────────
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name !== "fetch_page") {
    throw new Error("未知工具");
  }

  const url = request.params.arguments.url;

  try {
    // 1. 先尝试静默后台抓取
    const content = await fetchPage(url, true);
    return { content: [{ type: "text", text: content }] };
  } catch (error) {
    if (error.message !== 'NEEDS_LOGIN') {
      return { content: [{ type: "text", text: `抓取异常: ${error.message}` }], isError: true };
    }
  }

  try {
    // 2. 后台失败，唤起浏览器让用户扫码
    console.error("⚠️ 正在唤起浏览器进行手动扫码登录...");
    const content = await fetchPage(url, false);
    return { content: [{ type: "text", text: content }] };
  } catch (uiError) {
    return { content: [{ type: "text", text: `手动登录抓取失败: ${uiError.message}` }], isError: true };
  }
});

// ── 启动 ─────────────────────────────────────────────────────
const transport = new StdioServerTransport();
await server.connect(transport);

console.error(`🚀 途虎 Wiki 智能抓取服务已启动 (browser: ${BROWSER_TYPE}${BROWSER_CHANNEL ? '/' + BROWSER_CHANNEL : ''})`);
'@
Set-Content -Path "index.js" -Value $indexJs -Encoding UTF8

# 安装依赖
Write-Host "⏳ 正在安装 npm 依赖 (可能会花费几十秒)..." -ForegroundColor Yellow
npm install --silent

# 4. 配置 OpenCode MCP (使用内联 Node.js 脚本处理路径转义和 JSON 解析)
Write-Host "⚙️ 正在注册 MCP 服务到 OpenCode..." -ForegroundColor Yellow
$nodeScript = @"
const fs = require('fs');
const path = require('path');
const configFile = '$(($CONFIG_FILE -replace '\\', '\\\\'))';
const mcpDir = '$(($INSTALL_DIR -replace '\\', '\\\\'))';

let config = {};
if (fs.existsSync(configFile)) {
  try {
    config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
  } catch (e) {
    console.log('  ⚠️ 现有的 opencode.json 格式有误，将覆盖重建。');
  }
}

if (!config.mcp) config.mcp = {};
config.mcp['browse'] = {
  type: 'local',
  command: ['node', path.join(mcpDir, 'index.js')],
  enabled: true,
  environment: {
    BROWSER_CHANNEL: 'chrome' 
  }
};

fs.mkdirSync(path.dirname(configFile), { recursive: true });
fs.writeFileSync(configFile, JSON.stringify(config, null, 2));
"@

node -e $nodeScript

# 5. 生成 open_cr Skill
Write-Host "🧠 正在生成 open_cr Code Review 技能..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $SKILL_DIR | Out-Null

$skillMd = @'
---
name: open_cr
description: 结合需求文档 URL 与代码进行深度 Code Review 的智能助手
---

# open_cr: 途虎智能 Code Review 助手

当用户需要你进行 Code Review，并提供了一段代码以及相关的 Wiki、GitLab Issue 或需求文档链接时，你必须遵循以下步骤：

1. **获取背景信息**：调用 `browse` 工具，传入用户提供的所有 URL，抓取需求背景、类图、ER 图或技术方案细节，以及代码逻辑。
2. **交叉比对**：将抓取到的上下文与用户提供的代码进行严格比对，确认代码是否忠实实现了业务逻辑。
3. **深度 Code Review**：
   - 检查架构设计是否合理（例如：定价系统中的价格计算拦截器是否符合设计模式）。
   - 检查代码健壮性、异常处理和边界条件。
   - 识别潜在的安全漏洞、性能瓶颈（如慢 SQL、冗余循环）。
4. **输出报告**：给出一份结构清晰的 Review 报告，包含“背景一致性评估”、“发现的问题（严重程度排序）”以及“改进建议代码段”。

**交互示例**：
用户："帮我用 open_cr 审核一下这个定价策略引擎的实现代码，需求方案在 https://wiki.xxx.com/pricing-engine-v2"
代码地址，例如：https://gitlab.xxx.com/pricing-engine/blob/main/src/PriceInterceptor.java
你：（自动调用工具抓取 URL，然后输出综合了业务逻辑和代码质量的评审报告）
'@
Set-Content -Path (Join-Path $SKILL_DIR "SKILL.md") -Value $skillMd -Encoding UTF8

Write-Host ""
Write-Host "✅ 安装完成！" -ForegroundColor Green
Write-Host "👉 MCP 安装路径: $INSTALL_DIR" -ForegroundColor Green
Write-Host "👉 技能配置路径: $SKILL_DIR\SKILL.md" -ForegroundColor Green
Write-Host "💡 现在你可以在 OpenCode 中直接对我说: `"帮我用 open_cr 审核一下这段代码，需求在 <Wiki链接>, 代码在 <代码链接LIST>`"" -ForegroundColor Green