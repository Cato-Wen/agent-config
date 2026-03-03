# Agent Config

OpenCode AI agent 配置仓库，用于 Wonder 单体仓库的需求分析和代码定位工作流。

## 目录结构

```
.opencode/
├── opencode.json                          # 主配置文件 (MCP 等)
├── agents/
│   └── analyst-agent.md                   # 分析师 Agent
└── skills/
    └── wonder-analyzer/
        ├── SKILL.md                       # 需求分析 Skill
        └── glossary.md                    # 业务术语表
```

## 快速开始

**Windows (PowerShell)：**
```powershell
.\setup.ps1
```

**macOS / Linux：**
```bash
bash setup.sh
```

脚本会引导你完成环境变量配置和 `.opencode` 目录部署。

## 1. 环境变量配置

本项目通过 Google Vertex AI 使用 Claude 模型。使用前需配置以下环境变量：

| 变量 | 说明 | 必填 |
|------|------|------|
| `GOOGLE_CLOUD_PROJECT` | Google Cloud 项目 ID | 是 |
| `GOOGLE_APPLICATION_CREDENTIALS` | 服务账号 JSON 密钥文件路径 | 二选一 |
| `VERTEX_LOCATION` | Vertex AI 区域，默认 `global` | 否 |

**认证方式** (二选一)：
- 设置 `GOOGLE_APPLICATION_CREDENTIALS` 指向服务账号密钥文件
- 使用 gcloud CLI 认证：`gcloud auth application-default login`

**配置示例：**

```bash
# 方式一：环境变量启动
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
GOOGLE_CLOUD_PROJECT=your-project-id \
opencode

# 方式二：写入 shell 配置 (~/.bashrc 或 ~/.zshrc)
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
export GOOGLE_CLOUD_PROJECT=your-project-id
export VERTEX_LOCATION=global
```

## 2. Agent 配置

Agent 定义文件位于 `.opencode/agents/` 目录。


## 3. Skill 配置

Skill 定义文件位于 `.opencode/skills/` 目录。

## 4. MCP 配置

MCP (Model Context Protocol) 服务器配置在 `.opencode/opencode.json` 中。
