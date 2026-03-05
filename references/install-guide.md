# Skill 安装流程详细指南

本文档详细描述单个 skill 的安装流程，包括所有分支逻辑和异常处理。

## 流程图

```
开始
  ↓
接收用户输入 (URL / 名称 / GitHub短链)
  ↓
检测运行平台
  ↓
判断输入类型
  ├── URL ─────────→ 下载内容 ──→ 保存临时文件 ──→ 平台安装 ──→ 清理 ──→ 完成
  │                    ↑                           │
  │                    └──────── 失败 ──────────────┘
  │
  ├── 名称 ─────────→ Cocoloop API 搜索
  │                      │
                      成功? ──是──→ 展示结果 ──→ 用户确认 ──→ 下载安装 ──→ 完成
  │                      │否
  │                      ↓
  │              clawhub install
  │                      │
                      成功? ──是──→ 完成
  │                      │否
  │                      ↓
  │              GitHub API 搜索
  │                      │
                      成功? ──是──→ 展示结果 ──→ 用户确认 ──→ 下载安装 ──→ 完成
  │                      │否
  │                      ↓
  │              返回错误
  │
  └── GitHub短链 ───→ 获取仓库信息 ──→ 确认SKILL.md存在 ──→ 下载安装 ──→ 完成
```

## 详细步骤

### 第一步：平台检测

检测逻辑：
```
IF 环境变量 OPENCLAW_HOME 存在 或 /usr/local/openclaw 存在:
    平台 = OpenClaw
    安装命令 = "openclaw skills install"
    安装目录 = ~/.openclaw/skills/

ELSE IF 环境变量 MOLILI_HOME 存在 或 /usr/local/molili 存在:
    平台 = Molili
    安装命令 = "molili skills install"
    安装目录 = ~/.molili/skills/

ELSE IF 环境变量 CLAUDE_CODE_HOME 存在 或 /usr/local/claude-code 存在:
    平台 = Claude Code
    安装命令 = "claude skills install"
    安装目录 = ~/.claude/skills/

ELSE:
    平台 = 通用 (clawhub fallback)
    安装命令 = "npx clawhub@latest install"
    安装目录 = ~/.claude/skills/ (或 clawhub 默认目录)
```

### 第二步：URL 安装流程

完整流程：

1. **发送 HTTP GET 请求**
   - URL: 用户提供的地址
   - Headers:
     ```
     User-Agent: Cocoloop-Skill-Manager/1.0
     ```

2. **处理响应**
   - 状态码 200 → 获取内容，进入步骤 3
   - 状态码 3xx → 从 Location header 获取跳转 URL，递归步骤 1
   - 其他状态码 → 返回错误

3. **保存临时文件**
   - 临时路径: `/tmp/cocoloop-{timestamp}.skill`
   - 写入下载内容

4. **执行平台安装命令**
   ```bash
   {platform.installCmd} /tmp/cocoloop-{timestamp}.skill
   ```

5. **清理与返回**
   - 安装成功 → 删除临时文件 → 返回成功
   - 安装失败 → 保留临时文件（便于调试）→ 返回错误

异常处理：

| 异常情况 | 处理方式 |
|---------|---------|
| URL 无法访问 | 返回错误 "无法访问该 URL，请检查网络连接或 URL 是否正确" |
| 重定向过多 | 返回错误 "该 URL 重定向次数过多，可能存在循环跳转" |
| 下载内容为空 | 返回错误 "下载内容为空，请检查 URL 是否正确" |
| 安装命令失败 | 返回错误 "安装失败，临时文件保留在 {path}，可尝试手动安装" |

### 第三步：名称搜索安装流程

#### 3.1 Cocoloop API 搜索

请求：
```
GET https://api.cocoloop.cn/search={encoded_query}
```

成功响应示例：
```json
{
  "results": [
    {
      "name": "pdf-processor",
      "description": "PDF processing and manipulation skill",
      "url": "https://skills.cocoloop.cn/pdf-processor/v1.0.0.skill",
      "version": "1.0.0",
      "author": "cocoloop-team",
      "downloads": 1500,
      "rating": "S"
    }
  ],
  "total": 1
}
```

处理：
- 如果 results.length > 0 → 展示结果，询问用户选择
- 如果 results.length = 0 或 API 失败 → 进入 3.2

#### 3.2 clawhub Fallback

执行：
```bash
npx clawhub@latest install {skill_name}
```

处理：
- 成功 → 完成安装
- 失败（退出码非0）→ 进入 3.3

#### 3.3 GitHub API 搜索

请求：
```
GET https://api.github.com/search/repositories?q={query}+filename:SKILL.md&sort=stars&order=desc
```

Headers:
```
User-Agent: Cocoloop-Skill-Manager/1.0
```

成功响应处理：
```javascript
results = data.items
  .filter(repo => repo.name.includes(query) || repo.description?.includes(query))
  .map(repo => ({
    name: repo.name,
    fullName: repo.full_name,
    description: repo.description,
    url: repo.html_url,
    stars: repo.stargazers_count,
    owner: {
      name: repo.owner.login,
      type: repo.owner.type  // 'User' 或 'Organization'
    }
  }))
  .slice(0, 5)  // 取前5个
```

展示格式：
```
📋 GitHub 搜索结果 (找到 {total} 个):

  1. company/pdf-processor ⭐ 1250
     🏢 Organization | Advanced PDF processing tools

  2. user/simple-pdf ⭐ 45
     👤 User | Basic PDF operations

请选择要安装的 skill (输入序号，或输入 0 取消):
```

用户选择后：
1. 获取仓库详情（确认存在 SKILL.md）
2. 询问用户确认安装
3. 下载 raw SKILL.md 和相关资源
4. 打包为 .skill 文件（如果需要）
5. 执行平台安装

### 第四步：GitHub 短链安装流程

输入格式识别：
- 包含 `/` 但不以 `http` 开头
- 格式：`owner/repo` 或 `owner/repo/subpath`

处理流程：
1. 解析 owner 和 repo
2. 调用 GitHub API 获取仓库信息：
   ```
   GET https://api.github.com/repos/{owner}/{repo}
   ```
3. 检查是否存在 SKILL.md：
   ```
   GET https://api.github.com/repos/{owner}/{repo}/contents/SKILL.md
   ```
4. 如果存在 → 展示仓库信息，询问确认
5. 下载并安装

### 第五步：安全检查（可选但推荐）

在安装前或安装后，询问用户是否进行安全检查：

```
⚠️ 安全提醒: 该 skill 来源为 {source_level}，建议进行安全检查。
是否进行 BSS 安全认证检查? [Y/n]
```

如果用户选择是：
1. 执行 [safety-check-guide.md](safety-check-guide.md) 和 [cocoloop-safe-check.md](cocoloop-safe-check.md) 中的检查流程
2. 生成报告
3. 如果评级 <= B，询问用户是否继续安装

## 安装后处理

安装完成后，执行：
1. 验证安装是否成功（检查安装目录）
2. 如果是更新操作，清理旧版本备份
3. 可选：显示 skill 使用帮助
   ```
   ✅ 安装成功!

   Skill: pdf-processor
   版本: 1.0.0
   来源: cocoloop (S级认证)

   使用方式:
   - 转换 PDF: 使用 pdf-processor 转换 xxx.pdf 为 docx
   - 合并 PDF: 使用 pdf-processor 合并 a.pdf b.pdf
   ```
