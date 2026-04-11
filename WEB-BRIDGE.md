# Claw Code + Web-Bridge: 免费使用浏览器大模型

基于 [claw-code](https://github.com/ultraworkers/claw-code) 改造，内置 Web-Bridge 模块，通过浏览器登录凭证直接调用网页版大模型，**无需 API Key，零 Token 费用**。

## 支持的模型

| 提供商 | 模型 ID | 网页地址 |
|--------|---------|----------|
| **DeepSeek** | `deepseek/deepseek-chat`, `deepseek/deepseek-reasoner` | chat.deepseek.com |
| **ChatGPT** | `chatgpt/gpt-4o`, `chatgpt/o3`, `chatgpt/o3-mini` | chatgpt.com |
| **Gemini** | `gemini/gemini-pro`, `gemini/gemini-ultra` | gemini.google.com |
| **Qwen** | `qwen/qwen-max`, `qwen/qwen-plus`, `qwen/qwen-turbo` | tongyi.aliyun.com |
| **Kimi** | `kimi/kimi-chat`, `kimi/kimi-128k` | kimi.moonshot.cn |

## 快速开始

### 1. 构建

```bash
cd rust
cargo build --release
```

### 2. 启动 Chrome 调试模式

```bash
# 终端 1：启动 Chrome
./scripts/web-chrome.sh
```

在打开的 Chrome 中登录你要使用的 AI 网站（如 chat.deepseek.com）。

### 3. 捕获凭证

```bash
# 终端 2：捕获登录凭证
./scripts/web-login.sh deepseek

# 或手动输入 cookies（从浏览器 DevTools 复制）
./scripts/web-login.sh deepseek --cookies "ds_session=abc123; token=xyz"

# 或直接提供 bearer token
./scripts/web-login.sh deepseek --token "eyJhbGciOi..."
```

### 4. 使用

```bash
# 使用 DeepSeek
claw --model deepseek/deepseek-chat

# 使用 DeepSeek R1 推理模型
claw --model deepseek/deepseek-reasoner

# 使用 ChatGPT
claw --model chatgpt/gpt-4o

# 使用 Gemini
claw --model gemini/gemini-pro

# 使用 Qwen
claw --model qwen/qwen-max

# 使用 Kimi
claw --model kimi/kimi-chat
```

## 工作原理

```
用户输入 → claw CLI → 检测到 web 模型
                          ↓
                    自动启动 Web-Bridge 网关 (localhost:18899)
                          ↓
                    从 ~/.claw/web-credentials.json 加载凭证
                          ↓
                    构造网页版 API 请求（带 Cookie/Token）
                          ↓
                    发送到网页版 AI 服务（如 chat.deepseek.com/api/...）
                          ↓
                    SSE 流式响应 → 转换为 OpenAI 兼容格式 → 返回 claw CLI
```

### 架构

```
rust/crates/
├── api/                    # 原有 API 抽象层
│   └── src/providers/
│       ├── anthropic.rs    # Anthropic API（付费）
│       ├── openai_compat.rs # OpenAI 兼容（付费）
│       └── web.rs          # [新增] Web provider 路由
├── web-bridge/             # [新增] 浏览器凭证代理
│   └── src/
│       ├── browser.rs      # Chrome CDP 集成
│       ├── credential_store.rs # 凭证存储
│       ├── gateway.rs      # 内置 OpenAI 兼容网关
│       └── providers/      # 各网页版 AI 适配器
│           ├── deepseek.rs
│           ├── chatgpt.rs
│           ├── gemini.rs
│           ├── qwen.rs
│           └── kimi.rs
├── runtime/                # 原有运行时
├── commands/               # 原有命令层
└── ...
scripts/
├── web-chrome.sh           # 启动 Chrome 调试模式
└── web-login.sh            # 凭证捕获脚本
```

## 凭证管理

凭证存储在 `~/.claw/web-credentials.json`：

```json
{
  "credentials": {
    "deepseek": {
      "provider": "deepseek",
      "cookies": [{"name": "...", "value": "...", "domain": "chat.deepseek.com"}],
      "bearer_token": "...",
      "user_agent": "...",
      "captured_at": 1712800000
    }
  }
}
```

### 手动设置凭证

如果自动捕获不可用，可以从浏览器开发者工具手动复制：

1. 打开 AI 网站并登录
2. 按 F12 打开 DevTools
3. 进入 Network 标签
4. 发送一条消息
5. 找到 API 请求，复制 Cookie 和 Authorization 头
6. 运行：
```bash
./scripts/web-login.sh deepseek \
    --cookies "ds_session=...; token=..." \
    --token "Bearer eyJ..."
```

## 注意事项

- 凭证存储在本地 `~/.claw/` 目录，不会上传到任何外部服务
- 浏览器凭证可能会过期，需要重新登录并捕获
- Web 模型不支持原生 function calling，工具调用通过 prompt 注入实现
- 网页版 AI 可能有使用频率限制
- 此方案仅供个人学习使用

## 与原版 claw-code 的兼容性

所有原版功能保持不变：
- `ANTHROPIC_API_KEY` — 仍然可以使用 Anthropic 付费 API
- `OPENAI_API_KEY` — 仍然可以使用 OpenAI 付费 API
- `XAI_API_KEY` — 仍然可以使用 xAI
- `DASHSCOPE_API_KEY` — 仍然可以使用 DashScope

Web-Bridge 是额外新增的，不影响原有功能。
