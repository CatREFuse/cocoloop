# Skill 卸载流程详细指南

本文档详细描述 skill 的卸载流程。

## 卸载前准备

### 1. 检测平台

使用与安装相同的平台检测逻辑：

```
IF OpenClaw:
    安装目录 = ~/.openclaw/skills/
    配置文件 = ~/.openclaw/config.json

ELSE IF Molili:
    安装目录 = ~/.molili/skills/
    配置文件 = ~/.molili/config.json

ELSE IF Claude Code:
    安装目录 = ~/.claude/skills/
    配置文件 = ~/.claude/config.json

ELSE:
    安装目录 = ~/.claude/skills/ (clawhub 默认)
    配置文件 = ~/.claude/config.json
```

### 2. 确认 Skill 存在

检查 skill 目录是否存在：

```
{安装目录}/{skill-name}/
    ├── SKILL.md
    ├── scripts/
    ├── references/
    └── assets/
```

如果不存在：
- 返回错误 "未找到该 skill，可能已卸载或名称错误"
- 建议用户使用 `list` 命令查看已安装 skills

### 3. 获取 Skill 信息

读取 SKILL.md 获取基本信息：
- name
- description
- version（如果有）

## 卸载流程

### 第一步：用户确认

展示将要卸载的 skill 信息，请求确认：

```
⚠️ 即将卸载以下 skill:

名称: pdf-processor
描述: PDF processing and manipulation tools
安装路径: ~/.claude/skills/pdf-processor/

⚠️ 此操作将删除该 skill 的所有文件，不可恢复。

是否确认卸载? [y/N]
```

可选：添加 `--force` 或 `-f` 参数跳过确认。

### 第二步：备份（可选）

如果用户指定 `--backup` 或 `-b` 参数：

1. 创建备份目录：`~/.cocoloop/backups/`
2. 打包 skill 目录：`tar -czf ~/.cocoloop/backups/{skill-name}-{timestamp}.tar.gz {skill-path}/`
3. 提示备份位置

### 第三步：执行卸载

1. **删除 skill 目录**
   ```bash
   rm -rf {安装目录}/{skill-name}/
   ```

2. **更新平台配置（如果需要）**
   - 某些平台维护已安装 skill 列表
   - 从列表中移除该 skill

3. **清理相关缓存**
   - 删除 Cocoloop 本地缓存中该 skill 的搜索记录
   - 删除安全检查缓存（如果有）

### 第四步：验证卸载

检查 skill 目录是否还存在：
- 如果存在 → 返回错误 "卸载失败，请检查权限或手动删除"
- 如果不存在 → 卸载成功

## 批量卸载

支持一次卸载多个 skills：

```
卸载 skill1 skill2 skill3
```

处理流程：
1. 遍历每个 skill
2. 执行单个卸载流程（不询问确认，或统一确认）
3. 汇总结果：
   ```
   📊 卸载结果:
     skill1: ✅ 已卸载
     skill2: ❌ 未找到
     skill3: ✅ 已卸载
   ```

## 卸载后处理

### 依赖检查（可选）

检查是否有其他 skill 依赖被卸载的 skill：
1. 遍历所有已安装 skills
2. 检查它们的 dependencies（如果有记录）
3. 如果有依赖关系，警告用户：
   ```
   ⚠️ 警告: 以下 skill 可能依赖 pdf-processor:
     - document-workflow

   继续使用这些 skill 可能会出现问题。
   ```

### 清理孤立依赖（高级）

如果 skill 安装了独立的依赖（如 node_modules），检查是否可以清理：
- 如果其他 skill 不使用 → 可以删除
- 如果有共享依赖 → 保留

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 权限不足 | 提示使用 `sudo` 或检查目录权限 |
| 文件被占用 | 提示关闭使用该 skill 的程序后重试 |
| 目录非空但无法删除 | 保留日志，提示手动删除 |
| 配置文件损坏 | 尝试修复或重建配置 |

## 恢复卸载

如果用户误卸载，提供恢复选项（前提是备份存在）：

```
恢复 pdf-processor
```

流程：
1. 查找备份目录：`~/.cocoloop/backups/pdf-processor-*.tar.gz`
2. 列出可用备份（按时间排序）
3. 询问用户选择恢复哪个版本
4. 解压到安装目录
5. 验证恢复
