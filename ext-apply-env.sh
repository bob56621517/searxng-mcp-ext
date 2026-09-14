#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# 在启动 granian 之前,把环境变量应用到 /etc/searxng/settings.yml。
#
# 由官方 entrypoint 的 exec 行调用(见 Dockerfile 里的 sed 注入)。
#
# 支持的变量 —— 全部可选,一个都不设时本脚本什么都不改:
#
#   SEARXNG_ENGINES          引擎白名单(逗号分隔),整体替换默认清单
#   SEARXNG_ENGINES_EXCLUDE  从清单中剔除的引擎(逗号分隔)
#   GITHUB_TOKEN             github code 引擎认证;未设则回退匿名模式
#   BRAVE_API_KEY            braveapi 引擎密钥;未设则保持不启用
#
# 设计取向:引擎的启用与否是**部署决策**(关系到出网信誉、付费额度、反爬风险),
# 因此只由配置决定,不暴露为 MCP 工具参数。

set -eu

TARGET="${__SEARXNG_SETTINGS_PATH:-/etc/searxng/settings.yml}"

if [ ! -f "$TARGET" ]; then
    echo "[ext] 未找到 $TARGET,跳过环境变量注入"
    exit 0
fi

python3 - "$TARGET" <<'PYEOF'
import os
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    text = fh.read()

original = text

# ---------------- 1. 引擎清单 ----------------
BEGIN = "# >>> ext:keep-only:begin"
END = "# >>> ext:keep-only:end"

wanted = os.environ.get("SEARXNG_ENGINES", "").strip()
excluded = os.environ.get("SEARXNG_ENGINES_EXCLUDE", "").strip()

if BEGIN in text and END in text:
    span = re.search(re.escape(BEGIN) + r"(.*?)" + re.escape(END), text, re.S)
    if span:
        # 取当前清单作为基線(不设 SEARXNG_ENGINES 时只是做剔除)
        current = [
            line.strip()[2:].strip()
            for line in span.group(1).splitlines()
            if line.strip().startswith("- ")
        ]
        if wanted:
            current = [e.strip() for e in wanted.split(",") if e.strip()]
        if excluded:
            drop = {e.strip() for e in excluded.split(",") if e.strip()}
            current = [e for e in current if e not in drop]

        body = "\n".join("      - %s" % e for e in current)
        text = (
            text[: span.start()]
            + "%s\n%s\n      %s" % (BEGIN, body, END)
            + text[span.end() :]
        )

# ---------------- 2. GitHub token ----------------
gh_token = os.environ.get("GITHUB_TOKEN", "").strip()
if gh_token:
    text = text.replace('token: "$GITHUB_TOKEN"', 'token: "%s"' % gh_token)
else:
    # 回退匿名:type 改 none,token 清空(否则 github_code 会拿占位符去认证)
    text = text.replace('type: "personal_access_token"', 'type: "none"')
    text = text.replace('token: "$GITHUB_TOKEN"', 'token: ""')

# ---------------- 3. Brave API key ----------------
brave_key = os.environ.get("BRAVE_API_KEY", "").strip()
if brave_key:
    # 用带 api_key 行的整段做匹配,避免误伤其它条目的 inactive
    text = text.replace(
        'inactive: true\n    api_key: "$BRAVE_API_KEY"',
        'inactive: false\n    api_key: "%s"' % brave_key,
    )
else:
    text = text.replace('api_key: "$BRAVE_API_KEY"', 'api_key: ""')

# ---------------- 落盘 ----------------
if text != original:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("[ext] 已按环境变量更新 settings.yml")
else:
    print("[ext] 环境变量未变化,settings.yml 保持原样")
PYEOF
