# HTMLWallpaper:去掉 project.json 解析 + MVC 重构设计

日期:2026-08-15
状态:待评审

## 背景与目标

当前 `plugin/` 模块扫描壁纸依赖每个子目录下的 `project.json`(Wallpaper Engine 风格元数据):

- 扫描 worker 构造 `WallpaperProject` 读 `project.json`,文件缺失/非法即跳过该目录
- `type` 字段驱动 HTML/非 HTML 过滤(`requireWebType` / `nonHtmlTypes`)
- `general.properties` 驱动可配置属性系统(`WallpaperProperty` / `WallpaperPropertyModel` / `WallpaperPropertyItem` + PropertyPanel 面板)
- 大量扩展元数据字段(description / tags / workshopid / 评级 / supportsAudio 等)来自 JSON 顶层

目标:

1. **不再解析 `project.json`** —— 壁纸识别改为直接扫描子目录内的 `*.html` 文件
2. **彻底删除可配置属性系统** —— 属性类文件、PropertyPanel、`WallpaperProperties` 运行时注入、相关测试一并移除
3. **MVC 架构** —— Model 自治扫描、Controller 变薄、View 纯展示
4. **类名与 QML 类型名按 MVC 重命名**

## 决策记录

| 决策点 | 结论 |
|---|---|
| 可配置属性系统去留 | 彻底删除 |
| 扫描范围 | 仅一层子目录(扫描根下直接子目录含 `*.html` 即收录) |
| 入口文件选择 | `index.html` → `index.htm` → `main.html` → `main.htm` → `start.html` → 字典序第一个 `*.html` |
| type 过滤 | 删除 `requireWebType` / `nonHtmlTypes` |
| 扩展元数据字段 | 全部删除 |
| `main.qml` 运行时参数注入 | 一并删除(`_pageUrl` / `_injectProperties` / `WallpaperProperties` 配置项) |
| MVC 程度 | Model 自治(扫描下沉到 Model) |
| QML 类型名 | `HTMLBackend` 一并改为 `WallpaperController` |

## 最终类名映射

| 当前 | 新名 | 新文件 | 层 |
|---|---|---|---|
| `HTMLBackend` | `WallpaperController` | `wallpapercontroller.h/cpp` | Controller |
| `WallpaperListModel` | `WallpaperModel` | `wallpapermodel.h/cpp` | Model |
| `WallpaperProject` | `WallpaperEntry` | `wallpaperentry.h/cpp` | Model(值数据) |
| `WallpaperProjectJson` 命名空间 | `WallpaperPath` | — | 工具 |
| `WallpaperItem` | 保留 | 保留 | Model(单行门面) |
| `WallpaperProperty*`(3 类) | 删除 | 删除 | — |

## MVC 职责划分

| 层 | 组件 | 职责 |
|---|---|---|
| **Model** | `WallpaperModel` + `WallpaperItem` + `WallpaperEntry` | 数据存储、role 提供、**自治扫描**(内部 QtConcurrent worker 枚举目录 → 构造 WallpaperEntry → 填充自身)、目录探测 |
| **Controller** | `WallpaperController` | `scanPaths` 管理、`selectWallpaper` 状态、触发扫描(转发给 Model)、**转发 Model 信号**给 QML |
| **View** | config.qml / ThumbnailsPanel / WallpaperDelegate / ScanPathsPanel | 只读 Controller 暴露的 model 与 scanPaths、把用户操作转发给 Controller |

## 组件详细设计

### 1. `WallpaperEntry`(原 `WallpaperProject`,重写核心)

值类型、可拷贝/移动、后台线程安全构造,架构不变;构造函数从"读 JSON"改为"目录探测":

```
WallpaperEntry(dirUrl)
 ├─ 目录不存在 → 无效对象
 ├─ 枚举目录内 *.html / *.htm
 ├─ 入口选择:index.html → index.htm → main.html → main.htm → start.html → 字典序第一个 *.html
 ├─ 无 html → 无效对象(不收录)
 └─ preview 探测:preview.png / preview.jpg / preview.jpeg / preview.gif / preview.webp
                / default.png / thumbnail.png(可空)
```

- 字段:`name`(目录名) / `title`(= name) / `path`(目录 url) / `file`(入口 url) / `preview` / `m_valid`
- 别名:`source()` = file、`display()` = title(QML 兼容)
- 删除:全部 JSON 解析函数(`loadProjectJson` / `toTagsString` / `workshopIdString` / `resolveEntry` / `findEntry` 重写 / `parseProperties`)、扩展字段成员、`properties()`
- 命名空间 `WallpaperPath`(原 `WallpaperProjectJson`):保留 `toUrl` / `pathJoin`,删除 `isHtmlType`;注释更新为"通用路径工具"

### 2. `WallpaperItem`(保留,精简)

- Q_PROPERTY 从 20 个精简到 7 个:`name / title / path / file / source / display / preview`
- 删除 `description / tags / type / visibility / workshopid / monetization / contentrating / ratingsex / ratingviolence / version / workshopurl / supportsAudio / supportsaudioprocessing` 及 `properties`(WallpaperPropertyModel)成员
- 保留拷贝构造/赋值(`QList<WallpaperItem>` 值存储需要)
- 无 QML_ELEMENT,改名不影响 QML 侧

### 3. `WallpaperModel`(原 `WallpaperListModel`,自治扫描)

