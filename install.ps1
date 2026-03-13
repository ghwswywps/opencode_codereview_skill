$ErrorActionPreference = "Stop"

Write-Host "🚀 开始安装 browse MCP 与 Code Review 技能 (包含 actions 交互能力)..." -ForegroundColor Cyan

# 1. 环境检查 (移除自动安装，未检测到直接退出)
if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 错误: 未检测到 Node.js。请先前往 https://nodejs.org/ 手动安装 (建议 v20+)。" -ForegroundColor Red
    exit 1
}
if (-not (Get-Command "npm" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ 错误: 未检测到 npm。请检查 Node.js 安装是否完整。" -ForegroundColor Red
    exit 1
}

Write-Host "✅ 环境检查通过: Node.js $(node -v), npm $(npm -v)" -ForegroundColor Green
Write-Host "🔧 配置 npm 使用国内镜像 (npmmirror)..." -ForegroundColor Gray
npm config set registry https://registry.npmmirror.com --silent 2>$null

# 2. 定义路径
$HOME_DIR = [System.Environment]::GetFolderPath('UserProfile')
$INSTALL_DIR = Join-Path $HOME_DIR ".opencode-mcp\browse"
$SKILL_DIR = Join-Path $HOME_DIR ".config\opencode\skills\open_cr"

# 3. 创建 MCP 项目目录
Write-Host "📦 初始化 MCP 服务环境..." -ForegroundColor Yellow
if (-not (Test-Path $INSTALL_DIR)) { New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null }
Set-Location -Path $INSTALL_DIR

# 写入 package.json
$packageJson = @'
{
  "name": "browse",
  "version": "6.1.0",
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.1",
    "playwright-core": "^1.40.0"
  }
}
'@
Set-Content -Path "package.json" -Value $packageJson -Encoding UTF8

# 写入 MCP 核心代码 (index.js - 包含 actions 支持)
$indexJs = @'
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { chromium, firefox, webkit } from "playwright-core";
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const AUTH_PATH  = path.join(__dirname, 'auth.json');

const BROWSER_TYPE    = process.env.BROWSER_TYPE    || 'chromium';
const BROWSER_CHANNEL = process.env.BROWSER_CHANNEL || 'chrome';

const LOGIN_KEYWORDS = ['企微扫码', '密码登录', '验证码登录', '企业微信登录', '扫描二维码登录', '单点登录', '账号登录', '账号密码登录', 'sign in', 'sign up', 'username', 'password', 'remember me', 'ldap', 'login'];
const LOGIN_URL_RE   = /(login|sso|auth|sign_in|oauth)/i;

function getBrowserEngine() {
  switch (BROWSER_TYPE) {
    case 'firefox': return firefox;
    case 'webkit':  return webkit;
    default:        return chromium;
  }
}

function isLoginPage(content, url) {
  const lowerContent = content.toLowerCase();
  if (LOGIN_URL_RE.test(url)) return true;
  if (content.trim().length < 150) return true;
  return LOGIN_KEYWORDS.some(kw => lowerContent.includes(kw));
}

function isLoggedInContent(content, url) {
  const lowerContent = content.toLowerCase();
  return !LOGIN_URL_RE.test(url) && content.trim().length > 500 && !LOGIN_KEYWORDS.some(kw => lowerContent.includes(kw));
}

const server = new Server(
  { name: "browse", version: "6.1.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "fetch_page",
    description: "抓取需要鉴权的网页。支持在提取文本前执行点击、输入等交互动作。如果鉴权过期，会自动弹窗要求用户扫码登录。",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "要抓取的网页 URL" },
        actions: { 
          type: "array", 
          description: "可选。在读取页面内容前要执行的动作列表。支持: 'click' (需 selector), 'fill' (需 selector 和 value), 'wait' (需 ms), 'waitForSelector' (需 selector)。",
          items: {
            type: "object",
            properties: {
              action: { type: "string" },
              selector: { type: "string" },
              value: { type: "string" },
              ms: { type: "number" }
            }
          }
        }
      },
      required: ["url"],
    },
  }],
}));

async function launchBrowser(headless) {
  const engine = getBrowserEngine();
  const launchOpts = { headless };
  if (BROWSER_CHANNEL) launchOpts.channel = BROWSER_CHANNEL;
  return engine.launch(launchOpts);
}

async function waitForLoginComplete(page) {
  console.error("🌐 监测到登录拦截，请在弹出的浏览器中扫码...");
  const MAX_WAIT_MS = 5 * 60 * 1000;
  const POLL_INTERVAL = 2000;
  const STABLE_REQUIRED = 2;
  let stableCount = 0;
  const deadline = Date.now() + MAX_WAIT_MS;

  while (Date.now() < deadline) {
    try {
      await page.waitForTimeout(POLL_INTERVAL);
      const checkContent = await page.evaluate(() => document.body.innerText);
      const checkUrl = page.url();
      if (isLoggedInContent(checkContent, checkUrl)) {
        stableCount++;
        console.error(`✅ 正在确认正文稳定性... (${stableCount}/${STABLE_REQUIRED})`);
        if (stableCount >= STABLE_REQUIRED) return;
      } else { stableCount = 0; }
    } catch { stableCount = 0; }
  }
  throw new Error('等待扫码登录超时');
}

