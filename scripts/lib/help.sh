#!/usr/bin/env bash

cocoloop::help::main() {
  cat <<'HELP'
Cocoloop CLI

用法:
  cocoloop <command> [options]

主命令:
  search        搜索技能
  featured      查看主站精选推荐
  inspect       查看技能详情
  install       安装技能
  uninstall     卸载技能
  update        更新指定技能
  update-self   更新 Cocoloop 自己
  like          收藏技能
  like-list     查看收藏列表
  candidate     提交候选技能

高级命令:
  healthcheck   执行健康检查
  paths         查看候选安装路径
  safescan      执行安全扫描

帮助:
  cocoloop <command> --help
HELP
}

cocoloop::help::subcommand() {
  local command="$1"
  case "$command" in
    search)
      cat <<'HELP'
用法: cocoloop search --query QUERY

说明:
  search 会同时执行官方搜索和本地已知 Agent 目录搜索，再汇总输出。
  当前版本默认把候选结果视为待 Agent 判断或待用户确认，不直接把列表当成可信命中。
  如果本地已知 Agent 里已经存在同名或相近 Skill，会提示用户是否移植到当前环境。
HELP
      ;;
    featured)
      cat <<'HELP'
用法: cocoloop featured [--categories | --category CATEGORY]

说明:
  featured 默认读取主站当前精选技能列表。
  传入 --categories 时，读取主站当前精选技能分类列表。
  传入 --category CATEGORY 时，只读取该分类下的精选技能列表。
  这个命令只负责官方接口取数和展示，不替 Agent 做安装或选择判断。
HELP
      ;;
    inspect)
      cat <<'HELP'
用法: cocoloop inspect SKILL

说明:
  查看技能的元数据、版本、安全评级、来源和下载入口。
HELP
      ;;
    install)
      cat <<'HELP'
用法: cocoloop install SKILL_OR_SOURCE [--scope auto|project|user] [--force] [--skills skill-a,skill-b | --all]

说明:
  install 是“已知安装流程 wrapper”，不承担综合决策。
  仅在已知支持的环境中执行 batch 安装（本地路径、已知归档 URL、GitHub 仓库）。
  当前版本默认先把 Skill 内容写入 ~/.cocoloop/skills/，再通过软链接发布到目标平台目录；如果当前平台不适合软链接，会退回复制。
  如果来源里存在多个 Skill，默认返回 review-required 并列出候选；只有用户或 Agent 明确指定 --skills 或 --all 后才继续安装。
  如果环境不明确、来源不属于已知安装流、安装失败或自检失败，会输出 handoff-to-agent，交给 Agent 自行探索安装。
HELP
      ;;
    uninstall)
      cat <<'HELP'
用法: cocoloop uninstall SKILL [--scope all|project|user]

说明:
  定位并卸载指定 Skill。
HELP
      ;;
    update)
      cat <<'HELP'
用法: cocoloop update SKILL

说明:
  检查指定 Skill 的版本并执行更新。
HELP
      ;;
    update-self)
      cat <<'HELP'
用法: cocoloop update-self

说明:
  检查并更新 Cocoloop 本体。
HELP
      ;;
    like)
      cat <<'HELP'
用法: cocoloop like --skill SKILL

说明:
  收藏某个 Skill。当前版本调用联调接口。
HELP
      ;;
    like-list)
      cat <<'HELP'
用法: cocoloop like-list

说明:
  查看收藏列表，并合并本地安装状态。
HELP
      ;;
    candidate)
      cat <<'HELP'
用法: cocoloop candidate (--data-json JSON | --data-file FILE)

说明:
  提交未收录 Skill 的候选信息。
HELP
      ;;
    healthcheck)
      cat <<'HELP'
用法: cocoloop healthcheck

说明:
  检查网络、服务可用性和依赖连通性。当前版本已接入 ping 和 health 接口。
HELP
      ;;
    paths)
      cat <<'HELP'
用法: cocoloop paths [--agent AGENT] [--os OS]

说明:
  输出当前平台下的候选安装路径。
HELP
      ;;
    safescan)
      cat <<'HELP'
用法: cocoloop safescan TARGET

说明:
  对目标 Skill、路径或来源执行安全扫描。当前版本支持本地文件、目录和 hash 查询。
HELP
      ;;
    *)
      cocoloop::die "unknown_help" "未知帮助主题: $command"
      ;;
  esac
}
