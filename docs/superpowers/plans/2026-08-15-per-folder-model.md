# 每文件夹一个 WallpaperModel 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **设计转向注记（2026-08-16）**：本计划的"全部"视图原设想由懒建的合并 model `AllWallpapersModel` 提供（`setSources` 重挂源，见 Task 2）；该方案在后续 merge 阶段**放弃**（提交 `ec26817 refactor: 移除聚合模式语义`）。"全部"最终由独立 `WallpaperModel("ALL")` 承担（controller 构造即建、scan 时 `clear()` + 逐文件夹 `addEntries` 重建）。**Task 2（AllWallpapersModel 合并 model）未执行**；Task 1/3/4/5 实际落地，但接口形态有差异（见各 Task 注记）。最终设计见 [merge spec](../specs/2026-08-16-merge-allwallpapers-into-wallpapersmodel-design.md)。

**Goal（最终采纳）：** 把 WallpaperModel 从"单 model 内部分组存储多文件夹"改为"每文件夹一个独立 WallpaperModel 实例"，Controller 持多 model 容器并提供 `modelFor`/`allModel` 接口；"全部"视图由独立 `WallpaperModel("ALL")`（构造即建、scan 重建）承担，controller 新增 `activeModel`/`activeIndex` 属性供 QML 绑定。

**Architecture（最终采纳）：** WallpaperModel 收敛为纯单文件夹数据容器（构造带 key、`setEntries` 整组替换 + `addEntries` 追加 + `clear` + `get` 模板 + `selectedIndex`）；扫描编排（`scanWallpapers` + QFutureWatcher）上移 WallpaperController；Controller 缓存每文件夹 model（`QList<WallpaperModel*>`），`m_allModel` 为构造即建的独立 `WallpaperModel("ALL")`（保活复用，scan 时 `clear()` + `addEntries` 重建，无 `setSources`）；`activeModel` 初始指向 allModel、`activeIndex` 派生自其 `selectedIndex`；QML 中栏 `view.model`/`view.currentIndex` 直接绑 `activeModel`/`activeIndex`，移除 `modelData` 双路径兼容。

**Tech Stack:** Qt6/QML/KF6（Kirigami/KCM.GridView）、QAbstractListModel、QFutureWatcher + QtConcurrent、qmltestrunner（Qt6 版 `/usr/lib/qt6/bin/qmltestrunner`）。

## Global Constraints

- **命名保持 `scanPaths`**：生产已统一为 `scanPaths`/`addScanPath`/`removeScanPath`，本计划不引入 `scanUrls`；仅把测试层残留的 `scanUrls` 引用统一为 `scanPaths`（tst_Parser.qml、FolderTabsHost.qml、tst_FolderTabs.qml、wallpaperentry.h 注释）。
- **WallpaperModel 单文件夹语义（落地修订）**：构造 `WallpaperModel(const QString &key, QObject *parent = nullptr)`；`setEntries(const QList<WallpaperEntry> &)` 整组替换、`addEntries` 追加、`clear` 清空；删除 `byKey/keys/groupCount/folderName/parentPath/scan/scanInProgress` 及其存储（m_items QHash/m_groupOrder/m_flat/m_scanning/m_watcher）；roles 四字段（name/path/preview/file），无 `indexOf`；新增 `selectedIndex`/`setSelectedIndex`/`setSelectedIndexOfFile` 与 `get` 模板。
- **Controller 接口（落地修订）**：`Q_INVOKABLE WallpaperModel *modelFor(const QString &url)`（key 归一化去重建）、`Q_INVOKABLE WallpaperModel *allModel()`（构造即建、保活复用）、`Q_INVOKABLE QString folderName/parentPath(const QString&)`、`Q_PROPERTY bool scanInProgress`、`Q_PROPERTY WallpaperModel *activeModel`、`Q_PROPERTY int activeIndex`；私有 `obtainModel`/`releaseStaleModels`。
- **"全部"汇总（落地形态）**：由独立 `WallpaperModel("ALL")` 承担（非 AllWallpapersModel），scan 时 `clear()` + 逐文件夹 `addEntries` 重建；不引入 `setSources`/`m_isAggregate`。
- **合并 model 保活复用（落地形态）**：`m_allModel` 构造即建、不销毁重建（QML 正持引用时销毁会悬空）；`activeModel` 初始指向 allModel，`releaseStaleModels` 释放 activeModel 时置空并 emit。
- **QML 单路径**：`view.model` 恒为真 QAbstractListModel，delegate/onClicked 只用 `model.xxx`，删除 `?? modelData.xxx`。
- **中文注释、中文 commit message**；每步 TDD：先写/改测试 → 验证失败 → 实现 → 验证通过 → commit。
- 构建命令：`cmake --build /home/swix/Code/QtProjects/HTMLWallpaper/build`
- C++ 单测运行：`/home/swix/Code/QtProjects/HTMLWallpaper/build/bin/<target>`
- QML 测试运行（offscreen）：`cd /home/swix/Code/QtProjects/HTMLWallpaper/test && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import /home/swix/Code/QtProjects/HTMLWallpaper/build/bin -input <tst_xxx.qml>`
- 全量回归：`cd /home/swix/Code/QtProjects/HTMLWallpaper/build && ctest`

---

### Task 1: WallpaperModel 单文件夹化 + controller 编译适配（落地，接口有差异）

> **落地差异注记**：本任务执行完毕，但接口形态与最终实现有差异——
> - "整组替换"最终命名为 `setEntries`（本任务写作 `addEntries` 单参整组替换），并另加 `addEntries`（追加末尾）与 `clear`（清空）。
> - `indexOf` 未落地（删除）；roles 为四字段（name/path/preview/file），无第五字段。
> - 新增 `get` 模板（`get<R>(i)` / `get<R>()`）与 `selectedIndex`/`setSelectedIndex`/`setSelectedIndexOfFile`。
> 详见 [wallpapermodel.h](../../plugin/wallpapermodel.h) 与 merge spec"类设计"。

**Files:**
- Modify: `plugin/wallpapermodel.h`
- Modify: `plugin/wallpapermodel.cpp`
- Modify: `plugin/wallpapercontroller.h`
- Modify: `plugin/wallpapercontroller.cpp`
- Modify: `test/tst_wallpapermodel.cpp`

**Interfaces:**
- Produces: `WallpaperModel(const QString &key, QObject*)`、`key()`、`count()`、`addEntries(const QList<WallpaperEntry>&)`、`clear()`、`get(int)`、`indexOf(const QString&)`、roles 五字段。Task 2 的 AllWallpapersModel 与 Task 3 的 controller 依赖这些。
- Consumes: `WallpaperEntry`（值类型）、`WallpaperItem`（QObject 门面，不动）。

> 中间态说明：本任务完成后 plugin 编译通过、`tst_wallpapermodel` PASS；但 `tst_Parser`/`tst_WallpaperListModel`/`tst_FolderTabs`/`tst_Smoke` 处于失败中间态（controller 暂时无 scan/wallpapers，QML 层仍引用旧 API），由后续任务修复。controller 本任务只做"最小可编译"适配：删 `wallpapers` 属性与 `scan()`。

- [ ] **Step 1: 重写 `plugin/wallpapermodel.h` 为单文件夹语义**

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <qobject.h>
#include <qtmetamacros.h>

#include "wallpaperentry.h"
#include "wallpaperitem.h"

/**
 * @brief 单个文件夹的壁纸列表模型（WallpaperModel::modelFor 的返回）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) 与 data()。roles 对齐 WallpaperDelegate / ThumbnailsView
 * 使用的字段：name / title / path / preview / file（file 是目录探测选出的
 * *.html 入口）。
 *
 * 单文件夹语义：一个实例只装一个扫描根（key，归一化 URL）的壁纸。
 * addEntries(entries) 整组替换本文件夹条目（同文件夹重扫即覆盖）。
 * 无扫描逻辑、无后台线程——扫描编排由 WallpaperController 承担。
 */
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(QString key READ key CONSTANT) // 本文件夹归一化 URL

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        TitleRole,
        PathRole,
        PreviewRole,
        FileRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperModel(const QString &key, QObject *parent = nullptr);

    QString key() const;
    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 替换本文件夹全部条目；同文件夹重扫即整组覆盖。主线程调用；reset 一次。 */
    Q_INVOKABLE void addEntries(const QList<WallpaperEntry> &wallpapers);

    void clear();

    /** 兼容原 ListModel：返回第 i 项属性门面对象；越界返回 nullptr。 */
    Q_INVOKABLE WallpaperItem *get(int i);

    /** 按条目 source（html 文件 URL）返回行号；未找到返回 -1。 */
    Q_INVOKABLE int indexOf(const QString &source) const;

private:
    QString m_key;                  // 本文件夹归一化 URL
    QList<WallpaperItem *> m_items; // 本文件夹的壁纸项（QObject parent = 本 model）
};
```

- [ ] **Step 2: 重写 `plugin/wallpapermodel.cpp`（删 scanWallpapers 匿名命名空间）**

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapermodel.h"

#include "wallpaperitem.h"

WallpaperModel::WallpaperModel(const QString &key, QObject *parent)
    : QAbstractListModel(parent)
    , m_key(key)
{
}

QString WallpaperModel::key() const
{
    return m_key;
}

int WallpaperModel::count() const
{
    return m_items.size();
}

int WallpaperModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_items.size();
}

QVariant WallpaperModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }
    auto item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item->name();
    case TitleRole:
        return item->title();
    case PathRole:
        return item->path();
    case PreviewRole:
        return item->preview();
    case FileRole:
        return item->file();
    default:
        return {};
    }
}

QHash<int, QByteArray> WallpaperModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {TitleRole, "title"},
        {PathRole, "path"},
        {PreviewRole, "preview"},
        {FileRole, "file"},
    };
}

void WallpaperModel::addEntries(const QList<WallpaperEntry> &wallpapers)
{
    beginResetModel();
    for (WallpaperItem *p : m_items) {
        delete p; // 释放旧条目（QObject parent = 本 model）
    }
    m_items.clear();
    for (const WallpaperEntry &entry : wallpapers) {
        m_items.append(new WallpaperItem(entry, this));
    }
    endResetModel();
}

void WallpaperModel::clear()
{
    beginResetModel();
    for (WallpaperItem *p : m_items) {
        delete p;
    }
    m_items.clear();
    endResetModel();
}

int WallpaperModel::indexOf(const QString &source) const
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i)->source() == source) {
            return i;
        }
    }
    return -1;
}

WallpaperItem *WallpaperModel::get(int i)
{
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return m_items.at(i);
}
```

