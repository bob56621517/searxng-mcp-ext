# SPDX-License-Identifier: AGPL-3.0-or-later
#
# searxng-mcp-ext
#
# 在官方 SearXNG 镜像上注入两样东西:
#   1. 自定义搜索引擎(中文源 + 付费兜底)
#   2. 内嵌的 HTTP MCP 端点(/ext/mcp)
#
# 基础镜像固定版本 tag,不做 latest 跟随。升级时只改这一处。

ARG SEARXNG_VERSION=2026.8.29-d226b78bc

FROM ghcr.io/searxng/searxng:${SEARXNG_VERSION}

USER root

# ---- 1. 安装官方 MCP SDK ----------------------------------------------------
# 上游 venv 里没有 pip 模块(只有 ensurepip),所以先引导再安装。
# 经验证:SDK 的依赖与 SearXNG 已有依赖零覆盖(httpx2 vs httpx 是两个包名)。
RUN /usr/local/searxng/.venv/bin/python -m ensurepip --upgrade >/dev/null 2>&1 \
 && /usr/local/searxng/.venv/bin/python -m pip install --no-warn-script-location mcp \
 && /usr/local/searxng/.venv/bin/python -m pip cache purge >/dev/null 2>&1 \
 || true

# ---- 2. 注入配置与自定义搜索引擎 --------------------------------------------
# settings.yml 覆盖官方的 settings.template.yml:entrypoint 首次启动时会从它
# 生成 /etc/searxng/settings.yml(并替换 secret_key 里的占位符)。
# 部署者可以挂载自己的版本到 /etc/searxng/settings.yml 来覆盖 —— entrypoint
# 检测到文件已存在就不会再覆盖。
COPY searxng/settings.yml /usr/local/searxng/settings.template.yml

# 自定义引擎与上游内置引擎并列,不覆盖整个目录
COPY searxng/engines/ /usr/local/searxng/searx/engines/

# ---- 3. 注入 ASGI 组合入口 --------------------------------------------------
COPY ext_http.py /usr/local/searxng/ext_http.py

# ---- 4. 把启动方式从 WSGI 改为 ASGI -----------------------------------------
# 不重写官方 entrypoint,只替换它的最后一行 —— 保留官方的 volume 检查、
# settings.yml 生成、权限修正等全部逻辑。
# grep 兜底:若上游改了这行导致替换失败,构建立即报错,而不是静默降级成"没有 MCP"。
RUN sed -i \
      's|granian searx\.webapp:app|granian --interface asgi ext_http:app|' \
      /usr/local/searxng/entrypoint.sh \
 && grep -q 'ext_http:app' /usr/local/searxng/entrypoint.sh \
 && echo "[build] entrypoint patched: now serving ASGI ext_http:app"

# ext_http.py 与 searx 包同在 /usr/local/searxng 下,需让 Python 能找到它
ENV PYTHONPATH=/usr/local/searxng

# 上游 dist.dockerfile 硬编码了 GRANIAN_BLOCKING_THREADS=4,而 granian 在 ASGI
# 模式下拒绝 blocking threads > 1,会导致进程直接退出。必须覆盖。
#
# 注意:这里不影响 SearXNG 的并发能力 —— WSGIMiddleware 是通过 anyio 自己的
# 线程池派发 WSGI 调用的,与 granian 的 blocking threads 是两套机制。
ENV GRANIAN_INTERFACE=asgi \
    GRANIAN_BLOCKING_THREADS=1
