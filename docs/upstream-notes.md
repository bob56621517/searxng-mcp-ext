# 与上游交互的关键约束

实测得出的、**从代码和官方文档里看不出来**的约束。每条都注明了证据来源,不做转述。

> **本文件只记录不适合放在代码旁的两条。** 其余结论已经就近写在相关源文件的注释里 ——
> 让约束和它约束的代码待在一起,比集中放一份更容易被读到。末尾附索引。

---

## 一、为什么引擎的启用只能走配置

### 1. UI 的引擎开关是 cookie 级,API 场景完全用不上

`searx/preferences.py` 把引擎选择存进 **cookie**:

```python
resp.set_cookie('disabled_{0}'.format(self.name), ','.join(disabled_changed), max_age=COOKIE_MAX_AGE)
resp.set_cookie('enabled_{0}'.format(self.name),  ','.join(enabled_changed),  max_age=COOKIE_MAX_AGE)
```

引擎选择正是从这里读取的(`searx/webadapter.py`):

```python
disabled_engines = preferences.engines.get_disabled()
```

**三层作用域,差别很大:**

| 层次 | 存哪 | 作用域 | 谁能改 |
|---|---|---|---|
| `settings.yml` 的 `disabled` / `inactive` | 文件 | **全局** | 部署者 |
| UI 勾选开关 | **cookie** | 单客户端 / 单浏览器 | 用户点一下 |
| `engines=` / `categories=` | 请求参数 | **单次调用** | 每次请求 |

**MCP 客户端走的是 JSON API,不带 SearXNG 的 cookie** —— 所以中间那层对 API **完全无效**。

**这是「引擎启用与否只由环境变量/配置决定,不暴露为 MCP 工具参数」这个决策的直接依据。** 在 API 场景下,能改引擎的只有「全局配置」和「单次参数」两层;而引擎的启用关系到出网信誉、付费额度、反爬风险,属于部署决策,不该交给模型即兴选择。

### 2. `/config` 不能作为「引擎清单」的判据

- 它列出的是**静态配置**里的引擎,**包含那些因缺密钥而根本没被注册的**(例如无 `BOCHA_API_KEY` 时的 `bocha`)
- 实测中它的数量与 `settings.yml` 的 `keep_only` 结果**也不总是一致**(曾出现 `keep_only` 已剔到 17、`/config` 仍报 21 的情况)

**可靠判据只有两个:**

1. 容器内 `settings.yml` 的 `keep_only` 段
2. 搜索响应里的 `unresponsive_engines` 字段(**运行时**真相)

> 这个坑在开发中导致过三次误判 —— 每次都以为「改动没生效」,实际是看错了地方。**判断引擎状态时不要用 `/config`。**

---

## 二、已在代码注释里的结论(此处仅作索引)

| 结论 | 位置 |
|---|---|
| `use_default_settings.engines` 是**按名字合并**,漏写 `inactive` 会保留上游默认值(见下方备注) | `searxng/settings.yml` |
| 引擎**读不到入站 HTTP 请求头**(`RequestParams` 无该字段),故 header 传密钥不可实现 | `searxng/engines/bocha.py` |
| `GRANIAN_BLOCKING_THREADS=4` 与 granian 的 ASGI 模式冲突,进程直接退出 | `Dockerfile` |
| 上游镜像的 venv **没有 pip**,需先 `ensurepip` | `Dockerfile` |
| `FastMCP` 在 mcp 2.x 已改名 `MCPServer`;`fastmcp` 是另一个独立包 | `ext_http.py` |
| Streamable HTTP app 的 lifespan 挂在 `.router` 上,不在 app 实例上 | `ext_http.py` |
| 要同时控制文本与结构化内容,需显式构造 `CallToolResult` | `ext_http.py` |
| 引擎启用/禁用的环境变量接口(`SEARXNG_ENGINES` 等)与其设计取向 | `ext-apply-env.sh` |

**关于第一条的展开**(它是本项目踩过最隐蔽的坑):

上游 `searx/settings_loader.py` 对自定义 `engines:` 段的处理是**合并而非替换**:

```python
if default_engine:
    update_dict(default_engine, user_engine)   # 已存在 → 合并
else:
    engines.append(user_engine)                # 不存在 → 追加
```

**没写的键会保留上游默认值。** `github code` 和 `chinaso news` 在上游默认定义里都是 `inactive: true`,**不显式写 `inactive: false` 就永远不会启用**——即使 `disabled: false`、分类也配对了。排查时极易误判成「引擎名写错」或「引擎不存在」。

---

## 三、上游对 MCP 集成的立场

SearXNG 维护者曾多次明确表示:**MCP 集成应当作为独立项目、通过 API 交互,而不是并入主仓库。**

证据:

- PR [#5981](https://github.com/searxng/searxng/pull/5981)「Add MCP service plugin for SearXNG」—— **33 分钟后关闭**,标签 `invalid:slop`
- maintainer @return42:「it uses the API and can therefore be managed in a separate project」
- maintainer @inetol:「There are already several MCP servers built on top of sxng as standalone projects (**which is how it should be**)」

**本项目是有意采用「同进程内嵌」形态的独立派生镜像**,在 AGPL 许可范围内有权这么做,但这是有意识的取舍(换取单容器、单进程、单端口),不是对上游立场的无视。
