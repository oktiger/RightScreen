# RightScreen 产品说明

macOS 菜单栏窗口管理工具。提供两种互斥布局模式：

1. **Tab Mode**：固定窗格预设（全屏 / 二分 / 三等分 / 四等分等）；每格可叠多个窗口，顶部 **Tab 栏**切换。
2. **Grid Mode（网格模式）**：BSP 自动平铺；**一窗一格、全部可见、无 Tab**；格间可拖分隔条，拖动时显示 Icon + 尺寸预览。

对标：[BetterStage](https://betterstage.app/) 的 **Tabbed Layout Mode** 与 **Bento Box** 子集。不做完整 BetterStage（Stages / Recipe / AI 等）。

工程实现与 AI 协作约束见仓库根目录 `AGENTS.md`。

---

## 1. 产品范围

### 1.1 必须做（MVP / P0）

1. macOS 菜单栏常驻 Agent；菜单按分类展示：
   - **Tab Mode**：全屏、左右二分、左右三等分、上下二分、1+2、2+1、四等分
   - **Grid Mode**：网格（唯一项）
   - 退出当前布局（还原窗口位置，尽力而为）
   - 快捷键设置（Tab 换格箭头、全屏菜单）
   - 打开辅助功能（Accessibility）权限引导
   - 退出应用
2. **Tab Mode** 进入布局时：
   - 枚举当前 Space 上可管理的普通 App 窗口
   - 按策略均分到各窗格（例：6 窗 + 二分 → 左 3 / 右 3）
   - 每格只显示「当前 Tab」对应窗口；同格其他窗口不可见
   - 每格上方显示原生 Tab 栏，点击可切换
   - 可为 Tab 栏换格箭头配置全局快捷键（左 / 右 / 上 / 下）；语义与点击对应箭头完全相同，仅在 Tab Mode 中生效
   - 可为菜单「全屏」配置全局快捷键，语义与点该菜单项相同
3. **Grid Mode（网格模式）** 进入布局时：
   - 枚举当前 Space 可管理窗口，按 BSP 自动平铺（1 整屏 / 2 左右 / 3 左整高+右上下 / 4+ 继续二分）
   - 无 Tab；每一窗口独占一格并同时可见
   - 格间显示可拖分隔条（竖/横）；拖动时显示玻璃预览（App Icon + 名称 + 宽×高），松手一次提交 frame
   - 默认格间距 8pt
4. Tab 与网格模式 **互斥**：启动其一前退出另一模式。
5. 仅申请 **Accessibility** 权限；不禁用 SIP；不要求 Input Monitoring / Screen Recording（除非后续明确需要）。全局快捷键用系统热键注册，不监听全部按键。
6. 最低系统：macOS 14 Sonoma+；支持 Apple Silicon（Intel 可选）。

### 1.2 明确不做（当前阶段禁止实现）

- 完整 Stage / 工作区切换（BetterStage Stages）
- 网格模式的 drop-to-swap、边插入新分割、Fill 放大、跨屏拖入（可后续做）
- AI 布局 / Recipe
- Electron / Tauri / WebView 作为窗口管理核心
- 基于 RightBase（Tauri Git/AI 宿主）做底座或把本功能塞进 RightBase
- 依赖 yabai 式私有 API / 关闭 SIP
- 解析各 App 内部原生 Tab（Safari/Finder 标签页）；一律按「整窗」管理
- 强制接管全屏窗口、系统原生 Split View（可提示用户先退出全屏）

### 1.3 可后续做（P1/P2，未经要求不要提前做）

- 网格模式 / 其它布局菜单 / 退出布局的可配置快捷键、排除名单、多显示器策略、网格间距
- 网格模式：拖窗交换、边插入、Fill、Retile
- 新窗口自动并入当前布局（Tab / 网格模式已有基础可增强）
- 命名布局保存/恢复、拖拽换格、Tab 重排

---

## 2. 用户故事与行为规格

### 2.1 Tab Mode 主路径

```text
用户打开多个 App 窗口
  → 菜单栏 RightScreen → Tab Mode →「左右二分」
  → 系统请求/确认 Accessibility（若未授权）
  → 窗口被分配到左/右两格，每格出现 Tab 栏
  → 用户点某格 Tab → 该格切换显示对应窗口
  →「退出布局」→ 窗口尽量回到进入布局前的 frame
```

### 2.2 Grid Mode（网格模式）主路径

```text
用户打开多个 App 窗口
  → 菜单栏 RightScreen → Grid Mode →「网格」
  → 窗口按 BSP 平铺，全部可见，格间有分隔条
  → 拖分隔条 → 出现 Icon 玻璃预览 → 松手后窗口落到新尺寸
  →「退出布局」→ 预览/把手消失，窗口尽量还原
```

### 2.3 Tab 窗口分配规则（默认）

- 输入：可管理窗口列表（过滤后），按最近使用或稳定 Z 序排序。
- Split 2：两格；窗口轮流或均分到 left / right（余数给左侧或按序补齐，实现时固定一种并写测试/注释）。
- Split 3：三格（左、中、右等宽）；均分，余数按格顺序从前到后多分配 1 个。
- Split 4：四格（左上、右上、左下、右下）；均分，余数按格顺序从前到后多分配 1 个。
- 每格内窗口顺序 = Tab 顺序；默认选中每格第一个 Tab。
- 空窗口数：无窗口时 toast/菜单提示，不创建空布局。

### 2.4 网格模式平铺规则（默认）

- 平衡 BSP：深度偶数左右切，奇数上下切；3 窗自然为「左整高 + 右上下」。
- 拖竖条改左右（或该 split 左右子树）宽度比；拖横条改上下高度比；比例钳制保证最小格宽/高。
- 拖动中不逐步 AX resize；松手一次提交。

### 2.5 可管理窗口过滤（必须）

排除至少：

- 本应用自身窗口 / Tab 浮层 / 网格模式把手与预览
- Dock、菜单栏、壁纸、屏保、通知中心类系统 UI
- `kCGWindowLayer` 异常高/低的非标准窗（按经验表维护）
- 最小化窗口（MVP 可忽略；或进入布局时跳过）
- 其他 Space 的窗口（只管当前 Space）

保留：普通可激活 App 的标准文档/应用窗口。

### 2.6 Tab 切换行为

- 点击 Tab：目标窗口 `raise` 并置于该格 frame；同格其他窗口隐藏（策略见架构说明）。
- Tab 标题：默认优先 App 名，空则用窗口标题；Chrome 系列显示“App 名：标签/窗口标题”。
- Tab 栏不得严重抢焦点：使用非 activating 的 `NSPanel` 一类方案，再对目标窗做 AX raise。
- 换格快捷键：对当前聚焦 Tab 执行该方向的箭头；该格没有对应箭头时忽略。未进入 Tab Mode 时四向快捷键不生效。
- 换格箭头仅显示合法相邻格：左右二分 / 左右三等分仅水平（三等分中格可左右，左右格各只朝向中间）；上下二分仅垂直；1+2 / 2+1 / 四等分按格位邻接。
- **每格记住最近使用的 Tab（MRU）**。关闭或把当前 Tab 换到邻格后，该格回到上一工作窗口，而不是第一个 Tab。
- **新窗口按落点并入窗格**，成为该格当前 Tab。Tab Mode 下从一格拖到另一格时，目标格显示淡蓝半透明蒙版（忽略鼠标，不抢 Chrome 松手）。松手后把新窗口并入蒙版所在格并铺满该格。拖动尚未松手时不 raise / 不改 frame。若没有跨格拖放，仍按窗口中心点（否则相交面积，否则焦点格）并入。典型路径：从 Chrome 拖出标签移到右半屏 → 右格出现淡蓝蒙版 → 松手后新窗口成为右格当前 Tab 并铺满右半屏，左格继续显示原窗口。不解析 Chrome 内部标签，只把拖出后的新窗口当整窗管理。若用户尚未点选该 Tab 就把它换到邻格，焦点回到源格上一工作窗口（例：左格正在用 3 号，新软件变成 4 号并激活，把 4 号移到右侧后，左侧回到 3 号并继续操作）。若用户先点选了该 Tab 再换格，焦点跟随被移动的窗口；源格仍显示上一工作窗口。

### 2.7 退出布局

- 停止托管；销毁/隐藏所有 Tab 浮层与网格模式把手/预览。
- 将仍存活的窗口尽量恢复进入布局前记录的 `frame`。
- 已关闭的窗口跳过；不崩溃。

---

## 3. 技术选型（强制）

| 项 | 选择 |
| --- | --- |
| 语言 | **Swift** |
| UI | **AppKit**（菜单栏、`NSPanel` Tab 条 / 网格模式把手与预览）；设置页可用 SwiftUI |
| 窗口操作 | Accessibility（`AXUIElement`）：位置、尺寸、raise、显隐 |
| 窗口枚举 | `CGWindowListCopyWindowInfo` + AX 映射 |
| 可选库 | AXSwift / Swindler（允许）；禁止引入 Electron/Tauri |
| 形态 | Menu bar Agent（可按产品需要调整激活策略） |
| 工程 | 本仓库独立 Xcode / SwiftPM 工程；与 RightBase **进程与仓库职责分离** |

禁止：用 React/WebView 实现 Tab 条、网格模式预览或布局核心逻辑。

---

## 4. 架构（实现必须对齐）

```text
StatusItemController     菜单栏入口（Tab Mode / Grid Mode 分类）
Permissions              Accessibility 检测与引导
WindowIndexer            CG+AX 枚举、过滤、ID 映射
LayoutEngine             Tab 预设几何 + 窗口→窗格分配
BentoEngine              BSP 树构建 / 布局 / 分隔比例
WindowController         setFrame / raise / hide 的统一出口
PaneTabBarPanel          Tab Mode：每格一条浮层 Tab UI
PaneDropOverlayPanel     Tab Mode：跨格拖放时的淡蓝落点蒙版
BentoDividerController   网格模式：分隔条把手
BentoPreviewPanel        网格模式：拖动时 Icon 玻璃预览
LayoutSession            Tab 会话
BentoSession             网格模式会话
LayoutCoordinator        两种模式的启动 / 刷新 / 退出
HotKeyCenter             全局快捷键注册（Carbon）
HotKeySettingsStore      快捷键持久化
HotKeySettings           快捷键设置窗（SwiftUI）
```

### 4.1 隐藏同格非活动窗口的策略（Tab Mode，按优先级尝试）

1. 优先：同格窗口保持相同 frame，切换时仅 `raise` 当前 Tab，避免窗口在屏幕内外来回移动
2. 某 App 无法可靠通过窗口层级覆盖时：对该 bundle id 使用移出可视区域或 `AXHidden` 回退（记录在兼容表）
3. 禁止：杀死进程、强制 Quit、乱发 Cmd+W

### 4.2 几何

- 基于目标屏的 `visibleFrame`（扣除菜单栏/Dock）计算格位。
- Tab Mode：每格顶部预留 Tab 条高度（常量，如 28–36pt），窗口 frame 为「格位减去 Tab 条」。
- Grid Mode：叶节点 frame 直接铺满格位（扣 gap）；无 Tab 条预留。

### 4.3 建议目录

```text
RightScreen/
├── App/           # AppDelegate, StatusItem, Permissions, Coordinator
├── Windowing/     # Indexer, Controller, AX helpers
├── Layout/        # LayoutKind, LayoutEngine, BentoEngine
├── Chrome/        # PaneTabBarPanel, PaneDropOverlay, BentoDivider, BentoPreview
├── Store/         # LayoutSession, BentoSession
├── HotKeys/       # HotKeyCenter, KeyChord, 设置存储
└── Resources/     # Info.plist, Assets
```

---

## 5. 验收标准（Done Definition）

同时满足才可称 MVP 完成：

- [ ] 未授权时有清晰引导进入系统设置 → Privacy → Accessibility
- [ ] 菜单可见 **Tab Mode** / **Grid Mode** 分类
- [ ] ≥6 个普通窗口时，Tab「左右二分」得到两格，窗口大致均分，每格有 Tab 且可切换
- [ ] Tab「左右三等分」得到左中右三格，行为同上；中格 Tab 可左右换格，左右格仅能移向中间
- [ ] Tab「四等分」得到四格，行为同上
- [ ] ≥3 个窗口时，网格模式下窗口全部可见、无 Tab；拖分隔条出现 Icon 预览，松手后尺寸更新
- [ ] 「退出布局」后浮层消失，窗口大体回到原位置
- [ ] 不禁用 SIP；Info/权限模型仅为 Accessibility
- [ ] 空闲时无明显 CPU 占用；无 WebView 依赖

---

## 6. 参考（只读理解，勿复制其授权/品牌）

- BetterStage：https://betterstage.app/ （Tabbed Layout / Bento Box 行为参考）
- BetterStage Bento 文档：https://betterstage.app/docs/bento-box
- AXSwift / Swindler：Accessibility 封装参考
- 竞品边界：Rectangle（吸附）≠ 本产品；本产品 = Tab 窗格切换 + 网格模式全可见平铺。Tab 换格快捷键只复用 Tab 栏箭头，不是独立吸附器。
