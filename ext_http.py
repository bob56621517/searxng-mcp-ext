# SPDX-License-Identifier: AGPL-3.0-or-later
"""ASGI 组合入口:在同一个进程里同时提供 SearXNG 与 MCP 端点。

SearXNG 原生的 WSGI 应用被原样包裹在 WSGI-to-ASGI 适配中间件里挂在根路径,
MCP 的 Streamable HTTP 端点挂在 ``/ext/mcp``。

启动方式(替代官方 entrypoint 的最后一行):

    granian --interface asgi ext_http:app
"""

from __future__ import annotations

import os
from typing import Any
from urllib.parse import urlparse

import httpx
from starlette.applications import Starlette
from starlette.middleware.wsgi import WSGIMiddleware
from starlette.routing import Mount
from mcp.server import MCPServer
from mcp.types import CallToolResult, TextContent

# SearXNG 原生应用:Flask(WSGI)。此处不做任何修改,只做包装。
from searx.webapp import app as searxng_wsgi_app

# MCP SDK 内部的默认端点是 /mcp,因此外层挂载点取 /ext 即可拼出对外的 /ext/mcp。
MCP_MOUNT = "/ext"

# 工具通过 HTTP 自调用同进程的 SearXNG 服务,而不是直接调用其内部 API ——
# 这样不依赖 SearXNG 的私有实现,上游升级不会导致工具失效。
SEARXNG_BASE_URL = os.environ.get("SEARXNG_INTERNAL_URL", "http://127.0.0.1:8080")

DEFAULT_COUNT = 20
MAX_COUNT = 50

# 取值由镜像内的引擎清单唯一决定(见 searxng/settings.yml)。
# 这是封闭集合,所以用固定枚举而不是动态探测。
VALID_CATEGORIES = ("general", "it", "repos", "code", "videos", "news", "images")
VALID_TIME_RANGES = ("day", "week", "month", "year")

# 某些引擎返回的不是真实 URL,而是需要浏览器才能解开的跳转链接。
# 命中的结果会带上 fetch_url_mode 提示,告知调用方(及后续的抓取工具)
# 该 URL 不能用普通 HTTP 读取。
BROWSER_ONLY_HOSTS = ("chinaso.com",)

mcp = MCPServer("searxng-ext")


@mcp.tool()
def ping() -> str:
    """冒烟测试用:确认 MCP 端点可达。"""
    return "pong"


async def _fetch_from_searxng(
    query: str,
    time_range: str | None,
    categories: str | None,
) -> list[dict[str, Any]]:
    """向同进程的 SearXNG 发起一次 JSON 搜索,返回原始结果列表。"""
    params: dict[str, str] = {"q": query, "format": "json"}
    if time_range:
        params["time_range"] = time_range
    if categories:
        params["categories"] = categories

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(f"{SEARXNG_BASE_URL}/search", params=params)
        response.raise_for_status()
        payload = response.json()

    return payload.get("results") or []


def _normalize(results: list[dict[str, Any]], count: int) -> list[dict[str, Any]]:
    """把 SearXNG 的结果裁剪并归一化成搜索结果协议三元组。

    额外规则:URL 属于需要浏览器才能读取的引擎时,附带 fetch_url_mode 提示。
    """
    normalized: list[dict[str, Any]] = []
    for item in results:
        url = item.get("url")
        if not url:
            continue

        entry: dict[str, Any] = {
            "url": url,
            "title": item.get("title") or "",
            "content": item.get("content") or "",
        }

        hostname = (urlparse(url).hostname or "").lower()
        if any(hostname == h or hostname.endswith("." + h) for h in BROWSER_ONLY_HOSTS):
            entry["fetch_url_mode"] = "browser"

        normalized.append(entry)
        if len(normalized) >= count:
            break

    return normalized


def _render_markdown(results: list[dict[str, Any]]) -> str:
    """把结果渲染成人类与模型都易读的 Markdown 文本。"""
    if not results:
        return "没有找到网页结果。"

    blocks: list[str] = []
    for index, item in enumerate(results, start=1):
        title = item.get("title") or item["url"]
        block = f"{index}. [{title}]({item['url']})"
        content = item.get("content")
        if content:
            block += f"\n{content}"
        blocks.append(block)

    return "\n\n".join(blocks)


@mcp.tool()
async def web_search(
    query: str,
    count: int = DEFAULT_COUNT,
    time_range: str | None = None,
    categories: str | None = None,
) -> CallToolResult:
    """通过 SearXNG 聚合搜索网页。

    参数:
        query: 搜索词。
        count: 返回结果条数,1-50,默认 20。
        time_range: 时间范围,可选 day / week / month / year。
        categories: 结果分类,可选 general / it / repos / code / videos / news / images。

    返回值同时包含人类可读的 Markdown 文本(content)与结构化的搜索结果三元组
    {url, title, content}(structuredContent.results)。若某条结果需要浏览器才能
    读取,它会额外带有 fetch_url_mode="browser" 字段。
    """
    clamped = max(1, min(count, MAX_COUNT))

    if time_range and time_range not in VALID_TIME_RANGES:
        raise ValueError(
            f"无效的 time_range: {time_range}。可选值:{', '.join(VALID_TIME_RANGES)}"
        )
    if categories and categories not in VALID_CATEGORIES:
        raise ValueError(
            f"无效的 categories: {categories}。可选值:{', '.join(VALID_CATEGORIES)}"
        )

    raw = await _fetch_from_searxng(query, time_range, categories)
    results = _normalize(raw, clamped)

    # 显式构造结果:文本侧给模型读,结构化侧给下游程序取。
    return CallToolResult(
        content=[TextContent(type="text", text=_render_markdown(results))],
        structured_content={"results": results},
    )


# Streamable HTTP 的 ASGI 应用。
# 注意:生命周期钩子挂在 router 上 —— Starlette 实例本身没有 .lifespan 属性。
# 必须转交给外层应用,否则会话管理器不会被初始化,请求会失败。
mcp_asgi_app = mcp.streamable_http_app()

app = Starlette(
    routes=[
        Mount(MCP_MOUNT, app=mcp_asgi_app),
        Mount("/", app=WSGIMiddleware(searxng_wsgi_app)),
    ],
    lifespan=mcp_asgi_app.router.lifespan_context,
)
