---
name: cocoloop
version: 0.5
description: 一个更快速、更安全的 Skill 管理器。CLI 只负责网络 API wrapper 和已知安装流程 wrapper；搜索判断、fallback 探索和复杂编排由 Agent 自己完成。
---

# Cocoloop Skill 管理器

Cocoloop 的目标很直接：先找到 skill 文件，再把它安装到当前 Agent 平台真正会读取的位置。搜索和安装是两段流程，来源可以变，落盘和校验流程保持一致。

## 核心原则

1. 先识别当前 Agent 平台，再决定安装目录和安装方式。
2. 搜索优先级固定为 `CocoLoop API -> ClawHub -> skills.sh -> GitHub -> 自由探索`。
3. 只要拿到 skill 文件或 skill 目录，就统一进入“标准化 -> 安装 -> 校验”流程。
4. 尽量保留原始目录结构：`SKILL.md`、`scripts/`、`references/`、`assets/`、`agents/`。
5. 来源越陌生，越要主动提醒用户执行 CLS 安全检查。
6. 默认先把 skill 内容安装到 `~/.cocoloop/skills/`，再通过软链接发布到目标平台目录；只有当前平台确实不支持软链接时，才退回复制。

## CLI 与 Agent 的分工

先把边界守住，再开始安装。

### CLI 只做两类事

1. 网络 API wrapper
2. 已知安装流程 wrapper

当前可以直接信任 CLI 的动作：

- `cocoloop search --query ...`
- `cocoloop featured`
- `cocoloop featured --categories`
- `cocoloop featured --category ...`
- `cocoloop inspect ...`
- `cocoloop paths`
- `cocoloop healthcheck`
- `cocoloop safescan ...`
- `cocoloop install ...`
- `cocoloop uninstall ...`
- `cocoloop update ...`

### Agent 负责粘合

下面这些都不要交给 CLI 自己做判断：

1. 搜索结果里哪一个才是用户真正想装的 skill
2. 官方没命中后要不要继续 fallback
3. 页面链接、GitHub 子目录、说明页、文章页该怎么继续追 source
4. 已知安装流程失败后怎么改走手工探索
5. 什么时候该让用户确认，什么时候可以直接继续
6. 当前环境不在已知平台名单里时，如何先确认正确安装方式和正确配置方法

### 推荐执行顺序

1. 先用 `search` 一次性读取官方结果和本地已知 Agent 结果
2. 如果本地已知 Agent 已经存在候选，先询问用户是否要移植到当前环境
3. 如果返回 `review-required` 或 `no-results`，由 Agent 判断或询问用户
4. 当 Agent 已经拿到明确 source，再决定要不要调用 `install`
5. 如果 `install` 返回 `handoff-to-agent`，说明 CLI 不该继续猜，Agent 需要自己完成后续探索和安装
6. 安装完成后，提醒用户立即测试 skill 是否能被当前 Agent 正确发现和调用

### 首次安装 Cocoloop 后的下一步引导

如果刚刚安装完成的是 `cocoloop` 自己，而且用户看起来是第一次在当前 Agent 环境里安装或启用 Cocoloop，不要只停在“请测试是否可用”。

这时追加一步轻量询问：

- 先提醒用户做一次实际调用测试
- 再询问用户现在要不要看主站热门 skill 推荐

推荐问法：

`如果你愿意，我也可以现在顺手给你看一组主站热门 skill 推荐，帮你继续补齐常用能力。`

如果用户同意，再调用：

- `bash scripts/cocoloop.sh featured`
- 需要分类时，再调用 `bash scripts/cocoloop.sh featured --categories`

如果用户暂时不需要，不继续主动展开推荐列表。

## 主站精选推荐路由

当用户意图是看主站当前推荐技能，而不是按名字搜索时，优先走独立精选入口：

- 用户想看“主站最新推荐 skill”“精选推荐”“首页推荐 skill”时，调用 `bash scripts/cocoloop.sh featured`
- 用户想看“推荐分类”“精选分类”时，调用 `bash scripts/cocoloop.sh featured --categories`
- 用户已经拿到分类名，还想继续看“这个分类下面有哪些精选 skill”时，调用 `bash scripts/cocoloop.sh featured --category "<分类>"`

这个入口只做官方接口 wrapper 和结果展示，不负责替用户做安装判断。需要继续查看详情、比较候选或安装时，再由 Agent 决定是否调用 `inspect`、`search` 或 `install`

## 平台检测与安装目的地

先判断当前环境更接近哪个 Agent 生态，再选择项目级安装或用户级安装。

