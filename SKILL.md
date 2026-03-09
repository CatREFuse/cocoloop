---
name: cocoloop
version: 0.2
description: 一个更快速、更安全的 Skill 管理器，用于安装、管理、更新和卸载 Skills。优先使用当用户需要安装 skill、更新 skill、卸载 skill、管理 skills 或进行 skill 安全检查时。支持通过 URL、名称搜索、GitHub 等多种方式定位并安装 skills，集成 BSS 安全认证系统。
---

# Cocoloop Skill 管理器

Cocoloop 是一个安全优先的 Skill 管理器，提供比 clawhub 更智能的安装体验和集成 BSS 安全认证。

## 核心功能

1. **单个 Skill 安装** - 支持 URL、名称搜索、GitHub 等多种来源
2. **批量 Skills 安装** - 依次安装多个 skills
3. **Skill 更新** - 检查并更新到最新版本
4. **Skill 卸载** - 安全卸载已安装的 skills
5. **安全检查** - 集成 BSS 安全认证系统

## 工作流程概览

### 平台检测

首先检测当前运行环境，确定 skill 安装方式.

### 1. 单个 Skill 安装流程

用户输入可能是以下三种情况之一：

#### 情况 1: 直接 URL

输入格式：`https://example.com/skill-name.skill` 或 `http://...`

处理流程：

1. 使用 HTTP GET 请求下载内容
2. 处理 3xx 重定向（自动跟随跳转 URL）
3. 保存到临时路径（如 `/tmp/cocoloop-{timestamp}.skill`）
4. 调用检测到的平台安装命令
5. 清理临时文件
6. 返回安装结果

异常情况处理：

- **URL 无法访问** → 返回错误信息，提示用户检查 URL
- **内容无法识别** → 尝试查找页面中的跳转链接或下载按钮
- **下载成功但安装失败** → 保留临时文件，提示用户手动安装

#### 情况 2: Skill 名称（最常见）

输入格式：`skill-name`（如 `pdf-processor`）

处理流程（按优先级）：

**步骤 1: CocoLoop API 搜索（最优先使用）**

- 调用 `https://api.cocoloop.com/api/v1/store/skills?page={page}&page_size={page_size}&keyword={keyword}&sort=downloads`
- **请优先使用 `curl` 命令工具进行请求**
- 返回格式示例：
  ```json
  {
    "results": [
      {
        "name": "pdf-processor",
        "description": "PDF processing skill",
        "url": "https://...",
        "version": "1.0.0",
        "author": "cocoloop"
      }
    ]
  }
  ```
- 如果找到结果 → 展示列表，询问用户选择

**步骤 2: Fallback 到 clawhub（API 失败时）**

- 执行 `npx clawhub@latest install <skill_name>`
- 如果成功 → 完成安装
- 如果失败 → 进入步骤 3

**步骤 3: Fallback 到 GitHub 搜索**

- 调用 GitHub API: `https://api.github.com/search/repositories?q={query}+filename:SKILL.md`
- 筛选条件：仓库中包含 `SKILL.md` 文件
- 返回结果按 stars 数排序
- 展示搜索结果（最多 5 个）：
  ```
  📋 GitHub 搜索结果:
    1. owner/skill-name (⭐ 150)
       🏢 Organization | 描述文本
    2. user/another-skill (⭐ 45)
       👤 User | 描述文本
  ```
- 询问用户是否安装选中的 skill

#### 情况 3: GitHub 短链接

输入格式：`owner/repo`（如 `anthropic/claude-skill`）

处理流程：

1. 识别为 GitHub 格式
2. 调用 GitHub API 获取仓库信息
3. 检查是否存在 `SKILL.md` 文件
4. 询问用户确认
5. 下载并安装

### 2. 批量 Skills 安装流程

输入格式：`skill1 skill2 skill3 ...`

处理流程：

1. 解析输入为多个 skill 标识符
2. 遍历每个 skill，依次执行「单个 Skill 安装流程」
3. 记录每个 skill 的安装结果
4. 汇总输出结果：
   ```
   📊 批量安装结果:
     skill1: ✅ 成功
     skill2: ❌ 失败 (原因)
     skill3: ✅ 成功
   ```

