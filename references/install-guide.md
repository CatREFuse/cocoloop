# Skill 安装流程详细指南

这份文档描述 Cocoloop 在“拿到文件之前”和“拿到文件之后”分别怎么做。当前版本里，CLI 只负责已知安装流程 wrapper；搜索判断、fallback 和开放式探索由 Agent 负责。

当前默认安装策略：

1. 真实 skill 内容先写入 `~/.cocoloop/skills/<skill-name>/`
2. 再把目标平台目录发布成软链接
3. 只有当前平台确实不支持软链接时，才退回复制
4. 如果来源里存在多个 skill，先返回候选列表；只有用户或 Agent 明确指定后才继续安装

## 总流程

```text
开始
  ↓
识别输入类型
  ├── 直接文件 / URL
  ├── skill 名称
  ├── GitHub 链接 / 短链
  └── 平台页面 / 文章页
  ↓
检测当前 Agent 平台
  ↓
按已知流程下载文件，或交给 Agent 继续探索
  ↓
整理出包含 SKILL.md 的 skill 根目录
  ↓
按平台选择目标目录
  ↓
复制目录并校验
  ↓
完成
```

## 第一步：检测当前平台

安装前先判断当前任务更接近哪个 Agent 生态。
判断顺序：

1. 先看当前工作区里的平台信号
2. 再看项目配置文件
3. 最后才看 `HOME` 下的兼容目录

这样可以避免同一个 `HOME` 里存在多个 Agent 目录时互相串扰。

### Codex

优先信号：

- 仓库里已有 `.agents/skills/`
- 当前文档和配置明显使用 `AGENTS.md`、`agents/openai.yaml`
- 如果工作区没有更强信号，再看 `~/.agents/skills/`、`~/.codex/skills/`、`~/.codex/config.toml`

推荐安装目录：

- 项目级：`.agents/skills/<skill-name>/`
- 用户级：`~/.agents/skills/<skill-name>/`
- 兼容目录：`~/.codex/skills/<skill-name>/`

配置示范：

```toml
[[skills.config]]
path = "/Users/you/.agents/skills/cocoloop/SKILL.md"
enabled = false
```

### Claude Code

优先信号：

- 仓库里已有 `.claude/skills/`
- 当前工程使用 `CLAUDE.md` 或 `.claude/settings.json`
- 如果工作区没有更强信号，再看 `~/.claude/skills/` 或 `~/.claude/settings.json`

推荐安装目录：

- 项目级：`.claude/skills/<skill-name>/`
- 用户级：`~/.claude/skills/<skill-name>/`

说明：

- Claude Code 的 skill 发现主要依赖目录，不需要额外维护 skill 注册表。
- 如果团队还要共享额外行为，再配合 `.claude/settings.json`。

### OpenClaw

优先信号：

- 仓库里已有 `skills/` 或 `.agents/skills/`
- 当前工程使用 `.openclaw/openclaw.json`
- 如果工作区没有更强信号，再看 `~/.openclaw/skills/`、`~/.agents/skills/`、`~/.openclaw/openclaw.json`

推荐安装目录：

- 项目级：`skills/<skill-name>/` 或 `.agents/skills/<skill-name>/`
- 用户级：`~/.agents/skills/<skill-name>/` 或 `~/.openclaw/skills/<skill-name>/`

配置示范：

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

### Molili

优先信号：

- 工作目录存在 `.molili/workspaces/default/active_skills/`
- 如果工作区没有更强信号，再看 `~/.molili/workspaces/default/active_skills/`

推荐安装目录：

- 用户级：macOS / Linux 使用 `~/.molili/workspaces/default/active_skills/<skill-name>/`
- Windows 使用 `\\.molili\\workspaces\\default\\active_skills\\<skill-name>\\`

说明：

- Molili 当前没有单独的项目级 skill 目录。
- 已知安装动作就是把 skill 目录移动到 `active_skills`。
- 这一步可以直接用 Bash 完成。

### OpenCode

优先信号：

