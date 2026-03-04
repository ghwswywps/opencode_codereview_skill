#!/bin/bash

# 遇到错误即退出
set -e

# 颜色定义，提升终端输出体验
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 开始安装 途虎 Wiki Fetcher MCP 服务与 tuhucr 技能...${NC}"

# 1. 环境检查
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ 错误: 未检测到 Node.js。请先安装 Node.js (建议 v18+)。${NC}"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ 错误: 未检测到 npm。${NC}"
    exit 1
fi

# 2. 初始化安装目录
INSTALL_DIR="$HOME/.tuhu-mcp"
echo -e "${BLUE}📁 正在初始化工作目录: ${INSTALL_DIR}${NC}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 3. 生成 package.json
cat << 'EOF' > package.json
{
  "name": "tuhu-wiki-fetcher",
  "version": "6.0.0",
  "type": "module",
  "description": "Tuhu Wiki Fetcher MCP Server",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.1",
    "playwright-core": "^1.40.0"
  }
}
EOF

# 4. 生成 index.js (直接写入你提供的 Node.js 代码)
# 注意: 这里使用 'EOF' 带单引号，防止 bash 解析其中的变量 (如 $1, $2 等)
echo -e "${BLUE}✍️  正在写入 MCP Server 源码...${NC}"
cat << 'EOF' > index.js
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

const LOGIN_KEYWORDS = [
  '企微扫码', '密码登录', '验证码登录', '企业微信登录', '扫描二维码登录', '单点登录', '账号登录', '账号密码登录',
  'sign in', 'sign up', 'username', 'password', 'remember me', 'ldap', 'login'
];

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
  if (LOGIN_URL_RE.test(url)) return true;
  if (content.trim().length < 150) return true;
  return LOGIN_KEYWORDS.some(kw => lowerContent.includes(kw));
}

function isLoggedInContent(content, url) {
  const lowerContent = content.toLowerCase();
  return !LOGIN_URL_RE.test(url)
    && content.trim().length > 500
    && !LOGIN_KEYWORDS.some(kw => lowerContent.includes(kw));
}