- [ ] **Step 3: controller 最小编译适配——`plugin/wallpapercontroller.h` 删 `wallpapers` 属性与 `scan()`**

把 `Q_PROPERTY(WallpaperModel *wallpapers READ wallpapers CONSTANT)` 行删除，`WallpaperModel *wallpapers() const;` 声明删除，`Q_INVOKABLE void scan();` 声明删除，`WallpaperModel *m_wallpapers = nullptr;` 成员删除。其余（selectWallpaper/scanPaths/addScanPath/removeScanPath 及信号）保留。中间态头文件形如：

```cpp
class WallpaperController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(WallpaperController)

    Q_PROPERTY(QString selectWallpaper READ selectWallpaper WRITE setSelectWallpaper NOTIFY selectWallpaperChanged)
    Q_PROPERTY(QStringList scanPaths READ scanPaths WRITE setScanPaths NOTIFY scanPathsChanged)

public:
    explicit WallpaperController(QObject *parent = nullptr);
    QString selectWallpaper() const;
    void setSelectWallpaper(const QString &wallpaper);
    QStringList scanPaths() const;
    void setScanPaths(const QStringList &urls);

    Q_INVOKABLE bool addScanPath(const QString &url);
    Q_INVOKABLE void removeScanPath(const QString &url);

Q_SIGNALS:
    void selectWallpaperChanged();
    void scanPathsChanged();
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    QString m_selectWallpaper;
    QStringList m_scanPaths;
};
```

- [ ] **Step 4: controller 最小编译适配——`plugin/wallpapercontroller.cpp`**

构造删掉 `, m_wallpapers(new WallpaperModel(this))` 与三个 connect；删 `wallpapers()` 实现与 `scan()` 实现。`#include "wallpapermodel.h"` 保留（Task 3 还会用）。中间态：

```cpp
WallpaperController::WallpaperController(QObject *parent)
    : QObject(parent)
{
}
// ... selectWallpaper / scanPaths / addScanPath / removeScanPath 实现保持不变 ...
```

- [ ] **Step 5: 构建验证编译通过**

```bash
cmake --build /home/swix/Code/QtProjects/HTMLWallpaper/build
```

Expected: plugin 与 tst_wallpapermodel 编译通过。

- [ ] **Step 6: 重写 `test/tst_wallpapermodel.cpp` 为单文件夹语义**

整文件替换为：

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QPointer>
#include <QtTest>

#include "wallpapermodel.h"
#include "wallpaperitem.h"

/**
 * WallpaperModel 单文件夹语义的 C++ 单测。
 *
 * 直接构造无效 WallpaperEntry()（目录探测的空条目）验证单文件夹的
 * 整组替换/覆盖/清空/roles 等纯结构逻辑，不依赖文件系统。覆盖测试用
 * QPointer 断言旧指针已 delete。
 */
class tst_wallpapermodel : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void keyRoundTrip();
    void addEntriesReplacesAll();
    void addEntriesOverwritesAll();
    void clearEmptiesAll();
    void dataRolesAndGet();
    void indexOfNotFound();
};

void tst_wallpapermodel::keyRoundTrip()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QCOMPARE(model.key(), QStringLiteral("file:///root/a"));
}

void tst_wallpapermodel::addEntriesReplacesAll()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QList<WallpaperEntry> entries;
    entries.append(WallpaperEntry());
    entries.append(WallpaperEntry());
    model.addEntries(entries);
    QCOMPARE(model.count(), 2);
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.rowCount(model.index(0, 0)), 0); // 无子项
}

void tst_wallpapermodel::addEntriesOverwritesAll()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QList<WallpaperEntry> first;
    first.append(WallpaperEntry());
    first.append(WallpaperEntry());
    model.addEntries(first);
    QCOMPARE(model.count(), 2);

    // 记录旧条目指针，整组覆盖后应被 delete
    QPointer<WallpaperItem> survivor(model.get(0));

    QList<WallpaperEntry> second;
    second.append(WallpaperEntry());
    model.addEntries(second); // 整组替换

    QCOMPARE(model.count(), 1);
    QVERIFY(survivor.isNull());
}

void tst_wallpapermodel::clearEmptiesAll()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QList<WallpaperEntry> entries;
    entries.append(WallpaperEntry());
    model.addEntries(entries);
    QCOMPARE(model.count(), 1);

    model.clear();
    QCOMPARE(model.count(), 0);
    QCOMPARE(model.rowCount(), 0);
}

void tst_wallpapermodel::dataRolesAndGet()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QList<WallpaperEntry> entries;
    entries.append(WallpaperEntry());
    model.addEntries(entries);

    QVERIFY(model.get(0) != nullptr);
    // 无效 WallpaperEntry 的各 role data 为空字符串
    QCOMPARE(model.data(model.index(0, 0), WallpaperModel::NameRole).toString(), QString());
    QCOMPARE(model.data(model.index(0, 0), WallpaperModel::TitleRole).toString(), QString());
    QCOMPARE(model.data(model.index(0, 0), WallpaperModel::PathRole).toString(), QString());
    QCOMPARE(model.data(model.index(0, 0), WallpaperModel::PreviewRole).toString(), QString());
    QCOMPARE(model.data(model.index(0, 0), WallpaperModel::FileRole).toString(), QString());
    // 越界安全
    QCOMPARE(model.get(-1), nullptr);
    QCOMPARE(model.get(5), nullptr);
    QCOMPARE(model.data(model.index(5, 0), WallpaperModel::NameRole).toString(), QString());
}

void tst_wallpapermodel::indexOfNotFound()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QList<WallpaperEntry> entries;
    entries.append(WallpaperEntry());
    model.addEntries(entries);
    // 无效 WallpaperEntry source 为空，indexOf 查不到该 source
    QCOMPARE(model.indexOf(QStringLiteral("file:///nonexistent.html")), -1);
}

QTEST_MAIN(tst_wallpapermodel)
#include "tst_wallpapermodel.moc"
```

- [ ] **Step 7: 运行 tst_wallpapermodel 验证通过**

```bash
cmake --build /home/swix/Code/QtProjects/HTMLWallpaper/build && /home/swix/Code/QtProjects/HTMLWallpaper/build/bin/tst_wallpapermodel
```

Expected: 6 个用例全 PASS。

- [ ] **Step 8: Commit**

```bash
git add plugin/wallpapermodel.h plugin/wallpapermodel.cpp plugin/wallpapercontroller.h plugin/wallpapercontroller.cpp test/tst_wallpapermodel.cpp
git commit -m "refactor: WallpaperModel 单文件夹化(构造带 key/整组替换)，controller 暂删 wallpapers 属性"
```

---

### Task 2: AllWallpapersModel 合并 model（未执行）

> **未执行（设计转向放弃聚合模式）**：本任务描述的 `AllWallpapersModel` 类与 `setSources`
> 聚合合并在 merge 阶段**放弃**（提交 `ec26817`），文件从未创建/已删除。"全部"视图最终由
> 独立 `WallpaperModel("ALL")` 承担（见 Task 3 注记与 merge spec）。下文保留原文供追溯，可跳过。

**Files:**
- Create: `plugin/allwallpapersmodel.h`
- Create: `plugin/allwallpapersmodel.cpp`
- Modify: `plugin/CMakeLists.txt`
- Modify: `test/tst_wallpapermodel.cpp`

**Interfaces:**
- Consumes: `WallpaperModel`（Task 1，`rowCount`/`data`/`modelReset`/Roles）。
- Produces: `AllWallpapersModel::setSources(QList<WallpaperModel*>)`。Task 3 的 `WallpaperController::allModel()` 与 QML"全部"视图依赖。

- [ ] **Step 1: 新建 `plugin/allwallpapersmodel.h`**

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>

#include "wallpapermodel.h"

/**
 * @brief 多文件夹合并 model（"全部"视图的数据源，懒建于 controller）。
 *
 * 聚合多个单文件夹 WallpaperModel 为一个扁平 QAbstractListModel：
 * rowCount 各源求和，data 跨源定位行后透传源 data，roleNames 对齐
 * WallpaperModel 五字段。监听各源 modelReset，任一源重置即整体 reset。
 *
 * 生命周期由 WallpaperController 持有（保活复用）；scan 后经 setSources
 * 重挂最新源，不会出现 QML 持引用时被销毁的悬空。
 */
class AllWallpapersModel : public QAbstractListModel
{
    Q_OBJECT
public:
    explicit AllWallpapersModel(QObject *parent = nullptr);

    /** 重建源挂载：断开旧源连接、连接新源、自身整体 reset。 */
    void setSources(const QList<WallpaperModel *> &sources);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    void onSourceReset();
    QList<WallpaperModel *> m_sources;
};
```

- [ ] **Step 2: 新建 `plugin/allwallpapersmodel.cpp`**

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "allwallpapersmodel.h"

#include "wallpapermodel.h"

AllWallpapersModel::AllWallpapersModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

void AllWallpapersModel::setSources(const QList<WallpaperModel *> &sources)
{
    for (WallpaperModel *src : m_sources) {
        disconnect(src, &WallpaperModel::modelReset, this, &AllWallpapersModel::onSourceReset);
    }
    m_sources = sources;
    for (WallpaperModel *src : m_sources) {
        connect(src, &WallpaperModel::modelReset, this, &AllWallpapersModel::onSourceReset);
    }
    beginResetModel();
    endResetModel();
}

int AllWallpapersModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    int total = 0;
    for (const WallpaperModel *src : m_sources) {
        total += src->rowCount();
    }
    return total;
}

QVariant AllWallpapersModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount()) {
        return {};
    }
    int remaining = index.row();
    for (const WallpaperModel *src : m_sources) {
        const int count = src->rowCount();
        if (remaining < count) {
            return src->data(src->index(remaining, 0), role);
        }
        remaining -= count;
    }
    return {};
}

QHash<int, QByteArray> AllWallpapersModel::roleNames() const
{
    // 硬编码对齐 WallpaperModel::roleNames（五字段），QML role 名一致
    return {
        {WallpaperModel::NameRole, "name"},
        {WallpaperModel::TitleRole, "title"},
        {WallpaperModel::PathRole, "path"},
        {WallpaperModel::PreviewRole, "preview"},
        {WallpaperModel::FileRole, "file"},
    };
}

void AllWallpapersModel::onSourceReset()
{
    beginResetModel();
    endResetModel();
}
```

- [ ] **Step 3: `plugin/CMakeLists.txt` 的 `target_sources` 加 `allwallpapersmodel.cpp`**

把 `wallpapercontroller.cpp` 那组列表末尾补一行：

```cmake
target_sources(plasma_wallpaper_htmlwallpaperplugin PRIVATE
    wallpapercontroller.cpp
    wallpaperitem.cpp
    wallpapermodel.cpp
    allwallpapersmodel.cpp
    wallpaperentry.cpp
)
```

- [ ] **Step 4: `test/tst_wallpapermodel.cpp` 增加合并 model 用例**

在 `#include "wallpaperitem.h"` 后加 `#include "allwallpapersmodel.h"`、`#include <QSignalSpy>`；`private Q_SLOTS` 增补两函数并在文件末尾（`QTEST_MAIN` 前）实现：

```cpp
    void mergeAggregatesAcrossSources();
    void mergeResetsOnSourceReset();
```

```cpp
void tst_wallpapermodel::mergeAggregatesAcrossSources()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    QList<WallpaperEntry> ea, eb;
    ea.append(WallpaperEntry());
    ea.append(WallpaperEntry());
    eb.append(WallpaperEntry());
    modelA.addEntries(ea);
    modelB.addEntries(eb);

    AllWallpapersModel merged;
    merged.setSources({&modelA, &modelB});
    QCOMPARE(merged.rowCount(), 3);
    // 跨源定位：行 0/1 在 A，行 2 在 B（返回空字符串而非越界空）
    QCOMPARE(merged.data(merged.index(2, 0), WallpaperModel::NameRole).toString(), QString());
    // roles 对齐
    QCOMPARE(merged.roleNames().value(WallpaperModel::TitleRole), QByteArray("title"));

    // 换源后行数随之变化
    AllWallpapersModel merged2;
    merged2.setSources({&modelB});
    QCOMPARE(merged2.rowCount(), 1);
}

void tst_wallpapermodel::mergeResetsOnSourceReset()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    AllWallpapersModel merged;
    merged.setSources({&modelA});

    QSignalSpy resetSpy(&merged, &QAbstractItemModel::modelReset);
    modelA.addEntries({WallpaperEntry()}); // 源重置 → 合并 model 也应 reset
    QCOMPARE(resetSpy.count(), 1);
}
```

- [ ] **Step 5: `test/CMakeLists.txt` 的 tst_wallpapermodel 目标加编译源 `allwallpapersmodel.cpp`**

```cmake
    target_sources(tst_wallpapermodel PRIVATE
        ../plugin/wallpapermodel.cpp
        ../plugin/allwallpapersmodel.cpp
        ../plugin/wallpaperitem.cpp
        ../plugin/wallpaperentry.cpp
    )
```

- [ ] **Step 6: 构建 + 运行 tst_wallpapermodel**

```bash
cmake --build /home/swix/Code/QtProjects/HTMLWallpaper/build && /home/swix/Code/QtProjects/HTMLWallpaper/build/bin/tst_wallpapermodel
```

Expected: 8 个用例全 PASS。

- [ ] **Step 7: Commit**

```bash
git add plugin/allwallpapersmodel.h plugin/allwallpapersmodel.cpp plugin/CMakeLists.txt test/tst_wallpapermodel.cpp test/CMakeLists.txt
git commit -m "feat: AllWallpapersModel 多源合并 model(跨源定位/源 reset 联动)"
```

---

### Task 3: WallpaperController 扫描编排上移 + 多 model 容器 + 命名统一（落地，接口有差异）

> **落地差异注记**：本任务执行完毕，但 controller 接口与 scan 流程与最终实现有差异——
> - `allModel()` 返回 `WallpaperModel *`（非 `QAbstractItemModel *`），且**构造即建**（成员初始化
>   `new WallpaperModel(QStringLiteral("ALL"), this)`），非懒建。
> - 新增 `activeModel`（`WallpaperModel *`）与 `activeIndex`（`int`）Q_PROPERTY；`activeModel`
>   初始指向 allModel。
> - scan 流程不调用 `setSources`；改为 `m_allModel->clear()` + 逐文件夹 `addEntries` 重建，
>   并对非 activeModel 的 model 与 allModel 调 `setSelectedIndexOfFile` 恢复选中（详见
>   [wallpapercontroller.cpp](../../plugin/wallpapercontroller.cpp) 的 `scan()`）。
> - 无 `AllWallpapersModel` 依赖（Step 1/2 中的 `#include "allwallpapersmodel.h"` 与
>   `QAbstractItemModel *m_allModel` 与最终不符）。

**Files:**
- Modify: `plugin/wallpapercontroller.h`
- Modify: `plugin/wallpapercontroller.cpp`
- Modify: `plugin/wallpaperentry.h`
- Create: `test/tst_wallpapercontroller.cpp`
- Modify: `test/CMakeLists.txt`
- Modify: `test/tst_Parser.qml`
- Modify: `test/tst_WallpaperListModel.qml`

**Interfaces:**
- Consumes: `WallpaperModel`（Task 1）、`AllWallpapersModel`（Task 2）、`ScanResult/ScanGroup`（wallpaperentry.h 不动）。
- Produces: `modelFor(url)`/`allModel()`/`folderName(url)`/`parentPath(url)`/`scan()`/`scanInProgress`。Task 4 的 QML 层与 Task 5 的测试 mock 依赖。

- [ ] **Step 1: 重写 `plugin/wallpapercontroller.h`（完整多 model 容器）**

整文件替换为：

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractItemModel>
#include <QFutureWatcher>
#include <QList>
#include <QObject>
#include <QStringList>

#include <QtQml/qqml.h>

#include "wallpaperentry.h"
#include "wallpapermodel.h"

/**
 * @brief HTML 壁纸配置的 C++ 门面（QML 类型 WallpaperController）。
 *
 * 供配置界面（config.qml → ScanPathsPanel → ThumbnailsPanel）消费的
 * Controller：持有 scanPaths / selectWallpaper 属性与扫描编排，并为每个
 * 扫描根缓存一个单文件夹 WallpaperModel（QList<WallpaperModel *> m_models）。
 *
 * - modelFor(url)：url 对应文件夹的常驻 WallpaperModel*（key 归一化去重建）。
 * - allModel()：懒建 AllWallpapersModel 聚合全部文件夹；scan 后对缓存实例
 *   setSources 重挂最新源（保活复用，无悬空指针）。
 * - scan()：后台一次扫所有 scanPaths，逐组 addEntries 到对应文件夹 model。
 */
class WallpaperController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(WallpaperController)

    Q_PROPERTY(QString selectWallpaper READ selectWallpaper WRITE setSelectWallpaper NOTIFY selectWallpaperChanged)
    Q_PROPERTY(QStringList scanPaths READ scanPaths WRITE setScanPaths NOTIFY scanPathsChanged)
    Q_PROPERTY(bool scanInProgress READ scanInProgress NOTIFY scanInProgressChanged)

public:
    explicit WallpaperController(QObject *parent = nullptr);
    QString selectWallpaper() const;
    void setSelectWallpaper(const QString &wallpaper);
    QStringList scanPaths() const;
    void setScanPaths(const QStringList &urls);
    bool scanInProgress() const;
    /** 已缓存的文件夹 model 数（测试/调试用）。QML 读作方法调用 modelCount()。 */
    Q_INVOKABLE int modelCount() const;

    Q_INVOKABLE void scan();
    Q_INVOKABLE bool addScanPath(const QString &url);
    Q_INVOKABLE void removeScanPath(const QString &url);
    /** 返回 url 对应文件夹的常驻 WallpaperModel*；不存在即新建（key 归一化）。 */
    Q_INVOKABLE WallpaperModel *modelFor(const QString &url);
    /** 返回懒建的合并 model（全部文件夹聚合）；scan 后缓存实例重挂最新源。 */
    Q_INVOKABLE QAbstractItemModel *allModel();
    /** 扫描根 URL → 显示用文件夹名（去末尾斜杠后取最后一段）。 */
    Q_INVOKABLE QString folderName(const QString &url) const;
    /** 扫描根 URL → 父目录路径（去末尾斜杠后去掉最后一段；根路径返回空）。 */
    Q_INVOKABLE QString parentPath(const QString &url) const;

Q_SIGNALS:
    void selectWallpaperChanged();
    void scanPathsChanged();
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    WallpaperModel *obtainModel(const QString &url); // modelFor 的实现：创建/复用
    void releaseStaleModels(const QStringList &kept); // 销毁不在 kept 的 model
    void setScanInProgress(bool inProgress);

    QString m_selectWallpaper;
    QStringList m_scanPaths;
    QList<WallpaperModel *> m_models; // 按 key 缓存（key = WallpaperPath::toUrl 归一化）
    QAbstractItemModel *m_allModel = nullptr; // 懒建合并 model（保活复用）
    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
