# Cocoloop

一个更快、更稳、更偏安全的 Skill 管理器，用来搜索、下载、安装、更新、卸载和检查 Skills。

## 当前命令

- `cocoloop search --query <关键词>`：搜索官方商店和本地已知 Agent 目录
- `cocoloop featured`：读取主站当前精选推荐技能
- `cocoloop featured --categories`：读取主站当前精选推荐分类
- `cocoloop featured --category "<分类>"`：读取指定分类下的精选推荐技能
- `cocoloop inspect <skill>`：查看技能详情
- `cocoloop install <skill-or-source>`：安装技能
- `cocoloop update <skill>`：更新技能
- `cocoloop uninstall <skill>`：卸载技能

## 它解决什么问题

很多 Skill 安装流程停在“找到仓库”这一步。Cocoloop 继续往下做两件事：

1. 先从合适的来源把 skill 文件拿回来。
2. 再按当前 Agent 平台写到真正会被读取的目录里。

## 当前安装逻辑

### 搜索顺序

1. CocoLoop 搜索 API
2. ClawHub
3. skills.sh
4. GitHub
5. 自由探索

只要拿到 skill 文件、压缩包或仓库目录，就统一进入同一套安装流程。

### 统一安装流程

1. 识别当前 Agent 平台
2. 获取 skill 文件或 skill 目录
3. 标准化成包含 `SKILL.md` 的根目录
4. 按平台选择目标目录
5. 复制并保留 `scripts/`、`references/`、`assets/`、`agents/`
6. 校验安装结果

## 支持的平台

| 平台 | 项目级目录 | 用户级目录 | 兼容目录 |
| --- | --- | --- | --- |
| Codex | `.agents/skills/` | `~/.agents/skills/` | `~/.codex/skills/` |
| Claude Code | `.claude/skills/` | `~/.claude/skills/` | 无 |
| OpenClaw | `skills/` 或 `.agents/skills/` | `~/.agents/skills/` 或 `~/.openclaw/skills/` | `~/.openclaw/skills/` |

## 平台配置示范

### Codex

```toml
[[skills.config]]
path = "/Users/you/.agents/skills/cocoloop/SKILL.md"
enabled = false
```

### OpenClaw

```json
{
  "skills": {
    "load": {
      "extraDirs": [
        "/Users/you/.agents/skills",
        "/Users/you/.openclaw/skills"
      ]
    }
  }
}
```

Claude Code 的 skill 发现主要依赖目录本身，常见做法是直接写入 `.claude/skills/` 或 `~/.claude/skills/`，需要共享额外设置时再配合 `.claude/settings.json`。

## 搜索来源示范

### CocoLoop API

```bash
curl -L "https://api.cocoloop.com/api/v1/store/skills?page=1&page_size=10&keyword=rsshub&sort=downloads"
```

### 主站精选推荐

```bash
bash scripts/cocoloop.sh featured
bash scripts/cocoloop.sh featured --categories
bash scripts/cocoloop.sh featured --category "技术开发"
```

这个入口只负责读取主站最新精选推荐、分类列表和指定分类下的精选技能。后续是否查看详情、比较候选或继续安装，仍由 Agent 决定。

### ClawHub

```bash
npx clawhub@latest install rsshub
```

### skills.sh

```bash
npx skills add https://github.com/owner/repo --skill rsshub
```

这些原生命令只在它们和当前 Agent 平台兼容时优先使用。否则还是回到 Cocoloop 的标准化落盘流程。

## 启动自检

Cocoloop 会在每天第一次启动时静默执行一次升级检查。

如果当前已经有更新版本，CLI 会在正常输出前提示最新版本和下载地址。
如果当天已经检查过，或者当前没有更新，就不额外打扰。

## 安全检查

Cocoloop 集成了 CLS 风格的安全检查流程，评级标准为 `S+ / S / A / B / C / D`。

重点检查：

- 危险代码执行
- 敏感信息处理
- 动态下载与动态执行
- 多层 URL 加载
- 来源可信度

## 文档

- [Skill 定义文件](SKILL.md)
- [安装流程指南](references/install-guide.md)
- [搜索流程指南](references/search-guide.md)
- [卸载流程指南](references/uninstall-guide.md)
- [安全检查流程指南](references/safety-check-guide.md)
- [Cocoloop Safe Check 标准](references/cocoloop-safe-check.md)
