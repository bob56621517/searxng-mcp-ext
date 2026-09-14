# AGENTS.md

本仓库是 `searxng-mcp-ext` —— 基于官方 SearXNG 镜像的扩展发行版:注入搜索引擎 provider,并内置 HTTP MCP 端点,通过 Docker Compose 一键部署。

> 项目代码尚未开始。本文件当前只承载工程 skill 的配置。

## Agent skills

## Grilling

一个问题带着一个推荐答案提问,不要一次性提问3个以上的问题.  

### Issue tracker

issue 与 spec 作为 GitHub Issues 存放在 `bob56621517/searxng-mcp-ext`,统一用 `gh` CLI 操作。见 `docs/agents/issue-tracker.md`。

### Triage labels

沿用五个规范默认标签:`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`。见 `docs/agents/triage-labels.md`。

### Domain docs

单 context 布局:仓库根目录一个 `CONTEXT.md` 加 `docs/adr/`。见 `docs/agents/domain.md`。