```

- [ ] **Step 2: 重写 `plugin/wallpapercontroller.cpp`（扫描编排上移 + 多 model 容器）**

整文件替换为：

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapercontroller.h"

#include "allwallpapersmodel.h"

#include <QDir>
#include <QFutureWatcher>
#include <QSet>
#include <QUrl>
#include <QtConcurrent>

namespace
{

// 文件夹 key 归一化：去末尾斜杠（Qt.resolvedUrl 对目录可能带尾斜杠，
// 与 scan 生成的 key 差异会影响 modelFor 匹配）。
QString normalizeKey(const QString &url)
{
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s;
}

// 后台扫描 worker：只读 QDir + WallpaperEntry 构造，不触碰 QObject。
// 按扫描根归组，保留 roots 遍历顺序。
ScanResult scanWallpapers(const QStringList &roots)
{
    ScanResult result;
    for (const QString &base : roots) {
        const QString baseUrl = WallpaperPath::toUrl(base);
        QDir dir(QUrl(baseUrl).toLocalFile());
        if (!dir.exists()) {
            result.failures.append({base, QStringLiteral("cannot list directory")});
            continue;
        }
        ScanGroup group;
        group.key = baseUrl;
        const QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &sub : subdirs) {
            const QString dirUrl = WallpaperPath::pathJoin(baseUrl, sub);
            WallpaperEntry entry(dirUrl);
            if (entry.isValid()) {
                group.entries.append(entry);
            }
        }
        // 存在但无壁纸子目录的空根不进分组
        if (!group.entries.isEmpty()) {
            result.groups.append(group);
        }
    }
    return result;
}

} // namespace

WallpaperController::WallpaperController(QObject *parent)
    : QObject(parent)
{
}

QString WallpaperController::selectWallpaper() const
{
    return m_selectWallpaper;
}

void WallpaperController::setSelectWallpaper(const QString &wallpaper)
{
    if (m_selectWallpaper == wallpaper) {
        return;
    }
    m_selectWallpaper = wallpaper;
    Q_EMIT selectWallpaperChanged();
}

QStringList WallpaperController::scanPaths() const
{
    return m_scanPaths;
}

void WallpaperController::setScanPaths(const QStringList &urls)
{
    m_scanPaths = urls;
    Q_EMIT scanPathsChanged();
}

bool WallpaperController::scanInProgress() const
{
    return m_scanning;
}

void WallpaperController::setScanInProgress(bool inProgress)
{
    if (m_scanning == inProgress) {
        return;
    }
    m_scanning = inProgress;
    Q_EMIT scanInProgressChanged();
}

int WallpaperController::modelCount() const
{
    return m_models.size();
}

bool WallpaperController::addScanPath(const QString &url)
{
    if (m_scanPaths.contains(url)) {
        return false;
    }
    m_scanPaths.append(url);
    Q_EMIT scanPathsChanged();
    return true;
}

void WallpaperController::removeScanPath(const QString &url)
{
    if (!m_scanPaths.contains(url)) {
        return;
    }
    m_scanPaths.removeAll(url);
    Q_EMIT scanPathsChanged();
}

void WallpaperController::scan()
{
    if (m_scanning) {
        return;
    }
    setScanInProgress(true);

    if (!m_watcher) {
        m_watcher = new QFutureWatcher<ScanResult>(this);
        QObject::connect(m_watcher, &QFutureWatcher<ScanResult>::finished, this, [this]() {
            const ScanResult result = m_watcher->result();
            for (const auto &failure : result.failures) {
                Q_EMIT scanFailed(failure.first, failure.second);
            }
            for (const auto &group : result.groups) {
                obtainModel(group.key)->addEntries(group.entries);
            }
            // 清理已移除文件夹的 model
            releaseStaleModels(m_scanPaths);
            // 合并 model 保活复用：已建则重挂最新源（QML 引用不悬空），未建不动
            if (m_allModel) {
                static_cast<AllWallpapersModel *>(m_allModel)->setSources(m_models);
            }
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWallpapers, m_scanPaths));
}

WallpaperModel *WallpaperController::obtainModel(const QString &url)
{
    const QString key = normalizeKey(WallpaperPath::toUrl(url));
    for (WallpaperModel *m : m_models) {
        if (m->key() == key) {
            return m;
        }
    }
    auto *model = new WallpaperModel(key, this);
    m_models.append(model);
    return model;
}

WallpaperModel *WallpaperController::modelFor(const QString &url)
{
    return obtainModel(url);
}

QAbstractItemModel *WallpaperController::allModel()
{
    if (!m_allModel) {
        auto *merged = new AllWallpapersModel(this);
        merged->setSources(m_models);
        m_allModel = merged;
    }
    return m_allModel;
}

void WallpaperController::releaseStaleModels(const QStringList &kept)
{
    QSet<QString> keptKeys;
    for (const QString &u : kept) {
        keptKeys.insert(normalizeKey(WallpaperPath::toUrl(u)));
    }
    for (int i = m_models.size() - 1; i >= 0; --i) {
        if (!keptKeys.contains(m_models.at(i)->key())) {
            delete m_models.takeAt(i);
        }
    }
}

QString WallpaperController::folderName(const QString &url) const
{
    // 与 wallpaperentry.cpp 的 basename 一致：去末尾斜杠后取最后一段
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s.mid(s.lastIndexOf(QLatin1Char('/')) + 1);
}

QString WallpaperController::parentPath(const QString &url) const
{
    // 去末尾斜杠后去掉最后一段（保留父目录完整路径）
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s.left(s.lastIndexOf(QLatin1Char('/')));
}
```

- [ ] **Step 3: 命名统一——`plugin/wallpaperentry.h` 注释 `scanUrls` → `scanPaths`**

把第 14 行 `// 通用路径工具（scanUrls 归一化 + 目录拼接），被 Controller 与数据层复用。` 中的 `scanUrls` 改为 `scanPaths`。

- [ ] **Step 4: 构建验证编译通过**

```bash
cmake --build /home/swix/Code/QtProjects/HTMLWallpaper/build
```

Expected: plugin 编译通过（controller 恢复 scan() 等接口）。

- [ ] **Step 5: 新建 `test/tst_wallpapercontroller.cpp`（controller 多 model + 合并用例）**

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QDir>
#include <QtTest>

#include "allwallpapersmodel.h"
#include "wallpapercontroller.h"
#include "wallpapermodel.h"

/**
 * WallpaperController 多 model 容器 / 扫描编排的 C++ 单测。
 *
 * modelFor / allModel / releaseStaleModels 用纯内存数据验证；
 * scan 用 test/data/wallpapers fixtures（工作目录即 test/）。
 */
class tst_wallpapercontroller : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void modelForReusesSameKey();
    void modelForCreatesOnePerFolder();
    void allModelAggregatesAcrossSources();
    void scanPopulatesEachFolderModel();
    void releaseStaleModelsDropsRemovedFolders();
    void folderNameAndParentPath();
};

void tst_wallpapercontroller::modelForReusesSameKey()
{
    WallpaperController c;
    WallpaperModel *a = c.modelFor(QStringLiteral("file:///root/a"));
    QVERIFY(a != nullptr);
    // 同 key 复用同一实例
    QCOMPARE(c.modelFor(QStringLiteral("file:///root/a")), a);
    // 尾斜杠归一化：目录 URL 斜杠差异不影响匹配（Qt.resolvedUrl 可能带尾斜杠）
    QCOMPARE(c.modelFor(QStringLiteral("file:///root/a/")), a);
    QCOMPARE(c.modelCount(), 1);
}

void tst_wallpapercontroller::modelForCreatesOnePerFolder()
{
    WallpaperController c;
    QVERIFY(c.modelFor(QStringLiteral("file:///root/a")) != nullptr);
    QVERIFY(c.modelFor(QStringLiteral("file:///root/b")) != nullptr);
    QCOMPARE(c.modelCount(), 2);
}

void tst_wallpapercontroller::allModelAggregatesAcrossSources()
{
    WallpaperController c;
    WallpaperModel *a = c.modelFor(QStringLiteral("file:///root/a"));
    WallpaperModel *b = c.modelFor(QStringLiteral("file:///root/b"));
    QList<WallpaperEntry> ea, eb;
    ea.append(WallpaperEntry());
    ea.append(WallpaperEntry());
    eb.append(WallpaperEntry());
    a->addEntries(ea);
    b->addEntries(eb);

    QAbstractItemModel *all = c.allModel();
    QVERIFY(all != nullptr);
    QCOMPARE(all->rowCount(), 3);
    // 跨源定位：行 2 落在源 b（返回空字符串而非越界空）
    QCOMPARE(all->data(all->index(2, 0), WallpaperModel::NameRole).toString(), QString());
    // 缓存同一实例
    QCOMPARE(c.allModel(), all);
}

void tst_wallpapercontroller::scanPopulatesEachFolderModel()
{
    WallpaperController c;
    const QString fixture = QDir::current().absoluteFilePath(QStringLiteral("data/wallpapers"));
    c.setScanPaths({fixture});
    c.scan();

    // 扫描完成：modelFor 该 root 返回的 model 应被填充（fixtures 收录 6 个）
    WallpaperModel *m = c.modelFor(fixture);
    QTRY_COMPARE_WITH_TIMEOUT(m->count(), 6, 5000);
}

void tst_wallpapercontroller::releaseStaleModelsDropsRemovedFolders()
{
    WallpaperController c;
    c.modelFor(QStringLiteral("file:///root/a"));
    c.modelFor(QStringLiteral("file:///root/b"));
    QCOMPARE(c.modelCount(), 2);

    // scanPaths 只剩 b；scan 完成后 a 的 model 应被释放
    c.setScanPaths({QStringLiteral("file:///root/b")});
    c.scan();
    QTRY_COMPARE_WITH_TIMEOUT(c.modelCount(), 1, 5000);
    // 保活：仍可 modelFor(b)
    QVERIFY(c.modelFor(QStringLiteral("file:///root/b")) != nullptr);
}

