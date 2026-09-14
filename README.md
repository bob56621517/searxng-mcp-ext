# searxng-mcp-ext

基于官方 [SearXNG](https://github.com/searxng/searxng) 镜像的扩展发行版:注入中文搜索引擎,并在**同一个进程内**内嵌一个 HTTP MCP 端点。

给 AI 助手接上搜索能力,过去要拼三样东西——SearXNG 实例、MCP 服务器、把两者连起来的配置。这个项目把它们合成一个容器:**起一条命令,填一个 URL**。

> **Status:** 早期开发中。

## 快速开始

```bash
# 可选:填入博查 API key 以获得付费兜底能力
export BOCHA_API_KEY=你的key

docker compose up -d
```

起好后:

| | |
|---|---|
| 搜索界面 | <http://localhost:8888/> |
| JSON API | <http://localhost:8888/search?format=json&q=hello> |
| **MCP 端点** | **<http://localhost:8888/ext/mcp>** *(Streamable HTTP)* |

容器内固定监听 `8080`,宿主侧由 `PORT` 控制(默认 `8888`)。

> `docker-compose.yml` 引用的是 CI 构建好的镜像,**不需要本地构建工具链**。想自己构建用同目录的 `Dockerfile`。

## 接入 MCP 客户端

端点走 **Streamable HTTP**,客户端填 URL 即可,无需安装任何东西:

```json
{
  "mcpServers": {
    "searxng": {
      "type": "http",
      "url": "http://localhost:8888/ext/mcp"
    }
  }
}
```

## 工具

只暴露一个工具 `web_search`:

| 参数 | 必填 | 说明 |
|---|---|---|
| `query` | ✅ | 搜索词 |
| `count` | | 返回条数,1–50,默认 20 |
| `time_range` | | `day` / `week` / `month` / `year` |
| `categories` | | `general` / `it` / `repos` / `code` / `videos` / `news` / `images` |

返回**两种形态**:

- `content` — 人类可读的 Markdown
- `structuredContent.results` — 结构化三元组 `{url, title, content}`

**`fetch_url_mode` 字段**:当某条结果的 URL 不是真实地址、需要用浏览器才能解开时(目前是 `chinaso` 的加密跳转链接),该条会额外携带 `fetch_url_mode: "browser"`。下游抓取工具应据此选择浏览器模式,而**不要**用普通 HTTP 直接请求。

## 内置引擎

```
general : google, bing, duckduckgo, baidu, 360search, sogou, quark, bocha
it      : github, github code, baidu kaifa
repos   : github          code : github code
videos  : bilibili, iqiyi, acfun, 360search videos, sogou videos
news    : sogou wechat, chinaso news
images  : baidu images, quark images, sogou images
```

| 引擎 | 说明 |
|---|---|
| `bocha` | 付费兜底,**需要 `BOCHA_API_KEY`**。未设置时该引擎不工作,其余引擎不受影响 |
| `braveapi` | **默认不启用**,需要 `BRAVE_API_KEY` |
| `github code` | 默认匿名模式(限流较严)。有 token 可挂载配置提高配额 |
| `chinaso news` | 返回加密跳转链接,结果会带 `fetch_url_mode` 标记 |

## 配置

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `BOCHA_API_KEY` | (空) | 博查 API key |
| `PORT` | `8888` | 宿主侧映射端口(容器内固定 8080) |

要改引擎清单、或者给 `braveapi` / `github code` 填密钥,挂载自己的配置文件:

```yaml
volumes:
  - ./settings.yml:/etc/searxng/settings.yml:ro
```

文件已存在时官方 entrypoint 不会覆盖它。可从镜像内的 `searxng/settings.yml` 抄一份改。

**注意**:`use_default_settings.engines` 段是**按名字合并**——没写的键会保留上游默认值。`github code` 和 `chinaso` 在上游默认定义里是 `inactive: true`,**必须显式写 `inactive: false` 才会启用**。

## 安全

**端点默认没有任何鉴权。** 请自行在外部网关/反向代理做访问控制,不要直接暴露到公网——否则任何人都能拿你的实例跑聚合搜索(消耗你的出网带宽,并可能让你的 IP 被搜索引擎封禁)。

## 从源码构建

```bash
docker build -t searxng-mcp-ext:local .
```

## 许可证

**AGPL-3.0-or-later** —— 见 [LICENSE](LICENSE)。

本项目的镜像分发包含上游 SearXNG 代码,且通过网络提供服务,处于 AGPL 网络条款(第 13 条)覆盖范围内。

## 与上游的关系

**非官方派生项目**,不隶属于 SearXNG 项目,不使用其官方标识。

需要说明的是:SearXNG 维护者曾明确表示 MCP 集成应当作为**独立项目**通过 API 交互,而不是并入 SearXNG 主仓库。本项目作为独立派生镜像在许可范围内有权采用同进程内嵌的形态,这是一个有意的取舍——换取部署简单(单容器、单进程、单端口),代价是与上游的耦合更深。