- Roles 从 17 个精简到 5 个:`Name / Title / Path / Preview / File`;`data()` / `roleNames()` / `setEntries()` 的 dataChanged 列表相应精简
- `indexOf(source)` / `byKey(source)` 保留(source 作 key)
- **新增自治扫描**:
  - `Q_INVOKABLE void scan(const QStringList &roots)` —— 内部 QtConcurrent worker 枚举 + 构造 WallpaperEntry + 填充自身
  - `Q_PROPERTY(bool scanInProgress ...)` + `m_scanning` 状态
  - 信号 `scanFinished()` / `scanFailed(path, error)` / `scanInProgressChanged()`
  - 内部持有 `QFutureWatcher<ScanResult>`,worker 函数 `scanWallpapers(roots)` 从 `wallpapercontroller.cpp` 移入本文件
- `ScanResult` 结构保留在 `wallpaperentry.h`(projects + failures)

### 4. `WallpaperController`(原 `HTMLBackend`,变薄)

- **删除**:`requireWebType` / `nonHtmlTypes` 属性(getter/setter/信号/成员/默认值)、内部 `QFutureWatcher`、worker、`m_scanning`、`setScanInProgress`
- **保留**:`scanPaths` 管理(`setScanPaths` / `addScanPath` / `removeScanPath` + 信号)、`selectWallpaper`、`wallpapers` 属性(Model 暴露)
- `scan()` 简化为一行转发:`m_wallpapers->scan(m_scanPaths)`
- 内部 connect Model 的 `scanFinished` / `scanFailed` / `scanInProgressChanged` → **重发为自身同名信号**,保持 QML 接口不变
- `QML_ELEMENT` + `QML_NAMED_ELEMENT(WallpaperController)`(QML 类型名一并改为 WallpaperController)
- 头部注释更新:目录约定改为"`<根>/<壁纸名>/` 内含 `.html` 即收录",不再提 project.json

## QML 层改动

| 文件 | 改动 |
|---|---|
| `view/PropertyPanel.qml` | **删除**(git 已标记 D,补上) |
| `config.qml` | `HTMLBackend` 类型声明改 `WallpaperController`;注释更新(去掉 project.json 描述) |
| `main.qml` | **删参数注入**:删 `_propertiesJson` / `_injectedJson` / `_pageUrl` / `_injectProperties`;`_applyUrl` 简化为直接 `webView.url = _displayPage`;`onValueChanged` 只处理 `SelectWallpaper`;保留拖放 / 证书 / 错误层 / WebEngineView |
| `view/ScanPathsPanel.qml` | 仅更新第 31-32 行注释(去掉 properties 描述) |
| `view/ThumbnailsPanel.qml` | **不改**(用 title / preview / path / file,全部保留) |
| `view/WallpaperDelegate.qml` | **不改** |

## 配置定义 + dev 程序

- `package/contents/config/main.xml`:删除 `WallpaperProperties` 配置项
- `dev/src/DevConfigMap.cpp`:删除 `setProperty("WallpaperProperties", ...)` 行
- `dev/qml/DevShell.qml`:删除 `cfg_WallpaperProperties: "{}"` 注入,更新"调整参数"注释
- `dev/src/main.cpp`:更新第 34-36 行注释(不再提读 project.json)

## 构建改动

- `plugin/CMakeLists.txt`:target_sources 用新文件名(`wallpapercontroller.cpp` / `wallpapermodel.cpp` / `wallpaperentry.cpp` / `wallpaperitem.cpp`),删除 3 个属性类文件
- `test/CMakeLists.txt`:`tst_wallpaperproject` 的 target_sources 改为只编 `wallpaperentry.cpp`;include 目录不变

## 测试改动

| 文件 | 改动 |
|---|---|
| `tst_PropertyPanel.qml` | **删除** |
| `tst_wallpaperproject.cpp` | **重写**为目录探测单测:入口选择(index.html 优先 / main.html / 唯一 html / 无 html 无效)、preview 探测、toUrl/pathJoin 工具;类名用 `WallpaperEntry` |
| `tst_Parser.qml` | `HTMLBackend` → `WallpaperController`;更新期望:收录 aurora / matrix / missing-entry / neon / nova / offline 共 6 个;fetch、paramfallback(无 html)不收录;断言改为 title==name、file 入口探测、preview 探测、neon/offline 收录 |
| `tst_WallpaperListModel.qml` | 同上(`HTMLBackend` → `WallpaperController`,期望与断言更新) |
| `tst_Smoke.qml` | 删 `test_propertyPanel_compiles`;`HTMLBackend` → `WallpaperController` |
| `tst_MainCompile.qml` | 删 `test_pageUrl_mixed`(测 _pageUrl,已删);保留 `test_main_compiles` |
| `tst_ThumbnailsHighlight.qml` | **不改**(mock 只测 ThumbnailsPanel 高亮,用的 source/path/display 保留) |

## 测试夹具

`test/data/wallpapers/` 不改:

- fetch、paramfallback 目录无 `*.html` → 作为"不收录"反例
- aurora(index.html) / matrix(main.html) / missing-entry(唯一 real.html) / neon(index.html,无 json) / nova(index.html + preview.jpg) / offline(game.html) 覆盖入口选择、preview 探测、无 json 收录等场景

## 预期净效果

- 删除 3 个 C++ 属性类文件 + 1 个 QML 组件 + 1 个 C++ 测试 + 1 个 QML 测试
- `WallpaperEntry` 约 10KB → ~3KB;`WallpaperItem` / `WallpaperModel` 字段减半
- 扫描、路径管理、网格展示、运行时渲染行为全部保留
- MVC 分层:Controller 薄(配置输入 + 事件转发),Model 自治(数据 + 扫描执行),View 纯展示