void tst_wallpapercontroller::folderNameAndParentPath()
{
    WallpaperController c;
    QCOMPARE(c.folderName(QStringLiteral("file:///home/user/wallpapers/aurora")), QStringLiteral("aurora"));
    QCOMPARE(c.folderName(QStringLiteral("file:///home/user/wallpapers/aurora/")), QStringLiteral("aurora"));
    QCOMPARE(c.parentPath(QStringLiteral("file:///home/user/wallpapers/aurora")), QStringLiteral("file:///home/user/wallpapers"));
    QCOMPARE(c.parentPath(QStringLiteral("file:///home/user/wallpapers/aurora/")), QStringLiteral("file:///home/user/wallpapers"));
}

QTEST_MAIN(tst_wallpapercontroller)
#include "tst_wallpapercontroller.moc"
```

- [ ] **Step 6: `test/CMakeLists.txt` 注册 tst_wallpapercontroller 目标**

在 tst_wallpapermodel 目标之后追加：

```cmake
    # WallpaperController 多 model 容器 + 扫描编排单测。
    qt_add_executable(tst_wallpapercontroller tst_wallpapercontroller.cpp)
    target_sources(tst_wallpapercontroller PRIVATE
        ../plugin/wallpapercontroller.cpp
        ../plugin/wallpapermodel.cpp
        ../plugin/allwallpapersmodel.cpp
        ../plugin/wallpaperitem.cpp
        ../plugin/wallpaperentry.cpp
    )
    target_include_directories(tst_wallpapercontroller PRIVATE ../plugin)
    target_link_libraries(tst_wallpapercontroller PRIVATE Qt6::Test Qt6::Core Qt6::Concurrent)
    add_test(NAME tst_wallpapercontroller COMMAND tst_wallpapercontroller)
    set_tests_properties(tst_wallpapercontroller PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
```

- [ ] **Step 7: 运行 tst_wallpapermodel + tst_wallpapercontroller**

```bash
cmake --build /home/swix/Code/QtProjects/HTMLWallpaper/build && \
/home/swix/Code/QtProjects/HTMLWallpaper/build/bin/tst_wallpapermodel && \
/home/swix/Code/QtProjects/HTMLWallpaper/build/bin/tst_wallpapercontroller
```

Expected: 两个目标全 PASS（tst_wallpapercontroller 需重建，因 CMake 改了）。

- [ ] **Step 8: 重写 `test/tst_Parser.qml`——命名统一 scanPaths + modelFor 语义**

整文件替换为（改 4 处：`scanUrls` → `scanPaths`、函数名同步、`parser.wallpapers` → `modelFor`）：

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import com.github.moon_haze.htmlwallpaper

/**
 * WallpaperController（C++）单元测试。
 *
 * 覆盖异步扫描流程（QtConcurrent worker 枚举根目录下各子目录的 *.html 入口）
 * 与 scanPaths 路径管理。fixtures 位于 test/data/wallpapers/
 * （aurora / matrix / missing-entry / neon / nova / offline 被收录；
 *   fetch / paramfallback 无 html 被过滤）。
 */
TestCase {
    id: testCase
    name: "ParserTests"

    // 指向 fixtures 根目录（tst_Parser.qml 位于 test/ 下）
    property url fixtureDir: Qt.resolvedUrl("data/wallpapers")
    // 每个测试函数独立创建的控制器实例
    property var parser: null

    SignalSpy {
        id: scanSpy
        signalName: "scanFinished"
    }

    function init() {
        // C++ 后端模块类型，每个测试函数独立重建实例
        parser = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; WallpaperController {}", testCase);
        verify(parser !== null, "WallpaperController 实例化失败");
    }

    function cleanup() {
        scanSpy.target = null;
        if (parser) {
            parser.destroy();
            parser = null;
        }
    }

    // —— 扫描路径（scanPaths）——

    // 直接赋值 scanPaths 生效（数据源就是它本身，无中间模型）
    function test_scanPaths_assign() {
        parser.scanPaths = ["file:///a", "file:///b"];
        compare(parser.scanPaths.length, 2);
        compare(String(parser.scanPaths[0]), "file:///a");
        compare(String(parser.scanPaths[1]), "file:///b");
    }

    function test_scanPaths_addRemove() {
        // scanPaths 默认带一个扫描路径，先清空从无开始
        parser.scanPaths = [];
        compare(parser.scanPaths.length, 0, "初始无扫描路径");

        parser.addScanPath("file:///a");
        parser.addScanPath("file:///b/");
        compare(parser.scanPaths.length, 2);
        compare(String(parser.scanPaths[0]), "file:///a");
        compare(String(parser.scanPaths[1]), "file:///b/");

        // 重复路径去重
        parser.addScanPath("file:///a");
        compare(parser.scanPaths.length, 2, "重复路径应被拒绝");

        // 删除
        parser.removeScanPath("file:///a");
        compare(parser.scanPaths.length, 1);
        compare(String(parser.scanPaths[0]), "file:///b/");
    }


    // —— 异步扫描 ——

    function test_scanCollectsWebWallpapers() {
        scanSpy.target = parser;
        parser.scanPaths = [fixtureDir];
        parser.scan();
        // 注意：SignalSpy.wait() 超时会自动 FAIL 并终止测试，成功时返回 undefined，
        // 不能用 verify(wait(...))；wait 只作事件循环驱动，结果看 count
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");

        // 单文件夹语义：modelFor(扫描根) 返回该文件夹 model
        const model = parser.modelFor(String(fixtureDir));
        verify(model !== null, "modelFor 应返回 model");
        compare(model.count, 6, "期望 6 个壁纸，实际 " + model.count);

        let aurora = null, matrix = null, neon = null, nova = null, offline = null, missing = null;
        let fetch = null, paramfallback = null;
        for (let i = 0; i < model.count; i++) {
            let item = model.get(i);
            if (item.name === "aurora") aurora = item;
            if (item.name === "matrix") matrix = item;
            if (item.name === "neon") neon = item;
            if (item.name === "nova") nova = item;
            if (item.name === "offline") offline = item;
            if (item.name === "missing-entry") missing = item;
            if (item.name === "fetch") fetch = item;
            if (item.name === "paramfallback") paramfallback = item;
        }
        verify(aurora !== null, "缺少 aurora");
        verify(matrix !== null, "缺少 matrix");
        verify(neon !== null, "缺少 neon");
        verify(nova !== null, "缺少 nova");
        verify(offline !== null, "缺少 offline");
        verify(missing !== null, "缺少 missing-entry");
        // 排除项：无 html 的目录不被收录
        verify(fetch === null, "fetch 无 html 不应被收录");
        verify(paramfallback === null, "paramfallback 无 html 不应被收录");

        // aurora：title/display = name（目录名），缺省入口探测到 index.html
        compare(aurora.title, "aurora");
        compare(aurora.display, "aurora");
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);
        // source 是 file 的别名
        compare(aurora.source, aurora.file);

        // matrix 目录下入口为 main.html
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);

        // nova 目录下自动探测到 preview.jpg
        verify(nova.preview.endsWith("/data/wallpapers/nova/preview.jpg"), "nova preview 应自动探测: " + nova.preview);
        compare(nova.title, "nova");

        // missing-entry 目录仅 real.html → 探测到 real.html
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
        compare(missing.title, "missing-entry");
    }
}
```

注意：fixtureDir 是 `url` 类型（`Qt.resolvedUrl`），`String(fixtureDir)` 得 file URL 字符串（目录 URL 可能带尾斜杠）；controller 的 obtainModel 经 normalizeKey 去尾斜杠归一化，与 scan 填充的 key 一致，modelFor 必命中同一实例。

- [ ] **Step 9: 重写 `test/tst_WallpaperListModel.qml` 为多文件夹语义**

整文件替换为（保留 6 个 fixtures 收录断言 + 新增两 root 的聚合/清理断言）：

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import com.github.moon_haze.htmlwallpaper

/**
 * 每文件夹一个 model 的多文件夹语义测试（C++ controller 集成）。
 *
 * 覆盖：scan 后 modelFor(各扫描根) 返回对应文件夹 model（count/收录/入口
 * 探测）；两个扫描根各自独立 model；全部视图 allModel 懒建缓存实例；删一个
 * 扫描根后其 model 被释放。
 * fixtures 位于 test/data/wallpapers/（aurora / matrix / missing-entry / neon /
 * nova / offline 被收录）。
 */
TestCase {
    id: testCase
    name: "WallpaperListModelTests"

    property url fixtureDir: Qt.resolvedUrl("data/wallpapers")
    property url extraDir: Qt.resolvedUrl("data/extra")
    property var htmlWallpaper: null

    SignalSpy {
        id: scanSpy
        signalName: "scanFinished"
    }

    function init() {
        htmlWallpaper = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; WallpaperController {}", testCase);
        verify(htmlWallpaper !== null, "WallpaperController 实例化失败");
        scanSpy.target = htmlWallpaper;
    }

    function cleanup() {
        scanSpy.target = null;
        if (htmlWallpaper) {
            htmlWallpaper.destroy();
            htmlWallpaper = null;
        }
    }

    // 扫描 fixtures 并等待 scanFinished
    function scanAndWait(paths) {
        htmlWallpaper.scanPaths = paths;
        htmlWallpaper.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
    }

    // 单 root：modelFor(扫描根) 收录 6 个，get(i) 返回 WallpaperItem 元数据
    function test_scanCollectsWallpapers() {
        scanAndWait([fixtureDir]);
        const model = htmlWallpaper.modelFor(String(fixtureDir));
        verify(model !== null, "modelFor 应返回 model");
        compare(model.count, 6);
        const first = model.get(0);
        verify(first !== null, "get(0) 不应为 null");
        compare(first.name, "aurora");
    }

    // get(i) 返回 WallpaperItem：name/title/file 等基础元数据（从单 root model 取）
    function test_scanCollectsMetadata() {
        scanAndWait([fixtureDir]);
        const model = htmlWallpaper.modelFor(String(fixtureDir));
        const aurora = model.get(0);
        verify(aurora !== null, "get(0) 不应为 null");
        compare(aurora.name, "aurora");
        compare(aurora.title, "aurora");
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);
        const matrix = model.get(1);
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);
        const missing = model.get(2);
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
    }

    // 多 root：各文件夹独立 model；allModel 聚合跨源总数
    function test_multiRootIndependentModelsAndAggregate() {
        scanAndWait([fixtureDir, extraDir]);
        const m1 = htmlWallpaper.modelFor(String(fixtureDir));
        const m2 = htmlWallpaper.modelFor(String(extraDir));
        verify(m1 !== null && m2 !== null, "两个扫描根应有各自 model");
        compare(m1.count, 6, "fixtureDir 应收录 6 个");
        compare(m2.count, 2, "extraDir 应收录 2 个（red/blue）");

        // 全部视图：allModel 懒建并缓存同一实例
        // （聚合求和/跨源定位的 C++ 逻辑已由 tst_wallpapercontroller 覆盖）
        const all1 = htmlWallpaper.allModel();
        const all2 = htmlWallpaper.allModel();
        verify(all1 !== null, "allModel 应返回合并 model");
        compare(all1, all2, "allModel 应缓存同一实例（保活复用）");
    }

    // 移除扫描根后：modelCount 下降（releaseStaleModels）
    function test_removingRootDropsModel() {
        scanAndWait([fixtureDir, extraDir]);
        compare(htmlWallpaper.modelCount(), 2, "扫描两个根应有 2 个 model");

        htmlWallpaper.scanPaths = [fixtureDir];
        htmlWallpaper.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
        compare(htmlWallpaper.modelCount(), 1, "移除 extraDir 后其 model 应被释放");
    }
}
```

- [ ] **Step 10: 运行 tst_Parser + tst_WallpaperListModel**

```bash
cd /home/swix/Code/QtProjects/HTMLWallpaper/test && \
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import /home/swix/Code/QtProjects/HTMLWallpaper/build/bin -input tst_Parser.qml && \
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import /home/swix/Code/QtProjects/HTMLWallpaper/build/bin -input tst_WallpaperListModel.qml
```

Expected: 两个 QML 测试全 PASS。

- [ ] **Step 11: Commit**

```bash
git add plugin/wallpapercontroller.h plugin/wallpapercontroller.cpp plugin/wallpaperentry.h test/tst_wallpapercontroller.cpp test/CMakeLists.txt test/tst_Parser.qml test/tst_WallpaperListModel.qml
git commit -m "feat: 扫描编排上移 controller + modelFor/allModel 多 model 容器 + 命名统一 scanPaths"
```

---

### Task 4: QML 生产层改造（落地，形态有差异）

> **落地差异注记**：本任务执行完毕，但最终落地形态与下文步骤不同——中栏改为直接绑 controller
> 的 `activeModel`/`activeIndex`（`view.model: wallpaperController.activeModel`、
> `view.currentIndex: wallpaperController.activeIndex`），**删除了 `gridModel` 属性与
> `refreshModel()`**；delegate 点击写 `wallpaperController.activeIndex = index`（不再写
> `selectWallpaper`）；role 从 `model.title` 改为 `model.name`；`config.qml` 新增
> `cfg_SelectWallpaper` 别名与 `onScanPathsChanged: scan()`。当前形态见
> [ThumbnailsPanel.qml](../../package/contents/ui/view/ThumbnailsPanel.qml) /
> [ScanPathsPanel.qml](../../package/contents/ui/view/ScanPathsPanel.qml)。

**Files:**
- Modify: `package/contents/ui/view/ThumbnailsPanel.qml`
- Modify: `package/contents/ui/view/WallpaperDelegate.qml`
- Modify: `package/contents/ui/view/ScanPathsPanel.qml`
- Modify: `package/contents/ui/config.qml`

**Interfaces:**
- Consumes: Task 3 的 `modelFor`/`allModel`/`folderName`/`parentPath` 与新增 `activeModel`/`activeIndex`。
- Produces: 生产 QML 全链路新语义。Task 5 的测试 mock 对齐此形态。

- [ ] **Step 1: `package/contents/ui/view/ThumbnailsPanel.qml`——gridModel 改 allModel()/modelFor()、删 Connections、onClicked 单路径**

> **落地（与下文不同）：** 最终删除 `gridModel`/`refreshModel`，`view.model: wallpaperController.activeModel`
> + `view.currentIndex: wallpaperController.activeIndex`；`Connections onModelReset` 删除；delegate
> `onClicked` 写 `wallpaperController.activeIndex = index`（经 `required property QtObject wallpaperController`
> 注入）。下文 Step 1 代码为原始设想（保留供追溯）。

三处修改：

(1) `refreshModel()` 函数体替换：

```qml
    // 依 activeFolder 重新计算 gridModel，并滚回顶部、清空选中高亮
    function refreshModel() {
        if (!htmlWallpaper) {
            gridModel = null;
            return;
        }
        gridModel = activeFolder.length === 0
            ? htmlWallpaper.allModel()
            : htmlWallpaper.modelFor(activeFolder);
        wallpapersGrid.view.currentIndex = -1;
        wallpapersGrid.view.positionViewAtIndex(0, ListView.Beginning);
    }
