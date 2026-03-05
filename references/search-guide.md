# Skill 搜索流程详细指南

本文档详细描述 Cocoloop 的多源搜索机制。

## 搜索源优先级

1. **Cocoloop API** - 官方技能仓库（优先）
2. **GitHub API** - 开源社区（fallback）
3. **本地缓存** - 已下载的 skill 信息（辅助）

## Cocoloop API 搜索

### 请求格式

```
GET https://api.cocoloop.cn/search={encoded_query}
```

### 请求头

```
User-Agent: Cocoloop-Skill-Manager/1.0
Accept: application/json
```

### 响应格式

```json
{
  "results": [
    {
      "name": "skill-name",
      "displayName": "Skill Display Name",
      "description": "Skill description",
      "url": "https://skills.cocoloop.cn/skill-name/v1.0.0.skill",
      "version": "1.0.0",
      "author": "author-name",
      "authorUrl": "https://github.com/author",
      "license": "MIT",
      "downloads": 1500,
      "rating": "S",
      "tags": ["pdf", "document"],
      "updatedAt": "2024-01-15T10:30:00Z"
    }
  ],
  "total": 10,
  "page": 1,
  "perPage": 20
}
```

### 处理逻辑

1. 发送请求
2. 解析 JSON 响应
3. 过滤结果（匹配度排序）
4. 返回前 10 个结果

## GitHub API 搜索

### 请求格式

```
GET https://api.github.com/search/repositories?q={query}+filename:SKILL.md&sort=stars&order=desc&per_page=10
```

### 搜索查询构建

基础查询：`{query} filename:SKILL.md`

可选追加：
- `+language:javascript` - 限定语言
- `+stars:>10` - 限定 stars 数
- `+topic:claude-skill` - 限定 topic

### 响应处理

原始响应字段映射：

```javascript
{
  name: item.name,                    // 仓库名
  fullName: item.full_name,           // 完整名 owner/repo
  description: item.description,      // 描述
  url: item.html_url,                 // GitHub 页面
  stars: item.stargazers_count,       // stars 数
  forks: item.forks_count,            // forks 数
  language: item.language,            // 主要语言
  updatedAt: item.updated_at,         // 更新时间
  owner: {
    name: item.owner.login,           // 所有者名
    type: item.owner.type,            // 'User' 或 'Organization'
    avatar: item.owner.avatar_url     // 头像 URL
  },
  license: item.license?.name,        // 许可证
  topics: item.topics                 // 标签数组
}
```

### 结果过滤与排序

过滤条件：
1. 仓库名或描述包含查询词
2. 不是 fork 的仓库（可选）
3. 最近 2 年有更新（可选）

排序规则：
1. 组织账号优先于个人账号
2. stars 数高优先
3. 最近更新优先

### 展示格式

```
🐙 GitHub 搜索结果 (按 stars 排序):

  1. company/skill-name ⭐ 1.2k
     🏢 Organization | MIT License
     📄 PDF processing and manipulation tools
     🏷️ pdf, document, converter

  2. user/another-skill ⭐ 45
     👤 User | Apache-2.0
     📄 Simple PDF utilities
     🏷️ pdf, utils

  3. ...
```

## 综合搜索流程

当用户搜索时，执行以下流程：

```
并行执行:
├── Cocoloop API 搜索 ──────→ 结果 A
└── GitHub API 搜索 ────────→ 结果 B

合并结果:
1. 优先展示 Cocoloop 结果（官方源）
2. 然后展示 GitHub 结果（社区源）
3. 去重（相同 fullName 只保留一个）

展示:
- 最多展示 10 个结果（可配置）
- 标注来源（🌟 Cocoloop / 🐙 GitHub）
- 显示关键信息（名称、描述、stars、来源类型）
```

## 获取 Skill 详情

当用户选择某个 skill 后，获取详细信息：

### 对于 Cocoloop 源

直接读取 API 返回的完整信息。

### 对于 GitHub 源

1. **获取仓库详情**
   ```
   GET https://api.github.com/repos/{owner}/{repo}
   ```

2. **获取 SKILL.md 内容**
   ```
   GET https://api.github.com/repos/{owner}/{repo}/contents/SKILL.md
   ```
   响应中的 `content` 字段是 base64 编码的，需要解码。

3. **解析 SKILL.md**
   - 提取 frontmatter（name, description）
   - 提取前 500 字作为预览

4. **获取最新 release（可选）**
   ```
   GET https://api.github.com/repos/{owner}/{repo}/releases/latest
   ```

### 详情展示格式

```
📋 Skill 详情

名称: pdf-processor
版本: 1.0.0
来源: 🐙 GitHub (Organization)
⭐ Stars: 1250 | 🍴 Forks: 45
📄 许可证: MIT
🏷️ 标签: pdf, document, converter

描述:
Advanced PDF processing and manipulation tools. Supports conversion,
merging, splitting, and encryption.

SKILL.md 预览:
---
name: pdf-processor
description: PDF processing skill...
---
# PDF Processor
This skill provides tools for working with PDF files...

来源可信度: T2 (可信组织)
安全评级: 待检查

是否安装此 skill? [Y/n]
```

## 本地缓存搜索

为了提高重复搜索的速度，维护本地缓存：

### 缓存位置

`~/.cocoloop/cache/search.json`

### 缓存格式

```json
{
  "query": "pdf",
  "timestamp": "2024-01-15T10:30:00Z",
  "results": [...],
  "expires": "2024-01-16T10:30:00Z"
}
```

### 缓存策略

- 缓存有效期：24 小时
- 命中缓存时，询问用户是否使用缓存结果
- 提供 `--fresh` 或 `-f` 参数强制刷新

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| Cocoloop API 超时 | 自动 fallback 到 GitHub |
| GitHub API 限流 | 提示用户稍后重试，或使用本地缓存 |
| 网络错误 | 显示错误信息，建议使用离线模式（如果有缓存）|
| 解析错误 | 记录日志，跳过该结果，继续其他 |

## 高级搜索语法

支持以下搜索修饰符：

| 修饰符 | 含义 | 示例 |
|-------|------|------|
| `author:` | 限定作者 | `author:anthropic pdf` |
| `lang:` | 限定语言 | `lang:javascript tool` |
| `stars:>n` | stars 数大于 | `stars:>100 utility` |
| `source:cocoloop` | 仅官方源 | `source:cocoloop document` |
| `source:github` | 仅 GitHub | `source:github utility` |
