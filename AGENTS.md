# AGENTS.md — RightScreen

你正在开发 **RightScreen**：macOS 菜单栏窗口管理工具。本文件是产品与工程的唯一权威约束；实现前必读，实现中不得偏离。

---

## 0. 一句话目标

用户通过菜单栏图标（或快捷键）一点，把当前 Space 上所有可管理窗口自动分成 **左右二分** 或 **上下左右四等分**；每个窗格顶部有 **Tab 栏**，可在该格内的多个窗口间切换。

对标：[BetterStage](https://betterstage.app/) 的 **Tabbed Layout Mode** 子集。不做完整 BetterStage。

---

## 1. 产品范围

### 1.1 必须做（MVP / P0）

1. macOS 菜单栏常驻 Agent（`LSUIElement`），无 Dock 主窗口也可工作。
2. 菜单项至少包含：
   - 左右二分屏（Split 2）
   - 四等分屏（Split 4）
   - 退出当前布局（还原窗口位置，尽力而为）
   - 打开辅助功能（Accessibility）权限引导
   - 退出应用
3. 进入布局时：
   - 枚举当前 Space 上可管理的普通 App 窗口
   - 按策略均分到各窗格（例：6 窗 + 二分 → 左 3 / 右 3）
   - 每格只显示「当前 Tab」对应窗口；同格其他窗口不可见
   - 每格上方显示原生 Tab 栏，点击可切换
4. 仅申请 **Accessibility** 权限；不禁用 SIP；不要求 Input Monitoring / Screen Recording（除非后续明确需要）。
5. 最低系统：macOS 14 Sonoma+；支持 Apple Silicon（Intel 可选）。

### 1.2 明确不做（当前阶段禁止实现）

- 完整 Stage / 工作区切换（BetterStage Stages）
- Bento Box 全窗口平铺网格
- AI 布局 / Recipe
- Electron / Tauri / WebView 作为窗口管理核心
- 基于 RightBase（Tauri Git/AI 宿主）做底座或把本功能塞进 RightBase
- 依赖 yabai 式私有 API / 关闭 SIP
- 解析各 App 内部原生 Tab（Safari/Finder 标签页）；一律按「整窗」管理
- 强制接管全屏窗口、系统原生 Split View（可提示用户先退出全屏）

### 1.3 可后续做（P1/P2，未经要求不要提前做）

- 可配置快捷键、排除名单、多显示器策略
- 新窗口自动并入当前布局
- 命名布局保存/恢复、拖拽换格、Tab 重排

---

## 2. 用户故事与行为规格

### 2.1 主路径

```text
用户打开多个 App 窗口
  → 点击菜单栏 RightScreen →「左右二分」
  → 系统请求/确认 Accessibility（若未授权）
  → 窗口被分配到左/右两格，每格出现 Tab 栏
  → 用户点某格 Tab → 该格切换显示对应窗口
  →「退出布局」→ 窗口尽量回到进入布局前的 frame
```

### 2.2 窗口分配规则（默认）

- 输入：可管理窗口列表（过滤后），按最近使用或稳定 Z 序排序。
- Split 2：两格；窗口轮流或均分到 left / right（余数给左侧或按序补齐，实现时固定一种并写测试/注释）。
- Split 4：四格（左上、右上、左下、右下）；均分，余数按格顺序从前到后多分配 1 个。
- 每格内窗口顺序 = Tab 顺序；默认选中每格第一个 Tab。
- 空窗口数：无窗口时 toast/菜单提示，不创建空布局。

### 2.3 可管理窗口过滤（必须）

排除至少：

- 本应用自身窗口 / Tab 浮层
- Dock、菜单栏、壁纸、屏保、通知中心类系统 UI
- `kCGWindowLayer` 异常高/低的非标准窗（按经验表维护）
- 最小化窗口（MVP 可忽略；或进入布局时跳过）
- 其他 Space 的窗口（只管当前 Space）

保留：普通可激活 App 的标准文档/应用窗口。

### 2.4 Tab 切换行为

- 点击 Tab：目标窗口 `raise` 并置于该格 frame；同格其他窗口隐藏（策略见 §4）。
- Tab 标题：优先窗口标题，空则用 App 名。
- Tab 栏不得严重抢焦点：使用非 activating 的 `NSPanel` 一类方案，再对目标窗做 AX raise。

### 2.5 退出布局

- 停止托管；销毁/隐藏所有 Tab 浮层。
- 将仍存活的窗口尽量恢复进入布局前记录的 `frame`。
- 已关闭的窗口跳过；不崩溃。

---

## 3. 技术选型（强制）

| 项 | 选择 |
| --- | --- |
| 语言 | **Swift** |
| UI | **AppKit**（菜单栏、`NSPanel` Tab 条）；设置页可用 SwiftUI |
| 窗口操作 | Accessibility（`AXUIElement`）：位置、尺寸、raise、显隐 |
| 窗口枚举 | `CGWindowListCopyWindowInfo` + AX 映射 |
| 可选库 | AXSwift / Swindler（允许）；禁止引入 Electron/Tauri |
| 形态 | Menu bar Agent（`LSUIElement = true`） |
| 工程 | 本仓库独立 Xcode / SwiftPM 工程；与 RightBase **进程与仓库职责分离** |

禁止：用 React/WebView 实现 Tab 条或布局核心逻辑。

---

## 4. 架构（实现必须对齐）

```text
StatusItemController     菜单栏入口与菜单动作
Permissions              Accessibility 检测与引导
WindowIndexer            CG+AX 枚举、过滤、ID 映射
LayoutEngine             Split2/Split4 几何 + 窗口→窗格分配
WindowController         setFrame / raise / hide 的统一出口
PaneTabBarPanel          每格一条浮层 Tab UI
LayoutSession            本次会话：原 frame、格→窗口列表、当前 Tab
```

### 4.1 隐藏同格非活动窗口的策略（按优先级尝试）

1. 优先：移出可视区域（保留 AX 可操作）或 `AXHidden`（若目标 App 支持）
2. 某 App 表现异常时：对该 bundle id 使用回退策略（记录在兼容表）
3. 禁止：杀死进程、强制 Quit、乱发 Cmd+W

### 4.2 几何

- 基于目标屏的 `visibleFrame`（扣除菜单栏/Dock）计算格位。
- 每格顶部预留 Tab 条高度（常量，如 28–36pt），窗口 frame 为「格位减去 Tab 条」。
- Tab 条 `NSPanel` 贴在格位顶部，随布局更新。

### 4.3 建议目录

```text
RightScreen/
├── App/           # AppDelegate, StatusItem, Permissions
├── Windowing/     # Indexer, Controller, AX helpers
├── Layout/        # LayoutKind, Engine, Assignment
├── Chrome/        # PaneTabBarPanel
├── Store/         # LayoutSession
└── Resources/     # Info.plist, Assets
```

---

## 5. 工程与交付约束

1. **只改本仓库** RightScreen；不要去改 RightBase 来实现本功能。
2. 代码以可维护、可测试的小模块提交；布局分配逻辑尽量纯函数 + 单测（Swift Testing / XCTest）。
3. 用户可见文案：中文为主（可后续 i18n）；错误提示要可读。
4. 不添加无关文档/README 膨胀；必要说明放本文件或 `docs/` 短文。
5. 不提交密钥、证书私钥、公证凭据。
6. 未要求时不要做签名/公证/打包脚本以外的发布工程；本地 `run` 能验证 MVP 即可。
7. Commit 仅在用户明确要求时创建。

---

## 6. AI 实现时的工作方式

1. 先读本文件；若需求与本文件冲突，**以本文件为准**，并在回复中指出冲突。
2. 每次任务只做用户当前要求的切片；不要一次实现 P1/P2。
3. 先打通：权限 → 枚举窗口 → 改一个窗口 frame → 再做二分 → 再做 Tab → 再做四等分。
4. 遇到 AX 兼容问题：加 bundle 级兼容，而不是删掉核心功能。
5. 回复用户使用简体中文；代码标识符用英文。
6. 变更后说明：改了什么、如何手动验证（菜单路径 + 预期现象）。

---

## 7. 验收标准（Done Definition）

同时满足才可称 MVP 完成：

- [ ] 未授权时有清晰引导进入系统设置 → Privacy → Accessibility
- [ ] ≥6 个普通窗口时，「左右二分」得到两格，窗口大致均分，每格有 Tab 且可切换，同时每格只见一窗
- [ ] 「四等分」得到四格，行为同上
- [ ] 「退出布局」后 Tab 消失，窗口大体回到原位置
- [ ] 不禁用 SIP；Info/权限模型仅为 Accessibility
- [ ] 空闲时无明显 CPU 占用；无 WebView 依赖

---

## 8. 给下一轮 AI 的启动提示词（可直接粘贴）

```text
按仓库根目录 AGENTS.md 实现 RightScreen。

当前任务：<在此填写具体切片，例如：创建 Swift 菜单栏空壳 + Accessibility 权限检测>

约束摘要：
- Swift + AppKit 菜单栏 Agent，对标 BetterStage Tabbed Layout 子集
- MVP：二分 / 四等分 + 每格 Tab 切换 + 退出还原
- 用 AX + CGWindowList；禁止 Electron/Tauri/基于 RightBase
- 不要做 Stages、Bento、AI 布局
- 用简体中文回复；先最小可运行再迭代
```

---

## 9. 参考（只读理解，勿复制其授权/品牌）

- BetterStage：https://betterstage.app/ （Tabbed Layout 行为参考）
- AXSwift / Swindler：Accessibility 封装参考
- 竞品边界：Rectangle（吸附）≠ 本产品；本产品 = 分屏窗格 + 窗格内 Tab