```

同时把注释 `// 当前网格 model：全部 → htmlWallpaper.wallpapers；单组 → byKey(activeFolder)` 改为 `// 当前网格 model：全部 → controller.allModel()（懒建合并）；单文件夹 → controller.modelFor(activeFolder)`。

(2) 删除 `Connections onModelReset` 整块：

```qml
    // 重扫保护：WallpaperModel beginResetModel 时旧 byKey 快照失效，重算 gridModel
    Connections {
        target: htmlWallpaper && htmlWallpaper.wallpapers ? htmlWallpaper.wallpapers : null
        function onModelReset() { refreshModel(); }
    }
```

替换为空（整块删除）。model 实例常驻，`modelReset` 由 GridView 自动响应；全部模式合并 model 自身转发源 reset。

(3) delegate 的 `onClicked` 改为单路径：

```qml
                    onClicked: {
                        if (htmlWallpaper && model.path) {
                            htmlWallpaper.selectWallpaper = model.file;
                            wallpapersGrid.view.currentIndex = index;
                            console.log("Selected wallpaper:", model.file, "at index", index);
                        }
                    }
```

- [ ] **Step 2: `package/contents/ui/view/WallpaperDelegate.qml`——去 modelData 双路径**

> **落地（与下文不同）：** 最终 `text: model.name`（role 从 `title` 改 `name`）、`source: model.preview`
> 单路径；`onClicked` 由 ThumbnailsPanel 的 delegate 绑定写 `activeIndex`。`?? modelData.xxx`
> 双路径删除。

两处：

(1) `text: model.title ?? modelData.title` → `text: model.title`

(2) `source: model.preview ?? modelData.preview` → `source: model.preview`

同时把文件头注释"pendingDeletion 在 WallpaperModel/WallpaperItem/mock 三态下均为 undefined，无需 modelData 兜底"保留（依然成立），并可加一行说明"view.model 恒为真 QAbstractListModel，role 直接可用，不再需要 modelData 双路径"。

- [ ] **Step 3: `package/contents/ui/view/ScanPathsPanel.qml`——修复 allTab alias 编译错误 + folderName 改 controller**

> **落地（与下文不同）：** 最终 `allAction` 用 `checkable: true` + `checked: selectedFolder.length === 0`
> （Kirigami.Action 无 highlighted）；onTriggered 写 `wallpaperController.activeModel = wallpaperController.allModel()`；
> 文件夹 delegate onClicked 写 `wallpaperController.activeModel = wallpaperController.modelFor(modelData)`；
> folderName/parentPath 调用改 `wallpaperController.`（去掉 `wallpapers.`）。Step 3 代码为原始设想
> （`allTab` alias 修复保留落地，其余形态以下文为准）。

(1) 修复 alias：把 `allAction` 与 Add… action 从 `header` 内嵌提升到根 `ColumnLayout`（scanPathsPanel）作用域。在 `Kirigami.Separator` 之前插入两个 `Kirigami.Action`（非 Item，不参与 ColumnLayout 布局）：

```qml
    // —— 顶部动作 ——
    // header 内引用；根级定义使 property alias allTab 合法（header 内嵌 id 对根不可见）。
    // Kirigami.Action 非 Item，不参与 ColumnLayout 布局。
    Kirigami.Action {
        id: allAction
        icon.name: "all-wallpapers-symbolic"
        text: i18ndc("plasma_wallpaper_org.kde.image", "@action switch to look all wallpapers", "All")
        Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "All")
        highlighted: scanPathsPanel.selectedFolder.length === 0
        onTriggered: scanPathsPanel.selectedFolder = ""
    }

    Kirigami.Action {
        id: addFolderAction
        icon.name: "list-add-symbolic"
        text: i18ndc("plasma_wallpaper_org.kde.image", "@action button the thing being added is a folder", "Add…")
        Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Add Folder…")
        onTriggered: {
            const dialogComponent = Qt.createComponent("AddFolderDialog.qml");
            dialogComponent.createObject(scanPathsPanel, {
                addScanPath: (path) => {
                    htmlWallpaper.addScanPath(String(path));
                }
            });
            dialogComponent.destroy();
        }
    }
```

(2) header 的 `actions` 数组改为引用根级 id，删除内嵌 action 定义：

```qml
            header: Kirigami.InlineViewHeader {
                width: scanPathsView.width
                text: i18nd("plasma_wallpaper_org.kde.image", "Folders")
                actions: [
                    allAction,
                    addFolderAction
                ]
            }
```

(3) delegate 的 folderName/parentPath 调用改 controller（去掉 `wallpapers.`）：

```qml
                // 主标题只显示文件夹名（路径解析在 C++ WallpaperController 实现）
                text: htmlWallpaper.folderName(modelData)
                // Subtitle: the path to the folder
                // 副标题显示父目录路径（路径解析在 C++ WallpaperController 实现）
                subtitle: htmlWallpaper.parentPath(modelData)
```

同时更新文件头注释中 `目录列表 ← htmlWallpaper.scanPaths；壁纸网格 ← htmlWallpaper.wallpapers（WallpaperModel）。` 改为 `目录列表 ← htmlWallpaper.scanPaths；壁纸网格 ← htmlWallpaper.modelFor/allModel（每文件夹一个 WallpaperModel）。`。