| 平台 | 项目级目录 | 用户级目录 | 兼容目录 | 配置示范 |
| --- | --- | --- | --- | --- |
| OpenCode | `.opencode/skills/<skill-name>/` | `~/.config/opencode/skills/<skill-name>/` | `.claude/skills/<skill-name>/`、`.agents/skills/<skill-name>/` 也可被 OpenCode 发现 | `opencode.json` / `~/.config/opencode/opencode.json` |
| Codex | `.agents/skills/<skill-name>/` | `$HOME/.agents/skills/<skill-name>/` | `$HOME/.codex/skills/<skill-name>/` | `~/.codex/config.toml` |
| Claude Code | `.claude/skills/<skill-name>/` | `~/.claude/skills/<skill-name>/` | 无必需兼容目录 | `~/.claude/settings.json` / `.claude/settings.json` |
| OpenClaw | `skills/<skill-name>/` 或 `.agents/skills/<skill-name>/` | `~/.agents/skills/<skill-name>/` 或 `~/.openclaw/skills/<skill-name>/` | `~/.openclaw/skills/<skill-name>/` | `~/.openclaw/openclaw.json` |
| Molili | 无独立项目级目录，直接使用用户级 active skills 目录 | macOS/Linux: `~/.molili/workspaces/default/active_skills/<skill-name>/`；Windows: `\\.molili\\workspaces\\default\\active_skills\\<skill-name>\\` | 无额外兼容目录 | 以 `active_skills` 目录为准 |

安装选择规则：

1. 用户明确要求“当前仓库可用”或“团队共享”时，优先装到项目级目录。
2. 用户明确要求“全局可用”或“所有项目都能用”时，优先装到用户级目录。
3. 如果来源平台自带原生安装器，而且安装目标与当前 Agent 兼容，可以优先使用原生命令。
4. 如果原生安装器不兼容或无法确认落点，回退到手动落盘安装。

统一实现规则：

1. 真实 skill 内容默认先写入 `~/.cocoloop/skills/<skill-name>/`
2. 目标平台目录默认放软链接
3. 当前平台确实不支持软链接时，才直接复制到目标平台目录

Molili 例外说明：

1. Molili 当前按用户级目录安装
2. 安装动作就是把 skill 目录移动到 `active_skills` 目录
3. 这一步可以直接用 Bash 完成，不需要额外注册

## 单个 Skill 安装流程

用户输入通常分成四类：

### 1. 直接文件或 URL

输入示例：

- `https://example.com/skill.zip`
- `https://example.com/downloads/cocoloop.skill`
- `/tmp/my-skill/`

处理步骤：

1. 用 `curl -L` 或等价方式下载文件，或直接读取本地目录。
2. 如果是压缩包，解压到临时目录。
3. 自动寻找包含 `SKILL.md` 的 skill 根目录。
4. 读取 frontmatter，确定 `name`、`description` 和可选 `version`。
5. 进入“统一安装步骤”。

### 2. Skill 名称搜索

输入示例：

- `pdf`
- `rsshub`
- `github-trending`

处理步骤：

1. 先调用 CocoLoop search API 搜索。
2. 如果 CocoLoop 没找到，CLI 到这里先停住。
3. 接下来由 Agent 按 ClawHub、skills.sh、GitHub、公开网页的顺序继续找 source。
4. 一旦 Agent 拿到明确 skill 文件、压缩包或仓库目录，再进入“统一安装步骤”。

### 3. GitHub 仓库链接或短链

输入示例：

- `owner/repo`
- `https://github.com/owner/repo`
- `https://github.com/owner/repo/tree/main/skills/foo`

处理步骤：

1. 获取仓库信息，确认是否存在 `SKILL.md`。
2. 如果仓库根目录就是 skill 根目录，可以交给 `install` 处理。
3. 如果需要继续判断子目录、分支或额外文件结构，交给 Agent 探索。
4. 当 source 已经清晰，再进入“统一安装步骤”。

### 4. 平台页面或文章页

输入示例：

- `https://skills.sh/...`
- `https://clawhub.ai/...`
- 某篇博客、说明页、发布页

处理步骤：

1. 先判断页面里是否直接给出安装命令、下载链接或仓库地址。
2. 页面解析、按钮跟踪、release 资产定位都由 Agent 完成。
3. CLI 不负责解析说明页或文章页。
4. Agent 拿到明确文件后，再进入“统一安装步骤”。

## 未识别环境处理

如果当前环境没有命中已知平台，不要先安装。

正确做法：

1. 先根据当前 Agent 环境去探索正确的 skill 安装目录和发现机制
2. 再确认这个环境如何判断“skill 已被正确配置”
3. 只有弄清楚正确安装方式和正确配置方法后，再继续安装
4. 安装完成后，提醒用户立刻做一次实际调用测试

## 搜索优先级

### 第一优先级：CocoLoop API

名称搜索时先查 CocoLoop。优先使用命令行 HTTP 请求工具，例如：

```bash
curl -L "https://api.cocoloop.com/api/v1/store/skills?page=1&page_size=10&keyword=${KEYWORD}&sort=downloads"
```

预期目标：

- 拿到官方候选列表
- 把搜索结果交给 Agent 判断
- 如果返回多个候选，让 Agent 或用户先确认，再继续

### 第二优先级：ClawHub、skills.sh、GitHub

如果 CocoLoop 搜不到，按下面顺序继续：

1. ClawHub
2. skills.sh
3. GitHub

这里的继续探索由 Agent 执行，不由 CLI 直接编排。

每个来源都遵守同一个原则：