- 仓库里已有 `.opencode/skills/`
- 项目根存在 `opencode.json` 或 `opencode.jsonc`
- 环境变量存在 `OPENCODE_CONFIG_DIR` 或 `OPENCODE_CONFIG`
- 用户目录存在 `~/.config/opencode/skills/`

推荐安装目录：

- 项目级：`.opencode/skills/<skill-name>/`
- 用户级：`~/.config/opencode/skills/<skill-name>/`

说明：

- OpenCode 也会兼容发现 `.claude/skills/` 和 `.agents/skills/`
- 但当前 Cocoloop 在 OpenCode 环境下优先写 OpenCode 自己的目录

### 目录选择规则

1. 用户说“给当前项目装”时，写项目级目录。
2. 用户说“以后所有项目都能用”时，写用户级目录。
3. 如果仓库已经有既定结构，优先沿用现有目录风格。
4. 如果来源平台自带安装器，先判断它能否装到当前 Agent 真的会读取的位置。
5. 如果来源里存在多个 skill，先列出候选，不自动替用户选。

补充说明：

1. 如果当前平台不在已知支持列表，CLI 不继续猜，直接 `handoff-to-agent`
2. 如果来源不属于已知安装流，CLI 也不继续猜，直接 `handoff-to-agent`
3. Agent 接管后，要先确认这个环境的正确安装目录和正确验证方式，再继续安装

## 第二步：按来源拿到文件

### A. 直接 URL 或本地文件

处理顺序：

1. 用 `curl -L` 下载，或读取本地路径
2. 识别文件类型
3. 如果是 zip / tar.gz，解压到临时目录
4. 查找包含 `SKILL.md` 的根目录

建议命令：

```bash
curl -L -o /tmp/cocoloop-skill.zip "https://example.com/skill.zip"
```

### B. Skill 名称

处理顺序固定：

1. 先用 CocoLoop API 搜
2. 如果官方是模糊命中或返回多个候选，CLI 在这里返回 `review-required`
3. 只有用户或 Agent 明确指定目标 skill，才继续安装
4. 如果官方没有明确命中，CLI 在这里停住
5. 后续由 Agent 继续 ClawHub、skills.sh、GitHub 和公开网页探索

#### 1. CocoLoop API

示例：

```bash
curl -L "https://api.cocoloop.cn/api/v1/store/skills?page=1&page_size=10&keyword=${KEYWORD}&sort=downloads"
```

预期结果：

- skill 文件下载地址
- 仓库地址
- 版本、作者、描述等元数据

如果有多个结果，先展示候选，再由 Agent 判断或让用户确认。当前可以用精确 skill 名重试安装。

#### 2. ClawHub

这里开始已经不是 CLI 自动编排范围，而是 Agent 探索范围。

优先尝试：

```bash
npx clawhub@latest install <skill-name>
```

如果命令成功：

1. 确认它把 skill 装到了哪里
2. 判断该目录是否被当前 Agent 平台读取
3. 如果目录兼容，直接汇报结果
4. 如果目录不兼容，重新提取文件并手动安装到正确位置

#### 3. skills.sh

优先尝试：

```bash
npx skills add https://github.com/owner/repo --skill <skill-name>
```

处理原则：

- 如果 skills.sh 已经给出仓库地址或下载地址，优先拿文件
- 如果它直接完成安装，继续核对真实写入目录
- 如果它只兼容某个社区目录，也要向用户说明兼容路径和真实落点

#### 4. GitHub

搜索方向：

- 仓库名包含查询词
- 仓库中存在 `SKILL.md`
- 优先组织账号、近期更新、stars 更高的结果

下载方式：

1. 仓库根目录就是 skill 根目录时，可以直接交给 `install`
2. 如果仓库里有多个 skill，CLI 会先返回 `review-required` 和候选列表
3. 只有用户或 Agent 明确指定 `--skills` 或 `--all`，才继续安装
4. 如果需要继续判断子目录、分支或额外结构，由 Agent 继续探索
5. 当 source 已经明确，再进入统一安装流程

