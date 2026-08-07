# HTMLWallpaper 壁纸 UI 网格选择 设计文档

- 日期：2026-08-07
- 状态：已批准（待实现）→ 修订（壁纸目录改为独立数据目录）
- 插件 ID：`com.github.Moon-Haze.htmlwallpaper`

## 背景与目标

当前 HTML 壁纸插件的配置界面（`package/contents/ui/config.qml`）是一个 `Kirigami.FormLayout`，用户需**手动输入 URL** 来选择要展示的 HTML 页面。项目自带 5 个预装 HTML 壁纸，但没有可视化选择入口。

**目标**：参考 `ref/org.kde.slideshow/contents/ui/config.qml`，把「手动输入 URL」改为**缩略图网格 UI 选择**，让用户从预装壁纸中点击选择。

**明确排除的能力**：配置界面不再提供 URL 输入框。自定义网页能力通过「拖动 HTML 文件到桌面」保留（`main.qml` 的 `onOpenUrlRequested` 已实现）。

## 决策记录

| 决策点 | 选择 | 理由 |
|---|---|---|
| 选择方式 | 纯网格选择（移除 URL 输入框） | 用户明确要求 |
| 壁纸数据源 | **独立数据目录（扫描目录列表）** | 壁纸不再打进 KPackage，Arch 包安装到 `/usr/share/html-wallpapers`，与插件解耦 |
| 界面布局 | 设置在上 + **左侧扫描目录列表 + 右侧壁纸网格** | 参考官方 slideshow 插件的「Folders」目录列表 UI |
| 扫描实现 | `Qt.labs.folderlistmodel.FolderListModel` + XHR 读 JSON | 纯 QML，无需 C++ 编译 |
| UI 组件 | `KCM.GridView` / `KCM.GridDelegate` | 官方组件，观感贴近官方插件 |
| 默认扫描目录 | `/usr/share/html-wallpapers` + `~/.local/share/html-wallpapers` | 覆盖系统安装与用户本地安装两种场景 |

## 目录结构变化

```
html-wallpapers/                     # 项目根目录，独立于 KPackage
  AudioVisualizer/
  CanvasBg/
  CodeTime/
  FallingCherry/
  FetchTerminal/
```
→ CMake 通过 `install(DIRECTORY html-wallpapers/ DESTINATION share/html-wallpapers)` 安装：
- 本地开发（`CMAKE_INSTALL_PREFIX=~/.local`）→ `~/.local/share/html-wallpapers`
- Arch 包（`CMAKE_INSTALL_PREFIX=/usr`）→ `/usr/share/html-wallpapers`

`package/contents/wallpapers/` **不再存在**——壁纸数据与插件代码完全解耦。

## 架构

```
package/contents/ui/config.qml  （重写）
│
ColumnLayout
├── Kirigami.FormLayout          # 设置在上
│   ├── ZoomFactor 滑块
│   └── InsecureHTTPS 复选框
├── Kirigami.Separator
└── RowLayout
    ├── ColumnLayout             # 左侧：扫描目录列表
    │   └── ListView（Folders）
    │       ├── header: InlineViewHeader + Add 按钮
    │       └── delegate: 目录路径 + 删除按钮
    ├── Kirigami.Separator       # 垂直分隔
    └── KCM.GridView             # 右侧：壁纸缩略图网格
        └── KCM.GridDelegate（自定义）
            ├── thumbnail: 预览图 + 标题
            └── onClicked: 选中壁纸

package/contents/ui/main.qml    （已兼容，无需再改）
html-wallpapers/                （独立数据目录，不随 KPackage）
package/contents/config/main.xml（新增 SlidePaths 配置项）
```

## 数据流

1. **目录列表**：`cfg_SlidePaths`（StringList）存扫描目录；为空时回退默认两目录
   - `/usr/share/html-wallpapers`（Arch 系统安装）
   - `~/.local/share/html-wallpapers`（用 `QtCore.StandardPaths.writableLocation(GenericDataLocation)` 解析用户数据目录）
2. **多目录扫描**：对每个目录，`FolderListModel` 枚举其子目录；串行处理，目录不存在时用 `Timer` 超时兜底防卡死
3. 对每个子目录用 `XMLHttpRequest` 读 `project.json` → `title` / `preview` / `file`
4. 组装 `ListModel`（roles：`title`、`previewUrl`、`pagePath`）喂给 `KCM.GridView`
5. 点击 delegate → `cfg_DisplayPage` 存**绝对 `file://` URL**，并高亮当前项

## 配置存储与兼容性

新增配置项 `SlidePaths`（`StringList`），存扫描目录的绝对 `file://` URL 列表。

`DisplayPage` 存壁纸入口的**绝对 `file://` URL**（如 `file:///usr/share/html-wallpapers/FallingCherry/index.html`）：

- **`main.qml` 无需修改**：`Qt.resolvedUrl()` 对绝对 URL 原样返回、对相对路径基于插件包解析，天然兼容
- **向后兼容**：旧配置若已是 `file://` 绝对 URL 或 `https://`，仍能正常加载
- 拖放自定义 HTML 入口（`main.qml` 的 `onOpenUrlRequested`）保留不变

## 错误处理

- 某壁纸 `project.json` 缺失或损坏 → 网格中跳过该目录，不崩溃
- 扫描目录不存在 → `FolderListModel` 不触发 Ready，`Timer` 超时后继续下一个，不卡死
- 目录列表为空 → 左侧显示提示文案，网格为空
- 当前选中壁纸的匹配：根据 `cfg_DisplayPage` 判断当前项并高亮

## 验证方式

- CMake 构建 + 安装：`html-wallpapers/` 安装到 `share/html-wallpapers`
- 在 plasmashell 壁纸设置中：
  - 左侧目录列表默认显示两个目录，可 Add / Remove
  - 右侧网格正常显示预装壁纸缩略图与标题
  - 点击缩略图后壁纸切换成功
  - 选中项有高亮反馈
  - 旧配置（绝对 URL / https）仍能加载
  - 拖放 HTML 文件仍能设置壁纸

## 非目标（明确不做）

- 不支持从配置界面添加自定义 URL（改为拖放入口）
- 不引入 C++ 后端
- 不实现壁纸的搜索/排序/分组
- 不实现在线下载新壁纸（NewStuff）