- [ ] **Step 4: 构建 + 运行 tst_Smoke**

```bash
cmake --build /home/swix/Code/QtProjects/HTMLWallpaper/build && \
cd /home/swix/Code/QtProjects/HTMLWallpaper/test && \
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import /home/swix/Code/QtProjects/HTMLWallpaper/build/bin -input tst_Smoke.qml
```

Expected: tst_Smoke 全 PASS（allTab alias 修复后 config.qml / ScanPathsPanel.qml 编译恢复）。

- [ ] **Step 5: Commit**

```bash
git add package/contents/ui/view/ThumbnailsPanel.qml package/contents/ui/view/WallpaperDelegate.qml package/contents/ui/view/ScanPathsPanel.qml
git commit -m "feat: 中栏 modelFor/allModel 切换 + 去 modelData 双路径 + 修复 allTab alias 编译错误"
```

---

### Task 5: QML 测试同步 + 全量回归（落地，形态有差异）

> **落地差异注记**：mock 最终以 `wallpaperController` 命名（非 `htmlWallpaper`），并新增
> `activeModel` 属性（默认 `allModel()`，由 ScanPathsPanel 点击驱动）；`FolderTabsHost` 暴露
> `wallpaperControllerController` 别名，ThumbnailsPanel 经 `wallpaperController` 注入绑
> `activeModel`/`activeIndex`（不再有 `activeFolder` 联动）。**已知遗留：** `tst_FolderTabs` /
> `tst_ThumbnailsHighlight` 在 HEAD 失败（activeModel/activeIndex 绑定层问题：activeIndex mock
> 缺失 / activeModel 绑定循环），与 C++ 数据层改动无关。

**Files:**
- Modify: `test/FolderTabsHost.qml`
- Modify: `test/tst_FolderTabs.qml`
- Modify: `test/ThumbnailsHost.qml`
- Modify: `test/tst_ThumbnailsBinding.qml`
- Modify: `test/tst_ThumbnailsHighlight.qml`

**Interfaces:**
- Consumes: Task 4 的生产 QML（activeModel/activeIndex + modelFor/allModel/folderName 形态）。
- Produces: 全仓测试绿（除已知遗留的 activeModel/activeIndex 绑定用例）。

- [ ] **Step 1: 重写 `test/FolderTabsHost.qml`——scanPaths 命名 + modelFor/allModel mock**

整文件替换为：

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../package/contents/ui/view" as View

/**
 * 模拟 config.qml 的左栏-中栏联动结构，用于验证标签切换。
 *
 * 复刻 config.qml 关键结构：根内声明控制器子对象，ScanPathsPanel 与
 * ThumbnailsPanel 并排，ThumbnailsPanel.activeFolder 绑定
 * scanPathsPanel.selectedFolder（经 root 别名引用外层控制器避开同名遮蔽）。
 * 暴露 scanPathsView/thumbnails 供测试断言。
 *
 * mock（htmlWallpaper）模拟新架构：每文件夹一个 model（groupA/groupB），
 * modelFor(url) 按 URL 返回对应组；allModel() 返回合并缓存数组。
 */
ColumnLayout {
    id: root

    // offscreen 下显式尺寸：让 ScanPathsPanel 内部 ListView 有布局空间、
    // 从而实例化 delegate（测试触发其 clicked 需要真实 delegate 实例）
    width: 800
    height: 400

    property alias htmlWallpaperController: htmlWallpaper
    // 暴露两个面板供测试断言
    property Item scanPathsView: null
    property Item thumbnails: null

    // 模拟 config.qml 外层控制器（新架构：modelFor/allModel）
    QtObject {
        id: htmlWallpaper
        property string selectWallpaper: ""
        // scanPaths：两个扫描根
        property var scanPaths: ["file:///root/a", "file:///root/b"]

        // 每文件夹一个 model：groupA / groupB
        property var groupA: [
            { name: "a1", title: "a1", path: "file:///a1.html", file: "file:///a1.html", preview: "" },
            { name: "a2", title: "a2", path: "file:///a2.html", file: "file:///a2.html", preview: "" }
        ]
        property var groupB: [
            { name: "b1", title: "b1", path: "file:///b1.html", file: "file:///b1.html", preview: "" }
        ]

        // 合并缓存：首次 allModel() 调用构建，之后返回同一引用（供引用相等断言）
        property var allModelCache: null
        function allModel() {
            if (allModelCache === null) {
                const all = [];
                for (const g of [groupA, groupB]) {
                    for (const e of g) {
                        all.push(e);
                    }
                }
                allModelCache = all;
            }
            return allModelCache;
        }

        // modelFor：key 归一化（去末尾斜杠）后返回对应组
        function modelFor(url) {
            const key = String(url).replace(/\/+$/, "");
            if (key === "file:///root/a") return groupA;
            if (key === "file:///root/b") return groupB;
            return [];
        }

        // 模拟 controller.folderName：去末尾斜杠后取最后一段
        function folderName(url) {
            const s = String(url).replace(/\/+$/, "");
            return s.substring(s.lastIndexOf("/") + 1);
        }
        // 模拟 controller.parentPath：去末尾斜杠后去掉最后一段
        function parentPath(url) {
            const s = String(url).replace(/\/+$/, "");
            return s.substring(0, s.lastIndexOf("/"));
        }

        function addScanPath(url) { scanPaths.push(String(url)); }
        function removeScanPath(url) {
            scanPaths = scanPaths.filter(function (u) { return u !== String(url); });
        }
    }

    View.ScanPathsPanel {
        id: scanPathsPanel
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: 320
        htmlWallpaper: htmlWallpaper
    }

    View.ThumbnailsPanel {
        id: thumbnailsPanel
        Layout.fillWidth: true
        Layout.fillHeight: true
        htmlWallpaper: root.htmlWallpaperController
        // 标签联动（复刻 config.qml）
        activeFolder: scanPathsPanel.selectedFolder
        width: 600
        height: 400
    }

    Component.onCompleted: {
        root.scanPathsView = scanPathsPanel;
        root.thumbnails = thumbnailsPanel;
    }
}
```

- [ ] **Step 2: 重写 `test/tst_FolderTabs.qml`——scanPaths 命名 + allModel() 断言**

整文件替换为：

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 标签式分组展示集成测试：左栏点击标签 → 中栏缩略图视图切换。
 *
 * 锁定 config 层联动（新架构 modelFor/allModel）：
 *   - 默认选中"全部"：ThumbnailsPanel.view.model === allModel()（合并）
 *   - 点击文件夹标签 → activeFolder = 该 URL，view.model === modelFor(url)
 *   - 点击"全部"标签 → view.model 切回 allModel()
 *   - 切换标签后 view.currentIndex 复位为 -1（清高亮）
 *
 * 环境注意：htmlWallpaper 用 mock（scanPaths 数组 + modelFor/allModel 缓存数组）；
 * i18n 函数 mock。
 */
TestCase {
    id: testCase
    name: "FolderTabsTests"

    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    property var host: null

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    function init() {
        let c = Qt.createComponent("FolderTabsHost.qml");
        verify(c.status === Component.Ready, "FolderTabsHost 加载失败: " + c.errorString());
        host = c.createObject(testCase);
        verify(host !== null, "host 实例化失败");
        verify(waitForCondition(() => host.scanPathsView !== null, 2000), "面板未就绪");
        c.destroy();
    }

    function cleanup() {
        if (host) {
            host.destroy();
            host = null;
        }
    }

    // 默认"全部"：view.model 是 allModel() 返回的合并缓存数组
    function test_defaultShowsAll() {
        compare(host.thumbnails.activeFolder, "");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        // 全部模式下 view.model 即 allModel() 引用（缓存数组）
        compare(host.thumbnails.view.model, host.htmlWallpaperController.allModel());
    }

    // 点击文件夹标签：触发 ListView delegate 的 clicked 信号（等价真实点击），
    // 锁定 onClicked: selectedFolder = modelData 这条链路；后续
    // activeFolder→gridModel 断言与绑定链验证（tst_FolderTabs 其余用例）一致。
    function test_clickFolderShowsGroup() {
        const list = host.scanPathsView.folderList;
        verify(waitForCondition(() => list.count === 2, 2000), "scanPaths 未就绪");
        list.currentIndex = 0;
        verify(waitForCondition(() => list.currentItem !== null, 2000), "文件夹 delegate 未实例化");
        list.currentItem.clicked();
        compare(host.scanPathsView.selectedFolder, "file:///root/a");
        compare(host.thumbnails.activeFolder, "file:///root/a");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        // 单文件夹模式：view.model 应为 groupA（modelFor("file:///root/a") 返回的数组）
        compare(host.thumbnails.view.model.length, 2);
        compare(host.thumbnails.view.model[0].title, "a1");
    }

    // 点击"全部"标签 → 切回全部（先经真实点击选中某文件夹，再触发 allTab）
    function test_clickAllRestoresAll() {
        const list = host.scanPathsView.folderList;
        list.currentIndex = 1;
        verify(waitForCondition(() => list.currentItem !== null, 2000), "文件夹 delegate 未实例化");
        list.currentItem.clicked();
        compare(host.scanPathsView.selectedFolder, "file:///root/b");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.model.length, 1);

        // 触发 header 的"全部"动作 → selectedFolder 置空
        host.scanPathsView.allTab.triggered();
        compare(host.scanPathsView.selectedFolder, "");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.model, host.htmlWallpaperController.allModel());
        compare(host.thumbnails.view.model.length, 3);
    }

    // 切换标签后 currentIndex 复位（清高亮）
    function test_switchResetsCurrentIndex() {
        host.thumbnails.view.currentIndex = 2;
        // 先固化前置：赋值确实生效（否则断言 -1 会退化为"本来就 -1"的弱自证）
        compare(host.thumbnails.view.currentIndex, 2);
        host.scanPathsView.selectedFolder = "file:///root/a";
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.currentIndex, -1);
    }
}
```