async function fetchPage(url, headless, actions = []) {
  const hasAuth = fs.existsSync(AUTH_PATH);
  const browser = await launchBrowser(headless);

  try {
    const context = await browser.newContext(hasAuth ? { storageState: AUTH_PATH } : {});
    const page = await context.newPage();

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(3000);

    // ✨ 执行页面交互动作
    if (actions && Array.isArray(actions) && actions.length > 0) {
      console.error(`[DEBUG] 正在执行 ${actions.length} 个页面交互动作...`);
      for (const step of actions) {
        try {
          switch (step.action) {
            case 'click':
              await page.click(step.selector); break;
            case 'fill':
              await page.fill(step.selector, step.value); break;
            case 'wait':
              await page.waitForTimeout(step.ms); break;
            case 'waitForSelector':
              await page.waitForSelector(step.selector, { timeout: 10000 }); break;
          }
          await page.waitForTimeout(500); 
        } catch (actErr) {
          console.error(`[DEBUG] 动作执行失败 (${step.action}): ${actErr.message}`);
        }
      }
    }

    let content = await page.evaluate(() => document.body.innerText);
    const currentUrl = page.url();

    if (isLoginPage(content, currentUrl)) {
      if (headless) {
        await browser.close();
        throw new Error('NEEDS_LOGIN');
      }
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

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name !== "fetch_page") throw new Error("未知工具");
  const url = request.params.arguments.url;
  const actions = request.params.arguments.actions || [];

  try {
    const content = await fetchPage(url, true, actions);
    return { content: [{ type: "text", text: content }] };
  } catch (error) {
    if (error.message !== 'NEEDS_LOGIN') return { content: [{ type: "text", text: `抓取异常: ${error.message}` }], isError: true };
  }

  try {
    console.error("⚠️ 正在唤起浏览器进行手动扫码登录...");
    const content = await fetchPage(url, false, actions);
    return { content: [{ type: "text", text: content }] };
  } catch (uiError) {
    return { content: [{ type: "text", text: `手动登录抓取失败: ${uiError.message}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`🚀 网页抓取与交互服务已启动 (browser: ${BROWSER_TYPE})`);
'@
Set-Content -Path "index.js" -Value $indexJs -Encoding UTF8

Write-Host "⏳ 正在安装 npm 依赖..." -ForegroundColor Yellow
npm install --silent

# 4. 配置 OpenCode MCP (使用独立 JS 确保路径解析无误)
Write-Host "⚙️ 正在注册 MCP 服务到 OpenCode..." -ForegroundColor Yellow
$nodeScript = @'
const fs = require('fs');
const path = require('path');
const os = require('os');

const homeDir = os.homedir();
const configFile = path.join(homeDir, '.config', 'opencode', 'opencode.json');
const mcpDir = path.join(homeDir, '.opencode-mcp', 'browse');

let config = {};
if (fs.existsSync(configFile)) {
  try { config = JSON.parse(fs.readFileSync(configFile, 'utf8')); } 
  catch (e) { console.log('⚠️ opencode.json 格式有误，将覆盖重建。'); }
}

if (!config.mcp) config.mcp = {};
config.mcp['browse'] = {
  type: 'local',
  command: ['node', path.join(mcpDir, 'index.js')],
  enabled: true,
  environment: { BROWSER_CHANNEL: 'chrome' }
};

fs.mkdirSync(path.dirname(configFile), { recursive: true });
fs.writeFileSync(configFile, JSON.stringify(config, null, 2));
'@
node -e $nodeScript

# 5. 生成 open_cr Skill
Write-Host "🧠 正在生成 open_cr Code Review 技能..." -ForegroundColor Yellow
if (-not (Test-Path $SKILL_DIR)) { New-Item -ItemType Directory -Force -Path $SKILL_DIR | Out-Null }

$skillMd = @'
---
name: open_cr
description: 结合需求文档 URL 与代码进行深度 Code Review 的智能助手，支持操作复杂页面
---

# open_cr: 智能 Code Review 助手

当用户需要进行 Code Review 并提供相关链接时，请遵循：

1. **获取背景**：调用 `browse` 的 `fetch_page` 工具。如果页面有折叠面板、需要切换 Tab 等，你可以传入 `actions` 数组（包含 click, wait 等）来操作页面后再读取内容。
2. **交叉比对**：将抓取到的需求上下文与代码进行严格比对，确认代码是否忠实实现了业务逻辑。
3. **深度评估**：检查架构设计、健壮性、异常处理及潜在安全/性能问题。
4. **输出报告**：给出结构清晰的 Review 报告，包含“背景一致性评估”、“发现的问题”以及“改进建议”。
'@
Set-Content -Path (Join-Path $SKILL_DIR "SKILL.md") -Value $skillMd -Encoding UTF8

Write-Host "✅ 安装完成！请重启 OpenCode 以加载最新工具。" -ForegroundColor Green