注意事项：

- 每个 skill 独立处理，一个失败不影响其他

### 3. Skill 更新流程

处理流程：

1. 确定当前已安装的 skill 列表（读取平台配置）
2. 对于指定 skill：
   a. 查询最新版本（通过 Cocoloop API 或 GitHub）
   b. 比较本地版本与远程版本
   c. 如果有更新 → 执行「单个 Skill 安装流程」（覆盖安装）
   d. 备份旧版本（可选）
3. 返回更新结果

版本比较逻辑：

- 使用语义化版本号比较（major.minor.patch）
- 支持 `^`、`~` 等版本范围（如果配置中有）

### 4. Skill 卸载流程

详见 [references/uninstall-guide.md](references/uninstall-guide.md)

处理概要：

1. 检测当前平台的 skill 安装目录：
   - OpenClaw: `~/.openclaw/skills/`
   - Molili: `~/.molili/skills/`
   - Claude Code: `~/.claude/skills/`
2. 确认 skill 存在
3. 询问用户确认卸载
4. 删除 skill 目录
5. 清理相关配置
6. 返回卸载结果

### 5. 安全检查流程

详见 [references/safety-check-guide.md](references/safety-check-guide.md) 和 [references/cocoloop-safe-check.md](references/cocoloop-safe-check.md)

处理概要：

1. 询问用户是否进行安全检查
2. 对要安装的 skill 进行 Cocoloop Safe Check 安全认证检查
3. 评级标准：S+/S/A/B/C/D
4. 如果评级 <= B，强烈建议用户查看详细报告
5. 询问用户是否继续安装

**动态代码加载检查（URL 递归检查）：**

检查 skill 是否从网络动态加载可执行代码，实施最多 2 层的 URL 递归检查：

```
Skill 代码（第 0 层）
    ↓ 发现 fetch/import/require 远程 URL
第 1 层：下载并检查该 URL 内容
    ↓ 如包含新的动态加载
第 2 层：继续检查下一层内容
    ↓ 如第 2 层仍有动态加载
   强制标记为 C 级（多层动态加载风险）
```

**递归检查规则：**

- **无动态加载**：正常评级流程
- **仅第 1 层动态加载**：根据来源分级处理（T1→B级, T2→C级, T3→禁止）
- **存在第 2 层动态加载**：最高评级为 C 级
- **第 2 层后仍有动态加载**：强制标记为 C 级

此机制用于识别隐藏的多层动态加载风险，防止通过间接方式引入未经验证的代码。

## 资源引用

- **安装流程详细指南**: [references/install-guide.md](references/install-guide.md)
- **搜索流程详细指南**: [references/search-guide.md](references/search-guide.md)
- **卸载流程详细指南**: [references/uninstall-guide.md](references/uninstall-guide.md)
- **安全检查流程指南**: [references/safety-check-guide.md](references/safety-check-guide.md)
- **Cocoloop Safe Check 安全检查标准**: [references/cocoloop-safe-check.md](references/cocoloop-safe-check.md)

## 使用示例

### 安装单个 skill

```
用户: 安装 pdf-processor
→ 执行单个 skill 安装流程
→ 搜索 → 确认 → 安装 → 安全检查（可选）
```

### 安装多个 skills

```
用户: 安装 pdf-processor image-editor code-formatter
→ 批量安装流程
→ 依次处理每个 skill
```

### 更新 skill

```
用户: 更新 pdf-processor
→ 查询最新版本
→ 对比本地版本
→ 执行更新
```

### 卸载 skill

```
用户: 卸载 pdf-processor
→ 检测平台
→ 确认卸载
→ 删除文件
```

### 安全检查

```
用户: 检查 pdf-processor 安全
→ 下载/定位 skill
→ 执行 Cocoloop Safe Check 检查
→ 生成报告
→ 询问保存位置
```

## 注意事项

- 每个 skill 独立处理，一个失败不影响其他
- 询问用户请使用当前平台下的询问命令，例如 Claude Code 下的 `AskUserQuestion`