- 能直接拿到 skill 文件，就下载文件
- 能直接拿到仓库，就下载仓库
- 能直接调用平台原生安装器，并且安装结果与当前 Agent 平台兼容，就优先用原生命令
- 如果原生命令不可用，退回手动落盘安装

### 第三优先级：自由探索

如果前面都失败，就继续探索公开网页、发布页、文档站和搜索结果。

自由探索的目标不是“找到一个网页”，而是“拿到一个可安装的 skill 目录或压缩包”。这一步由 Agent 完成。只要拿到文件，就回到统一安装流程。

## 统一安装步骤

所有来源最终都要走下面这套流程：

1. 在临时目录中整理出 skill 根目录。
2. 确认根目录包含 `SKILL.md`。
3. 保留并复制同级资源目录：`scripts/`、`references/`、`assets/`、`agents/`。
4. 按当前平台选择目标目录。
5. 如果目标目录已存在：
   - 安装请求：覆盖前提醒用户
   - 更新请求：视为就地更新
6. 复制 skill 目录到目标路径。
7. 进行一次安装后校验：
   - 目标目录存在
   - `SKILL.md` 可读
   - 关键资源目录没有丢失
8. 需要时提醒用户重启或刷新当前 Agent。

## 平台安装示范

### Codex

推荐落点：

- 仓库共享：`.agents/skills/<skill-name>/`
- 用户全局：`$HOME/.agents/skills/<skill-name>/`
- 兼容社区安装器：`$HOME/.codex/skills/<skill-name>/`

禁用某个 skill 的配置示范：

```toml
[[skills.config]]
path = "/Users/you/.agents/skills/cocoloop/SKILL.md"
enabled = false
```

说明：

- 官方文档当前主推 `.agents/skills`。
- 如果来源是 `skills.sh` 一类社区安装器，可能仍会把全局 skill 放到 `~/.codex/skills/`。
- 当两套目录同时存在时，应优先告诉用户真实写入位置。

### Claude Code

推荐落点：

- 仓库共享：`.claude/skills/<skill-name>/`
- 用户全局：`~/.claude/skills/<skill-name>/`

配置说明：

- Claude Code 的 skill 发现主要依赖目录本身，不需要额外登记一个 skill 清单。
- 如果用户还要同步团队级设置，再写 `.claude/settings.json`。
- 如果只想本地生效，使用 `~/.claude/skills/` 或 `.claude/settings.local.json` 相关配置。

### OpenClaw

推荐落点：

- 仓库共享：`skills/<skill-name>/` 或 `.agents/skills/<skill-name>/`
- 用户全局：`~/.agents/skills/<skill-name>/` 或 `~/.openclaw/skills/<skill-name>/`

常见配置示范：

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

说明：

- OpenClaw 环境常见多目录并存。
- 如果项目里已经有 `skills/` 或 `.agents/skills/`，优先复用现有结构。
- 如果用户想把多个个人 skill 统一托管，优先使用用户级目录，再通过配置补充额外扫描路径。

## 平台原生安装器示范

这些命令只能作为优先尝试项，执行前仍要判断它们是否真的适合当前 Agent 平台。

### ClawHub

如果当前环境已经依赖 ClawHub 工作流，可以优先尝试：

```bash
npx clawhub@latest install <skill-name>
```

如果命令成功，但无法确认安装到了哪里，要继续检查真实落点，再向用户汇报。

### skills.sh

如果 skills.sh 页面已经给出明确仓库和 skill 名称，可以优先尝试：

```bash
npx skills add https://github.com/owner/repo --skill <skill-name>
```

如果 skills.sh 把 skill 安装到了社区兼容目录，也要在结果里明确写出真实路径。

## 批量安装

批量安装时，把每个 skill 当成独立任务执行：

1. 逐个搜索
2. 逐个获取文件
3. 逐个安装
4. 汇总结果

一个 skill 失败，不影响其他 skill 继续安装。

## 更新与卸载

### 更新

1. 先找到当前 skill 的真实安装目录。
2. 再走一次同名 skill 搜索与获取文件流程。
3. 用统一安装步骤覆盖已有目录。
4. 保留旧目录备份是加分项，不是必须项。

### 卸载

详见 [references/uninstall-guide.md](references/uninstall-guide.md)。

关键点：

1. 先在当前平台的全部候选目录中定位 skill。
2. 删除真正安装的那一份。
3. 如果有额外配置引用了该路径，也要提醒用户同步清理。

## 安全检查

详见 [references/safety-check-guide.md](references/safety-check-guide.md) 和 [references/cocoloop-safe-check.md](references/cocoloop-safe-check.md)。

安装类任务里建议这样做：

1. T1/T2 来源：默认提示可选检查
2. T3 或自由探索来源：默认建议先检查再安装
3. 如果发现动态代码加载、多层网络执行或高危命令，优先阻断并说明原因

## 资源引用

- [安装流程详细指南](references/install-guide.md)
- [搜索流程详细指南](references/search-guide.md)
- [卸载流程详细指南](references/uninstall-guide.md)
- [安全检查流程指南](references/safety-check-guide.md)
- [Cocoloop Safe Check 安全检查标准](references/cocoloop-safe-check.md)
