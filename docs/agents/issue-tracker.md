# Issue 载体:GitHub

本仓库的 issue 与 spec 都作为 GitHub issue 存在。所有操作统一使用 `gh` CLI。

## 约定

- **创建 issue**:`gh issue create --title "..." --body "..."`。多行正文使用 heredoc。
- **读取 issue**:`gh issue view <number> --comments`,用 `jq` 过滤评论,并同时取回标签。
- **列出 issue**:`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`,配合适当的 `--label` 与 `--state` 过滤条件。
- **评论 issue**:`gh issue comment <number> --body "..."`
- **添加 / 移除标签**:`gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **关闭**:`gh issue close <number> --comment "..."`

仓库由 `git remote -v` 推断;在克隆目录内运行 `gh` 时会自动完成推断。

## 把 Pull Request 作为 triage 输入面

**PR 作为请求输入面:否。** _(如果本仓库把外部 PR 视为功能请求,就改成 `是`;`/triage` 会读取这个开关。)_

设为 `是` 时,PR 会走与 issue 相同的标签与状态流程,使用对应的 `gh pr` 命令:

- **读取 PR**:`gh pr view <number> --comments`,用 `gh pr diff <number>` 查看 diff。
- **列出待 triage 的外部 PR**:`gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`,然后只保留 `authorAssociation` 为 `CONTRIBUTOR`、`FIRST_TIME_CONTRIBUTOR` 或 `NONE` 的条目(丢弃 `OWNER`/`MEMBER`/`COLLABORATOR`)。
- **评论 / 打标签 / 关闭**:`gh pr comment`、`gh pr edit --add-label`/`--remove-label`、`gh pr close`。

GitHub 的 issue 与 PR 共用同一套编号空间,所以单独的 `#42` 可能是两者之一:先用 `gh pr view 42` 解析,失败再回落到 `gh issue view 42`。

## 当某个 skill 说"发布到 issue 载体"

创建一个 GitHub issue。

## 当某个 skill 说"获取相关工单"

执行 `gh issue view <number> --comments`。

## Wayfinding 操作

由 `/wayfinder` 使用。**map** 是单个 issue,**child** issue 作为其下的 ticket。

- **Map**:单个带 `wayfinder:map` 标签的 issue,承载 Notes / Decisions-so-far / Fog 正文。`gh issue create --label wayfinder:map`。
- **Child ticket**:一个链接到 map 的 issue,作为 GitHub sub-issue 挂上去(`gh api` 调 sub-issues 端点)。若 sub-issues 未启用,则把 child 加入 map 正文的任务列表,并在 child 正文顶部写 `Part of #<map>`。标签:`wayfinder:<type>`(`research`/`prototype`/`grilling`/`task`)。被认领后,该 ticket 指派给负责推进的开发者。
- **阻塞关系**:使用 GitHub **原生 issue 依赖**,这是规范且 UI 可见的表示方式。用 `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>` 添加边,其中 `<blocker-db-id>` 是阻塞方的数字**数据库 id**(`gh api repos/<owner>/<repo>/issues/<n> --jq .id`,**不是** `#number` 或 `node_id`)。GitHub 通过 `issue_dependencies_summary.blocked_by` 报告阻塞方(仅统计未关闭的,即当前的实时门禁)。依赖功能不可用时,回落到在 child 正文顶部写一行 `Blocked by: #<n>, #<n>`。当所有阻塞方都已关闭时,ticket 解除阻塞。
- **Frontier 查询**:列出 map 下未关闭的 child(`gh issue list --state open`,限定在该 map 的 sub-issues / 任务列表范围内),剔除任何存在未关闭阻塞方的(`issue_dependencies_summary.blocked_by > 0`,或 `Blocked by` 行里有未关闭 issue)或已有 assignee 的;按 map 顺序取第一个。
- **认领**:`gh issue edit <n> --add-assignee @me`,这是本 session 的第一次写入。
- **解决**:`gh issue comment <n> --body "<answer>"`,然后 `gh issue close <n>`,再把一个上下文指针(gist + 链接)追加到 map 的 Decisions-so-far。
