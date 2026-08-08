# AGENTS.md — RightScreen

所有在本仓库工作的 AI 均须遵守以下规则。

**产品规格**以 `docs/PRODUCT.md` 为唯一权威；本文件只管工程实现与交付协作。若实现与产品文档冲突，**以 `docs/PRODUCT.md` 为准**，并在回复中指出冲突。

---

## 工程约束

1. 只改本仓库；技术栈与架构对齐 `docs/PRODUCT.md` §3–§4：Swift + AppKit；AX + CGWindowList；禁止 Electron / Tauri / WebView 做布局核心。
2. 代码以可维护、可测试的小模块提交；布局分配逻辑尽量纯函数 + 单测（Swift Testing / XCTest）。
3. 用户可见文案以中文为主；错误提示要可读。
4. 不添加无关文档膨胀；产品说明放 `docs/`，本文件只保留 Agent 规则。
5. 不提交密钥、证书私钥、公证凭据。
6. 未要求时不做签名/公证/打包以外的发布工程；本地 `run` 能验证 MVP 即可。

---

## AI 工作方式

1. 先读 `docs/PRODUCT.md` 与本文件；每次只做当前要求的切片，不要一次实现 P1/P2。
2. 先打通：权限 → 枚举窗口 → 改一个窗口 frame → 再做二分 → 再做 Tab → 再做四等分。
3. 遇到 AX 兼容问题：加 bundle 级兼容，而不是删掉核心功能。
4. 回复用简体中文；代码标识符用英文。
5. 变更后说明：改了什么、如何手动验证（菜单路径 + 预期现象）。

---

## AI 生成文档命名

- 文件名：`<原文件名>-<AI名称>-<YYYYMMDD>.<扩展名>`（如 `architecture-cursor-20260808.md`）。
- `<原文件名>` 用语义名称；`<AI名称>` 小写（`codex`、`cursor`）；日期为当天 8 位数字。

---

## Git 交付

改完代码后直接交付，不要询问是否提交或推送。用户说「先别提交 / 先别推送」时除外。

### 单任务

1. 检查 `git status`、`git diff`；按风险跑 lint / build / test。
2. 只暂存本任务相关文件（禁止 `git add .` / `git add -A`）；勿提交 secret、环境文件、缓存、构建产物。
3. commit 后安全同步并 push 到 `origin/master`；禁止 force push。
4. 确认本地 `master` 与 `origin/master` 同一 commit。

### 并行任务

两个及以上改代码任务须各自用独立 worktree 与 `codex/<简短任务名>` 分支。

- 各任务只在自己的 worktree 里改、验、提交；分支不得自行 push 到 `origin/master`。
- 只有集成任务在干净主 worktree 合并、验证并 push。
- 可能改同一核心文件的任务应拆分或串行。
- 集成前更新 `origin/master`，只允许安全 fast-forward 或 rebase。
- 只读排查/评审可共用主工作区，但不得改、提交或推送。

### Commit message

```text
<序号>.<type>: <中文主题>，<中文说明>
```

- `序号`：历史中整数前缀最大值加一。
- `type`：`feat` / `fix` / `refactor` / `docs` / `chore` 等。