#### 5. 自由探索

当上面都失败时：

1. 搜索公开网页、发布页、文档站
2. 沿着下载按钮、release 资产、源码链接继续追
3. 只要拿到 zip、仓库或 skill 目录，就回到统一安装流程

这里的页面解析、链接追踪和结果判断都由 Agent 完成，不由 CLI 自动完成。

## 第三步：标准化 skill 目录

无论文件从哪里来，都整理成一个统一的 skill 根目录。

如果来源中发现多个 `SKILL.md`：

1. 默认不自动挑一个
2. 先返回候选 skill 名和路径
3. 用户或 Agent 可重试：
   - `cocoloop install SOURCE --skills skill-a,skill-b`
   - `cocoloop install SOURCE --all`

### 根目录必须满足

```text
skill-name/
├── SKILL.md
├── scripts/        可选
├── references/     可选
├── assets/         可选
└── agents/         可选
```

### 标准化步骤

1. 找到第一个包含 `SKILL.md` 的目录
2. 读取 frontmatter
3. 优先使用 frontmatter 里的 `name`
4. 如果缺少 `name`，退回目录名
5. 清理无关构建产物，但不要误删脚本和资源

## 第四步：写入目标目录

### 手动落盘安装

推荐做法：

1. 先写临时目录
2. 再把 skill 内容落到 `~/.cocoloop/skills/<skill-name>/`
3. 默认把目标平台目录发布成软链接
4. 平台不支持软链接时，再复制到目标目录
5. 覆盖前提醒用户

目标路径示例：

```text
.agents/skills/cocoloop/
.claude/skills/cocoloop/
~/.openclaw/skills/cocoloop/
~/.molili/workspaces/default/active_skills/cocoloop/
~/.config/opencode/skills/cocoloop/
```

### 保留目录结构

复制时不要只拿 `SKILL.md`。如果来源里还有下面这些目录，也要一起保留：

- `scripts/`
- `references/`
- `assets/`
- `agents/`

### 覆盖与更新

如果目标目录已存在：

1. 安装请求：先确认是否覆盖
2. 更新请求：默认按覆盖处理
3. 如有需要，先创建备份目录

## 第五步：安装后校验

安装结束后至少检查三件事：

1. 目标目录存在
2. `SKILL.md` 可读
3. 关键资源目录没有丢失

按平台补充提示：

- Codex：如技能没有立刻出现，提醒用户刷新或重启 Codex
- Claude Code：如技能没有出现，提醒用户确认目录范围是项目级还是用户级
- OpenClaw：如技能没有出现，提醒用户检查 `openclaw.json` 的额外扫描目录
- Molili：如技能没有出现，提醒用户检查 `active_skills` 目录是否为当前 workspace 正在读取的目录
- OpenCode：如技能没有出现，提醒用户运行 `opencode debug skill` 检查是否被发现

安装完成后，要提醒用户立刻做一次真实调用测试，而不是只看目录存在。

## 异常处理

| 场景 | 处理方式 |
| --- | --- |
| URL 失效 | 提示用户检查链接，或继续尝试其他来源 |
| 压缩包里找不到 `SKILL.md` | 视为无效安装包，继续 fallback |
| 原生安装器成功但路径不兼容 | 补做一次手动安装到正确目录 |
| 目标目录无写权限 | 改用用户级目录，或提示用户切换安装范围 |
| 同名 skill 已存在 | 显示现有路径，询问覆盖还是改名 |
| 环境不是已知平台 | CLI 直接 `handoff-to-agent` |
| 来源不属于已知安装流 | CLI 直接 `handoff-to-agent` |

## 推荐汇报格式

安装完成后，建议输出这些信息：

```text
安装成功
Skill: cocoloop
来源: CocoLoop / ClawHub / skills.sh / GitHub / 自由探索
平台: Codex / Claude Code / OpenClaw
真实安装路径: /absolute/path/to/skill
兼容说明: 是否同时写入兼容目录，是否需要刷新客户端
```
