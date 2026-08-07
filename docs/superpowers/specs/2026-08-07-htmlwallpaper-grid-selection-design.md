# HTMLWallpaper 壁纸 UI 网格选择 设计文档

- 日期：2026-08-07
- 状态：已批准（待实现）
- 插件 ID：`com.github.Moon-Haze.htmlwallpaper`

## 背景与目标

当前 HTML 壁纸插件的配置界面（`package/contents/ui/config.qml`）是一个 `Kirigami.FormLayout`，用户需**手动输入 URL** 来选择要展示的 HTML 页面。项目自带 5 个预装 HTML 壁纸（位于 `wallpapers/` 目录），但没有可视化选择入口。

**目标**：参考 `ref/org.kde.slideshow/contents/ui/config.qml`，把「手动输入 URL」改为**缩略图网格 UI 选择**，让用户从预装壁纸中点击选择。

**明确排除的能力**：配置界面不再提供 URL 输入框。自定义网页能力通过「拖动 HTML 文件到桌面」保留（`main.qml` 的 `onOpenUrlRequested` 已实现）。

## 决策记录

| 决策点 | 选择 | 理由 |
|---|---|---|
| 选择方式 | 纯网格选择（移除 URL 输入框） | 用户明确要求 |
| 壁纸数据源 | 扫描包内目录 | 预装壁纸随 KPackage 打包，加新壁纸无需改代码 |
| 界面布局 | 设置在上、网格在下 | 与官方 image/slideshow 配置风格一致 |
| 扫描实现 | `Qt.labs.folderlistmodel.FolderListModel` + XHR 读 JSON | 纯 QML，无需 C++ 编译 |
| UI 组件 | 方案 B：`KCM.GridView` / `KCM.GridDelegate` | 官方组件，观感贴近官方插件 |

## 目录结构变化

```
wallpapers/                          # 从项目根目录移入包内
  AudioVisualizer/
  CanvasBg/
  CodeTime/
  FallingCherry/                     # 缺少 project.json，需补充
  FetchTerminal/
```
→ 移动到 `package/contents/wallpapers/`，随 KPackage 一起安装。

CMake 无需改动：`plasma_install_package(package ... wallpapers wallpaper)` 已打包整个 `package/` 目录，`contents/wallpapers/` 会自然包含在内。

## 架构

```
package/contents/ui/config.qml  （重写）
│
ColumnLayout
├── Kirigami.FormLayout          # 设置在上
│   ├── ZoomFactor 滑块
│   └── InsecureHTTPS 复选框
└── 缩略图网格区域                # 网格在下
    └── KCM.GridView
        └── KCM.GridDelegate（自定义）
            ├── thumbnail: 预览图 + 标题
            └── onClicked: 选中壁纸

package/contents/ui/main.qml    （小幅修改：URL 兼容解析）
package/contents/wallpapers/    （预装壁纸，随包安装）
```

## 数据流

1. `FolderListModel` 枚举 `../wallpapers/`（相对 config.qml 的包内路径）下的子目录
2. 对每个目录用 `XMLHttpRequest` 读 `project.json` → 得到 `title` / `preview` / `file` 字段
3. 组装一个 `ListModel`（roles：`title`、`previewUrl`、`pageUrl`）喂给 `KCM.GridView`
4. 点击 delegate → 设置 `cfg_DisplayPage` 为壁纸入口的**包内相对路径**，并高亮当前项

## 配置存储与兼容性

`DisplayPage` 配置项存储**包内相对路径**（如 `wallpapers/AudioVisualizer/index.html`），而不是绝对 `file://` URL：

- **`main.qml` 需小幅修改**：对 `DisplayPage` 做 URL 兼容解析
  - 绝对 URL（`http(s)://`、`file://`）→ 直接使用
  - 相对路径 → 用 `Qt.resolvedUrl()` 基于插件包路径解析
- **向后兼容**：旧配置若已是 `file://` 绝对 URL 或 `https://`，仍能正常加载
- 拖放自定义 HTML 入口（`main.qml` 的 `onOpenUrlRequested`）保留不变

## 错误处理

- 某壁纸 `project.json` 缺失或损坏 → 网格中跳过该目录，不崩溃
- 目录扫描为空 → 显示提示文案
- 当前选中壁纸的匹配：根据 `cfg_DisplayPage` 判断当前项并高亮

## 验证方式

- CMake 构建 + 安装（`plasma_install_package` 自动打包 `contents/wallpapers/`）
- 在 plasmashell 壁纸设置中：
  - 验证网格正常显示预装壁纸缩略图与标题
  - 点击缩略图后壁纸切换成功
  - 选中项有高亮反馈
  - 旧配置（绝对 URL / https）仍能加载
  - 拖放 HTML 文件仍能设置壁纸

## 非目标（明确不做）

- 不支持从配置界面添加自定义 URL（改为拖放入口）
- 不引入 C++ 后端
- 不实现壁纸的搜索/排序/分组
- 不实现在线下载新壁纸（NewStuff）
