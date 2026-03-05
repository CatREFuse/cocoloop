# Cocoloop

一个更快速、更安全的 Skill 管理器，用于安装、管理、更新和卸载 Skills。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 简介

Cocoloop 是一个安全优先的 Skill 管理器，提供比 clawhub 更智能的安装体验和集成 BSS 安全认证。

## 功能特性

- **单个 Skill 安装** - 支持 URL、名称搜索、GitHub 等多种来源
- **批量 Skills 安装** - 依次安装多个 skills
- **Skill 更新** - 检查并更新到最新版本
- **Skill 卸载** - 安全卸载已安装的 skills
- **安全检查** - 集成 BSS 安全认证系统

## 安装

```bash
# 克隆仓库
git clone https://github.com/CatREFuse/cocoloop.git
cd cocoloop
```

## 使用方法

### 安装单个 Skill

```bash
# 通过名称安装
cocoloop install pdf-processor

# 通过 URL 安装
cocoloop install https://example.com/skill-name.skill

# 通过 GitHub 安装
cocoloop install owner/repo
```

### 批量安装 Skills

```bash
cocoloop install skill1 skill2 skill3
```

### 更新 Skill

```bash
cocoloop update pdf-processor
```

### 卸载 Skill

```bash
cocoloop uninstall pdf-processor
```

### 安全检查

```bash
cocoloop check pdf-processor
```

## 安全检查系统

Cocoloop 集成了 BSS (Berry Skills Safe) 安全认证检查，评级标准：

- **S+** - 最高安全等级
- **S** - 优秀
- **A** - 良好
- **B** - 一般（需谨慎）
- **C** - 风险较高
- **D** - 不建议使用

### 动态代码加载检查

实施最多 2 层的 URL 递归检查，识别隐藏的多层动态加载风险：

- 无动态加载：正常评级流程
- 仅第 1 层动态加载：根据来源分级处理
- 存在第 2 层动态加载：最高评级为 C 级
- 第 2 层后仍有动态加载：强制标记为 C 级

## 支持的平台

- OpenClaw
- Molili
- Claude Code

## 文档

- [安装流程指南](references/install-guide.md)
- [搜索流程指南](references/search-guide.md)
- [卸载流程指南](references/uninstall-guide.md)
- [安全检查流程指南](references/safety-check-guide.md)
- [Cocoloop Safe Check 标准](references/cocoloop-safe-check.md)

## 工作流程

### Skill 安装流程

1. **平台检测** - 确定当前运行环境和安装方式
2. **来源识别** - 支持直接 URL、Skill 名称、GitHub 短链接
3. **搜索与下载** - 从 Cocoloop API、clawhub 或 GitHub 获取
4. **安全检查** - BSS 安全认证检查
5. **安装执行** - 安装到对应平台的 skill 目录

### 搜索优先级

1. Cocoloop API 搜索
2. Fallback 到 clawhub
3. Fallback 到 GitHub 搜索

## 项目结构

```
cocoloop/
├── SKILL.md                      # Skill 定义文件
├── README.md                     # 项目说明文档
└── references/                   # 详细指南文档
    ├── install-guide.md          # 安装流程指南
    ├── search-guide.md           # 搜索流程指南
    ├── uninstall-guide.md        # 卸载流程指南
    ├── safety-check-guide.md     # 安全检查流程指南
    └── cocoloop-safe-check.md    # 安全检查标准
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

[MIT](LICENSE)

---

Made with ❤️ by Cocoloop Team