// ── MCP Server ───────────────────────────────────────────────
const server = new Server(
  { name: "tuhu-wiki-fetcher", version: "6.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: "fetch_wiki_page",
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
      } else {
        stableCount = 0;
      }
    } catch {
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

// ── 工具请求处理 ─────────────────────────────────────────────
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name !== "fetch_wiki_page") {
    throw new Error("未知工具");
  }
  const url = request.params.arguments.url;
  try {
    const content = await fetchPage(url, true);
    return { content: [{ type: "text", text: content }] };
  } catch (error) {
    if (error.message !== 'NEEDS_LOGIN') {
      return { content: [{ type: "text", text: `抓取异常: ${error.message}` }], isError: true };
    }
  }
  try {
    console.error("⚠️ 正在唤起浏览器进行手动扫码登录...");
    const content = await fetchPage(url, false);
    return { content: [{ type: "text", text: content }] };
  } catch (uiError) {
    return { content: [{ type: "text", text: `手动登录抓取失败: ${uiError.message}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`🚀 途虎 Wiki 智能抓取服务已启动 (browser: ${BROWSER_TYPE}${BROWSER_CHANNEL ? '/' + BROWSER_CHANNEL : ''})`);
EOF

# 5. 安装依赖
echo -e "${BLUE}📦 正在安装 npm 依赖 (这可能需要几秒钟)...${NC}"
npm install --silent

# 6. 配置 OpenCode MCP
# 【注意】这里假设 OpenCode 的 MCP 配置文件位于 ~/.opencode/mcp.json。如果路径不同，请在此处修改。
OPENCODE_CONFIG_DIR="$HOME/.opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/mcp.json"

echo -e "${BLUE}⚙️  正在配置 OpenCode MCP...${NC}"
mkdir -p "$OPENCODE_CONFIG_DIR"

# 如果配置文件不存在，则初始化一个基础结构
if [ ! -f "$OPENCODE_CONFIG_FILE" ]; then
    echo '{"mcpServers": {}}' > "$OPENCODE_CONFIG_FILE"
fi

# 使用 Python 来安全地更新 JSON (避免引入 jq 依赖，Mac/Linux 通常自带 Python3)
python3 -c "
import json
import os
import sys

config_path = sys.argv[1]
install_dir = sys.argv[2]
node_path = os.popen('which node').read().strip()

with open(config_path, 'r', encoding='utf-8') as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        data = {'mcpServers': {}}

if 'mcpServers' not in data:
    data['mcpServers'] = {}

data['mcpServers']['tuhu-wiki-fetcher'] = {
    'command': node_path,
    'args': [f'{install_dir}/index.js'],
    'env': {
        'BROWSER_TYPE': 'chromium',
        'BROWSER_CHANNEL': 'chrome'
    }
}

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" "$OPENCODE_CONFIG_FILE" "$INSTALL_DIR"

# 7. 生成 tuhucr 技能 (Skill/Prompt)
# 【注意】这里假设 OpenCode 通过特定目录存放自定义 Prompt 技能。
OPENCODE_SKILLS_DIR="$HOME/.opencode/skills"
mkdir -p "$OPENCODE_SKILLS_DIR"

echo -e "${BLUE}🧠 正在生成 'tuhucr' 代码审查技能...${NC}"
cat << 'EOF' > "$OPENCODE_SKILLS_DIR/tuhucr.md"
# 技能名称: tuhucr (途虎 Code Review)
# 触发指令: /tuhucr [Wiki/GitLab 链接]

## 角色与目标
你是一位资深的系统架构师和资深研发工程师。当用户提供 Wiki 设计文档或 GitLab 代码链接时，你需要调用 `fetch_wiki_page` MCP 工具获取页面正文，然后进行极其专业、严谨的代码审查 (Code Review)。

## 执行流程
1. **获取信息**: 提取用户提供的 URL，静默调用 `fetch_wiki_page` 获取内容。如果遇到登录提示，请告知用户在弹出的浏览器中完成扫码。
2. **理解上下文**: 快速通读文档或代码，理解其业务背景（如：定价逻辑、营销逻辑、系统架构等）。
3. **深度 Review**: 
   - **架构设计**: 评估类图、ER图、交互时序图的合理性。
   - **代码质量**: 指出潜在的 Bug、NPE（空指针异常）、并发问题或不符合 SOLID 原则的坏味道。
   - **性能与安全**: 检查是否存在慢 SQL 隐患、缓存穿透/击穿风险、以及权限越权风险。
4. **输出报告**: 以清晰的 Markdown 格式输出 Review 结果，包含：【背景提要】、【发现的问题 (按严重程度排序)】、【优化建议与重构思路】。

## 语气要求
保持客观、专业、直击要害。用词要干练。
EOF

echo -e "${GREEN}✅ 安装完成！${NC}"
echo -e "${YELLOW}======================================================${NC}"
echo -e "1. MCP 核心代码已安装至: ${INSTALL_DIR}"
echo -e "2. 已向 OpenCode 配置中注入 'tuhu-wiki-fetcher'。"
echo -e "3. 已生成 'tuhucr' 技能模板。"
echo -e "   （由于 OpenCode 的技能加载机制可能不同，如果该工具不支持本地文件读取，"
echo -e "     你可以直接将 ~/.opencode/skills/tuhucr.md 的内容粘贴到 IDE 的全局 Prompt 中。）"
echo -e "4. 请重启你的 OpenCode / AI 助手以使配置生效。"
echo -e "5. 接下来，你可以直接对 AI 助手说：${BLUE}'执行 tuhucr，请 review 这个链接: https://...'${NC}"
echo -e "${YELLOW}======================================================${NC}"