- [ ] **Step 3: 重写 `test/ThumbnailsHost.qml`——wallpapers → modelFor/allModel（ListModel）**

整文件替换为：

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import "../package/contents/ui/view" as View

/**
 * 模拟 config.qml 的嵌套结构，用于验证 ThumbnailsPanel 的控制器绑定解析。
 *
 * 复刻 config.qml 的关键结构：根 ColumnLayout(id: root) 内声明一个与
 * 子面板同名（htmlWallpaper）的控制器子对象，经 root 别名属性
 * （htmlWallpaperController）暴露给 ThumbnailsPanel，验证组件内声明式
 * binding 下经别名引用能正确解析到外层控制器，而非被面板自身同名属性
 * 遮蔽成自引用 Binding loop。
 *
 * mock（htmlWallpaper）模拟新架构：单文件夹 ListModel（modelA）经
 * modelFor/allModel 返回，供 ThumbnailsPanel 全部模式取全部数据。
 */
ColumnLayout {
    id: root

    // 经别名把外层控制器暴露给子组件（名避开面板自身属性名 htmlWallpaper）
    property alias htmlWallpaperController: htmlWallpaper

    // 模拟 config.qml 外层控制器（WallpaperController { id: htmlWallpaper }）
    QtObject {
        id: htmlWallpaper
        property string selectWallpaper: ""
        // 单文件夹 model：ListModel（真 model，role 可用）
        ListModel {
            id: modelA
            ListElement { name: "a"; title: "a"; path: "file:///a.html"; file: "file:///a.html"; preview: "" }
        }
        // 新架构：modelFor/allModel 返回该文件夹 model
        function modelFor(url) { return modelA; }
        function allModel() { return modelA; }
    }

    // 暴露面板供测试断言
    property Item panel: null

    View.ThumbnailsPanel {
        id: panelItem
        // 经 root 别名引用外层控制器，避开自身同名属性遮蔽
        htmlWallpaper: root.htmlWallpaperController
        width: 600
        height: 400
    }

    Component.onCompleted: {
        root.panel = panelItem
    }
}
```

- [ ] **Step 4: 重写 `test/tst_ThumbnailsBinding.qml`——断言改 allModel()**

整文件替换为：

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 控制器绑定解析回归测试（防自引用 Binding loop）。
 *
 * config.qml 里 ThumbnailsPanel 的 htmlWallpaper 绑定必须经 root 别名
 * （htmlWallpaperController）引用外层控制器；若写裸 htmlWallpaper，会被
 * ThumbnailsPanel 自身同名属性遮蔽成自引用（面板拿到 null，中栏网格为空）。
 * 此测试经 ThumbnailsHost（模拟 config.qml 嵌套结构）锁定修复后语义：
 *   - 面板 htmlWallpaper 非 null 且等于外层控制器；
 *   - 面板 view.model 连到外层 allModel()；
 *   - root 自身无 htmlWallpaper 属性（裸标识符会遮蔽外层 id 的根因）。
 *
 * 环境注意：htmlWallpaper 用 mock（QtObject 声明 selectWallpaper 属性 +
 * modelFor/allModel 返回的 ListModel）；KDeclarative 国际化函数在
 * qmltestrunner 不可用，用同名 property 注入 mock。
 */
TestCase {
    id: testCase
    name: "ThumbnailsBindingTests"

    // KDeclarative 国际化函数 mock（返回原文；动态创建的子组件经作用域链解析）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    // config.qml 修复写法（root 别名）：面板应拿到外层控制器
    function test_nestedAliasBinding_resolvesOuter() {
        let c = Qt.createComponent("ThumbnailsHost.qml");
        verify(c.status === Component.Ready, "ThumbnailsHost 加载失败: " + c.errorString());
        let host = c.createObject(testCase);
        verify(host !== null, "host 实例化失败");
        verify(waitForCondition(() => host.panel !== null, 2000), "panel 未就绪");

        // 修复写法下面板拿到外层控制器（非 null、非自引用）
        verify(host.panel.htmlWallpaper !== null, "修复写法下面板 htmlWallpaper 不应为 null");
        compare(host.panel.htmlWallpaper, host.htmlWallpaperController);
        // 面板模型连到外层 allModel()
        compare(host.panel.view.model, host.htmlWallpaperController.allModel());

        // 对照：root 自身无 htmlWallpaper 属性（裸 htmlWallpaper 会遮蔽外层 id）
        verify(host.htmlWallpaper === undefined,
               "root.htmlWallpaper 应为 undefined（root 无此属性）");

        host.destroy();
        c.destroy();
    }
}
```

- [ ] **Step 5: 重写 `test/tst_ThumbnailsHighlight.qml`——mock 改 modelFor/allModel（ListModel）**

整文件替换为：

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 缩略图点击联动行为测试（点击驱动高亮）。
 *
 * 锁定 ThumbnailsPanel 中 WallpaperDelegate 的 onClicked 行为：
 * 点击某缩略图 → htmlWallpaper.selectWallpaper = model.file，
 * 且 wallpapersGrid.view.currentIndex = index（高亮跟随点击项）。
 * 不做反向同步：不验证 selectWallpaper 变化反向驱动高亮。
 *
 * 环境注意：htmlWallpaper 用 mock（QtObject 声明 selectWallpaper 属性 +
 * modelFor/allModel 返回的 ListModel）。ListModel 是真 model，delegate 里
 * model.path 等 role 可直接读（单路径）。QML 属性 selectWallpaper 会自动
 * 生成隐式 selectWallpaperChanged 信号，因此不能再显式声明同名 signal
 * （会触发 "Duplicate signal name" 解析错误）。
 */
TestCase {
    id: testCase
    name: "ThumbnailsHighlightTests"

    // KDeclarative 国际化函数 mock（返回原文；动态创建的子组件经作用域链解析）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    property var htmlWallpaper: null
    property var comp: null

    function init() {
        // htmlWallpaper mock：selectWallpaper（可写属性）+ 单文件夹 ListModel
        // （modelFor/allModel 返回；元素含 file/path/title/preview 字段，供
        // delegate 与 onClicked 读取）。
        // 注意：createQmlObject 内联对象体成员必须以换行分隔。
        htmlWallpaper = Qt.createQmlObject(
            'import QtQuick;'
            + '\nQtObject {'
            + '\n  property string selectWallpaper: ""'
            + '\n  ListModel { id: modelA'
            + '\n    ListElement { name: "a"; title: "a"; path: "file:///a.html"; file: "file:///a.html"; preview: "" }'
            + '\n    ListElement { name: "b"; title: "b"; path: "file:///b.html"; file: "file:///b.html"; preview: "" }'
            + '\n    ListElement { name: "c"; title: "c"; path: "file:///c.html"; file: "file:///c.html"; preview: "" }'
            + '\n  }'
            + '\n  function modelFor(url) { return modelA; }'
            + '\n  function allModel() { return modelA; }'
            + '\n}',
            testCase);
        verify(htmlWallpaper !== null, "htmlWallpaper mock 实例化失败");

        let c = Qt.createComponent("../package/contents/ui/view/ThumbnailsPanel.qml");
        verify(c.status === Component.Ready, "ThumbnailsPanel 加载失败: " + c.errorString());
        // 给足尺寸让 GridView 实例化可见 delegate（offscreen 下显式宽高驱动布局）
        comp = c.createObject(testCase, { htmlWallpaper: htmlWallpaper, width: 600, height: 400 });
        verify(comp !== null, "ThumbnailsPanel 实例化失败");
        c.destroy();
    }

    function cleanup() {
        if (comp) {
            comp.destroy();
            comp = null;
        }
        if (htmlWallpaper) {
            htmlWallpaper.destroy();
            htmlWallpaper = null;
        }
    }

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    // 定位到第 i 项并触发其 delegate 的 clicked 信号（等价点击缩略图）。
    // 触发前把 currentIndex 复位到别的索引（(i + 1) % 3），使随后的
    // compare(currentIndex, i) 真实验证 onClicked 把高亮移回点击项，
    // 而非因预先设了 currentIndex=i 而恒真（自证循环）。
    function clickIndex(i) {
        comp.view.currentIndex = i;
        verify(waitForCondition(() => comp.view.currentItem !== null, 2000),
               "索引 " + i + " 的 delegate 未实例化");
        const delegate = comp.view.currentItem;   // 持有第 i 项 delegate
        comp.view.currentIndex = (i + 1) % 3;     // 复位到别的索引，使 currentIndex 断言有意义
        delegate.clicked();                        // 触发 onClicked（delegate 的 model context 仍有效）
    }

    // 点击缩略图 → selectWallpaper = model.file，currentIndex = index
    function test_clickDelegate_setsSelectWallpaperAndIndex() {
        // 初始 selectWallpaper 为空；点击第 0 项
        clickIndex(0);
        compare(htmlWallpaper.selectWallpaper, htmlWallpaper.allModel().get(0).file);
        compare(comp.view.currentIndex, 0);

        // 点击第 1 项 → 选中与高亮跟随点击项
        clickIndex(1);
        compare(htmlWallpaper.selectWallpaper, htmlWallpaper.allModel().get(1).file);
        compare(comp.view.currentIndex, 1);
    }
}
```

- [ ] **Step 6: 全量回归 ctest**

```bash
cd /home/swix/Code/QtProjects/HTMLWallpaper/build && ctest
```

Expected: C++ 单测全 PASS；QML 测试已知遗留——`tst_FolderTabs`/`tst_ThumbnailsHighlight` 在 HEAD 失败（activeModel/activeIndex 绑定层问题），与 C++ 数据层改动无关。

- [ ] **Step 7: Commit**

```bash
git add test/FolderTabsHost.qml test/tst_FolderTabs.qml test/ThumbnailsHost.qml test/tst_ThumbnailsBinding.qml test/tst_ThumbnailsHighlight.qml
git commit -m "test: QML 测试同步 modelFor/allModel 形态并统一 scanPaths 命名"
```
