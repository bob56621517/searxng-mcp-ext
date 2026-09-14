# 领域文档

工程类 skill 在探索代码库时,应如何消费本仓库的领域文档。

## 探索之前,先读这些

- 仓库根目录的 **`CONTEXT.md`**,或
- 仓库根目录的 **`CONTEXT-MAP.md`**(如果它存在):它指向每个 context 各自的 `CONTEXT.md`。读取与当前主题相关的每一个。
- **`docs/adr/`**:读取与即将工作的区域相关的 ADR。在多 context 仓库中,还要检查 `src/<context>/docs/adr/` 里的 context 级决策。

如果这些文件不存在,**静默继续**。不要指出它们的缺失,也不要建议提前创建。`/domain-modeling` skill(经由 `/grill-with-docs` 和 `/improve-codebase-architecture` 触达)会在术语或决策真正被敲定时按需创建它们。

## 文件结构

单 context 仓库(大多数仓库):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多 context 仓库(根目录存在 `CONTEXT-MAP.md` 时):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context 专属决策
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## 使用术语表里的词汇

当你的输出要命名某个领域概念时(在 issue 标题、重构提案、假设、测试名称中),使用 `CONTEXT.md` 中定义的术语。不要漂移到术语表明确避免的同义词。

如果你需要的概念还不在术语表里,那是个信号:要么你在发明项目并不使用的语言(重新考虑),要么存在真实空缺(记下来交给 `/domain-modeling`)。

## 标出 ADR 冲突

如果你的输出与某个既有 ADR 相矛盾,显式提出来,而不是静默覆盖:

> _与 ADR-0007(event-sourced orders)相矛盾,但值得重新讨论,因为……_
