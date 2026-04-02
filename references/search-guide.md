# Skill 搜索流程详细指南

这份文档只关心一件事：怎样更稳定地拿到一个可安装的 skill 文件。当前版本里，CLI 会并行执行官方搜索和本地已知 Agent 目录搜索；后续多源探索和候选判断由 Agent 负责。

## 搜索优先级

1. CocoLoop API
2. ClawHub
3. skills.sh
4. GitHub
5. 自由探索

同一轮搜索里，CLI 会把官方结果和本地已知 Agent 结果一起汇总。
如果返回的是候选集合，CLI 负责展示，Agent 或用户负责决定下一步。
如果本地已知 Agent 里已经有同名或相近 Skill，CLI 会提示用户是否移植。

## 搜索输入标准化

开始搜索前，先把输入归类：

- 纯名称：`rsshub`
- 带空格的自然语言：`github trending`
- GitHub 短链：`owner/repo`
- URL：`https://...`

标准化规则：

1. 去掉两端空格
2. 保留原始大小写用于展示，搜索时可补一份小写关键词
3. 如果像 `owner/repo`，优先按 GitHub 入口处理
4. 如果已经是 URL，优先交给安装流或 Agent 页面探索，不再做名称搜索
5. 如果最终得到多个候选，默认不自动替用户挑选

## 第一层：CocoLoop API

### 目标

优先从 CocoLoop 拿到：

- skill 文件 URL
- 仓库 URL
- 版本、作者、描述、评分、下载量

### 示例请求

```bash
curl -L "https://api.cocoloop.cn/api/v1/store/skills?page=1&page_size=10&keyword=${KEYWORD}&sort=downloads"
```

### 建议响应归一化

```json
{
  "name": "skill-name",
  "description": "Skill description",
  "version": "1.0.0",
  "author": "author-name",
  "download_url": "https://...",
  "repo_url": "https://github.com/owner/repo",
  "source": "cocoloop"
}
```

### 命中后怎么做

1. CLI 输出官方结果
2. 如果官方或本地任一侧有结果，返回 `STATUS: review-required`
3. 如果两侧都没有结果，返回 `STATUS: no-results`
4. 如果是模糊搜索，Agent 或用户需要从候选里选出目标
5. 如果本地已知 Agent 里已有候选，先确认是否移植
6. 两种情况都默认交给 Agent 判断，或让用户确认下一步

## 并行的本地已知 Agent 搜索

### 目标

在官方搜索的同时，扫描本机已知 Agent 的 Skill 目录，看看是否已经存在可移植的 Skill。

### 扫描范围

- `.opencode/skills`
- `~/.config/opencode/skills`
- `.agents/skills`
- `~/.agents/skills`
- `.claude/skills`
- `~/.claude/skills`
- `skills`
- `~/.openclaw/skills`
- `~/.molili/workspaces/default/active_skills`

### 命中后怎么做

1. CLI 输出本地候选
2. CLI 标记 `LOCAL_MIGRATION_AVAILABLE: yes`
3. Agent 或用户确认是否把本地 Skill 移植到当前环境
4. 没有确认前，不直接执行移植

## 第二层：ClawHub

### 目标

优先利用 ClawHub 的已有分发能力，但不要把“命令执行成功”当成搜索结束。只有确认真实安装结果或拿到文件，才算完成。

这一层开始已经属于 Agent 探索范围，不是 `cocoloop search` 的职责。

### 可选原生命令

```bash
npx clawhub@latest install <skill-name>
```

### 处理原则

1. 原生命令成功后，继续检查写入目录
2. 如果写入目录兼容当前 Agent 平台，直接记录结果
3. 如果不兼容，继续定位它下载的实际文件，再做手动安装
4. 如果原生命令失败，再进入下一层

## 第三层：skills.sh

### 目标

把 skills.sh 当作“线索源”和“兼容安装器”两种能力来用：

- 找仓库
- 找 skill 名称
- 找下载或安装命令

### 常见命令示范

```bash
npx skills add https://github.com/owner/repo --skill <skill-name>
```

### 处理原则

1. 如果 skills.sh 页面给出仓库地址，优先拿仓库
2. 如果直接完成安装，继续核对真实安装路径
3. 如果它写入的是社区兼容目录，例如 `~/.codex/skills/`，要明确告诉用户

## 第四层：GitHub

### 搜索目标

优先寻找满足下面条件的仓库：

1. 包含 `SKILL.md`
2. 仓库名或描述和查询词相关
3. 最近仍有更新
4. 组织账号优先

### 搜索思路

```text
{query} SKILL.md
{query} "agents/openai.yaml"
{query} "skills"
```

### 下载策略

1. 仓库根目录就是 skill 根目录时，可以作为已知 source 交给 `install`
2. 仓库里有多个 skill 时，当前 `install` 会返回 `review-required`
3. 只有用户或 Agent 明确指定 `--skills` 或 `--all`，才继续安装
4. 下载后一定要确认根目录里有 `SKILL.md`

## 第五层：自由探索

当前四层都失败时，再进入自由探索。

### 可探索目标

- 官方文档站
- 博客文章
- 发布页
- release 资产
- 搜索引擎结果页

### 判定标准

只有拿到这些东西之一，才算探索成功：

- skill 目录
- 压缩包
- 仓库地址
- 可以验证真实落点的原生安装结果

这一层完全由 Agent 负责，CLI 不自动解析文章页、说明页或下载按钮。

## 结果去重与排序

来自不同来源的候选结果，按下面顺序排序：

1. CocoLoop 命中
2. 官方或组织账号来源
3. 近期更新
4. 下载量 / stars 更高
5. 描述更贴近查询词

去重规则：

1. 同一个 GitHub 仓库只保留一条主结果
2. CocoLoop 和 GitHub 指向同一仓库时，保留 CocoLoop 结果作为主入口
3. skills.sh 和 ClawHub 如果都只是转向同一仓库，保留更直接的文件来源

## 搜到之后的统一出口

无论搜索命中哪一层，最终都要把结果转成下面三种之一：

1. skill 目录
2. 压缩包
3. 已验证路径的原生安装结果

前两种进入手动安装流程，第三种进入安装后校验。

当前推荐执行顺序：

1. 先调用 `cocoloop search --query ...`
2. 一次性读取官方结果、本地已知 Agent 结果和状态字段
3. 如果本地已知 Agent 已有候选，先确认是否移植
4. 如果是官方候选集合，由 Agent 或用户先明确要装哪一个或哪几个
5. 由 Agent 选择是否继续 `inspect`
6. 由 Agent 决定是否继续 ClawHub、skills.sh、GitHub 或自由探索
7. 当 source 已明确，再调用 `install`

## 本地缓存

如果需要缓存搜索结果，建议写到：

```text
~/.cocoloop/cache/search.json
```

缓存建议字段：

```json
{
  "query": "rsshub",
  "source": "cocoloop",
  "timestamp": "2026-04-02T10:00:00Z",
  "results": []
}
```

缓存只用来提速，不替代实时搜索。用户明确要求最新结果时，应绕过缓存。

## 错误处理

| 场景 | 处理方式 |
| --- | --- |
| CocoLoop API 超时 | 交给 Agent 继续下一层 |
| ClawHub 命令失败 | 继续尝试 skills.sh |
| skills.sh 页面只给演示信息 | 继续提取仓库或下载链接 |
| GitHub API 限流 | 降级到页面解析或其他来源 |
| 所有来源都失败 | 明确告诉用户未找到可安装文件，而不是只说“搜索失败” |
