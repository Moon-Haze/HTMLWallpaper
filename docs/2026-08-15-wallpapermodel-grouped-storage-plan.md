# WallpaperModel 按扫描路径分组存储实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `WallpaperModel` 的条目存储从扁平 `QList<WallpaperItem>` 改为按扫描路径分组的 `QHash<QString, QList<WallpaperItem *>>`，保持对外扁平 API 不变，并新增分组访问接口。

**Architecture:** `m_items`（QHash 分类存储）+ `m_groupOrder`（key 插入顺序）+ `m_flat`（扁平视图缓存）三者同步维护。`scan()` 后台一次性扫完所有 root，`ScanResult` 按 root 归组（`QList<ScanGroup>`），完成后 `clear()` + 逐组 `addEntries`。`WallpaperItem*` 由模型显式所有，addEntries 覆盖 / clear 时 `qDeleteAll`。

**Tech Stack:** Qt6 / KF6 Plasma 插件（QAbstractListModel + QtConcurrent）；QML 测试（qmltestrunner, Qt6 版）；C++ QTest 单测。

**Spec:** `docs/2026-08-15-wallpapermodel-grouped-storage-design.md`

## Global Constraints

- 构建：`cmake --preset native`（已配置 build 目录）；增量构建 `cmake --build build`
- 测试：`ctest --test-dir build -R <test名> --output-on-failure`；QML 测试在 offscreen 下跑（Qt6 qmltestrunner）
- 新文件必须带 SPDX 头：`SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>` + `SPDX-License-Identifier: GPL-2.0-or-later`
- 代码注释与 commit message 用中文（项目习惯）
- 对外扁平 API（count/get/data/roles/indexOf）语义不变；controller / config.qml / ThumbnailsPanel 不改动
- 分组 key = 扫描根 URL 的归一化形式（`WallpaperPath::toUrl` 结果），`byKey` 入参同样归一化后匹配

---

### Task 1: 完成 WallpaperModel 分组存储实现（恢复编译）

当前代码处于半重构状态（头文件声明 QHash 分组，实现仍是扁平 QList），编译不过。本任务把数据层与模型一次性改到位，恢复编译并保证现有回归测试通过。

**Files:**
- Modify: `plugin/wallpaperentry.h`（ScanResult → 按 root 分组）
- Modify: `plugin/wallpapermodel.h`（成员 / 接口 / 注释）
- Modify: `plugin/wallpapermodel.cpp`（实现重写）
- Modify: `plugin/wallpaperitem.h`（删拷贝构造 / operator=）
- Modify: `plugin/wallpaperitem.cpp`（删拷贝构造 / operator= 定义）

**Interfaces:**
- Produces: `WallpaperModel::addEntries(const QString &key, const QList<WallpaperEntry> &wallpapers)`（Q_INVOKABLE，按 key 覆盖整组）；`WallpaperModel::byKey(const QString &key)` → `QList<WallpaperItem *>`（整组）；`WallpaperModel::keys()` → `QStringList`（保序）；`WallpaperModel::groupCount()` → `int`；`struct ScanGroup { QString key; QList<WallpaperEntry> entries; }`；`ScanResult { QList<ScanGroup> groups; QList<QPair<QString,QString>> failures; }`。Task 2/3 依赖以上签名。

- [ ] **Step 1: 改 `plugin/wallpaperentry.h` 的 ScanResult 分组**

把 `wallpaperentry.h` 第 22-26 行的 `ScanResult` 改为：

```cpp
struct ScanGroup {
    QString key;                       // 扫描根 URL（WallpaperPath::toUrl 归一化）
    QList<WallpaperEntry> entries;     // 该根下探测到的壁纸
};

struct ScanResult {
    QList<ScanGroup> groups;           // 按 roots 遍历顺序保序
    QList<QPair<QString, QString>> failures; // (path, error)
};
```

（保留 `QPair` / `QStringList` include，不变。）

- [ ] **Step 2: 改 `plugin/wallpaperitem.h` 删拷贝语义**

删除第 32-33 行：

```cpp
    explicit WallpaperItem(const WallpaperItem &item, QObject *parent = nullptr);
    WallpaperItem &operator=(const WallpaperItem &item);
```

- [ ] **Step 3: 改 `plugin/wallpaperitem.cpp` 删对应定义**

删除第 15-26 行的 `WallpaperItem::WallpaperItem(const WallpaperItem &...)` 与 `operator=` 两个定义。

- [ ] **Step 4: 改 `plugin/wallpapermodel.h`**

整文件改为：

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QStringList>
#include <qobject.h>
#include <qtmetamacros.h>

#include "wallpaperentry.h"
#include "wallpaperitem.h"

template<typename T>
class QFutureWatcher;

/**
 * @brief 扫描结果壁纸列表模型（WallpaperController::wallpapers，列表层，自治扫描）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) 与 data()。roles 对齐 WallpaperDelegate / ThumbnailsView
 * 使用的字段：name / title / path / preview / file（file 是目录探测选出的
 * *.html 入口）。
 *
 * 条目按扫描路径（每个扫描根 URL）分组存储于 m_items（QHash<QString,
 * QList<WallpaperItem *>>），m_groupOrder 记录分组 key 插入顺序，m_flat 为
 * 扁平视图缓存（对外的 rowCount/data/get 直接索引）。addEntries(key, ...)
 * 替换 key 对应整组（同 key 覆盖）；scan() 后台一次性扫完所有 root，
 * 完成后 clear() + 逐组 addEntries。byKey(key) 返回整组，keys() 返回保序
 * 分组列表，为将来 UI 分组 / 局部重扫预留。
 */
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(bool scanInProgress READ scanInProgress NOTIFY scanInProgressChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        TitleRole,
        PathRole,
        PreviewRole,
        FileRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperModel(QObject *parent = nullptr);

    int count() const;
    bool scanInProgress() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 替换 key（扫描根 URL）对应整组条目；同 key 覆盖（先 delete 旧组指针）。
     *  主线程调用；每次完整重置模型。 */
    Q_INVOKABLE void addEntries(const QString &key, const QList<WallpaperEntry> &wallpapers);

    void clear();

    /** 兼容原 ListModel：返回第 i 项属性门面对象；越界返回 nullptr。 */
    Q_INVOKABLE WallpaperItem *get(int i);

    /** 按条目 source（html 文件 URL）返回扁平行号；未找到返回 -1。 */
    Q_INVOKABLE int indexOf(const QString &source) const;

    /** 按扫描路径（归一化 URL）返回该组全部 WallpaperItem*；不存在返回空列表。 */
    Q_INVOKABLE QList<WallpaperItem *> byKey(const QString &key);

    /** 保序的分组 key（扫描根 URL）列表。 */
    Q_INVOKABLE QStringList keys() const;

    /** 分组数。 */
    Q_INVOKABLE int groupCount() const;

    // —— 自治扫描 ——
    /** 后台扫描 roots 下各壁纸目录并按 root 分组填充模型；完成后发 scanFinished。 */
    Q_INVOKABLE void scan(const QStringList &roots);

Q_SIGNALS:
    /** 扫描全部完成（可能部分子目录解析失败，已发 scanFailed）。 */
    void scanFinished();
    /** 某个根目录无法读取时发出（path：根目录 url，error：底层错误字符串）。 */
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    void setScanInProgress(bool inProgress);
    /** 按 m_groupOrder 顺序重建 m_flat（m_items 变化后调用）。 */
    void rebuildFlat();

    QHash<QString, QList<WallpaperItem *>> m_items; // 分类存储：key = 扫描根 URL
    QStringList m_groupOrder;                       // key 插入顺序，驱动 keys() 与扁平化
    QList<WallpaperItem *> m_flat;                  // 扁平视图缓存
    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
```

- [ ] **Step 5: 改 `plugin/wallpapermodel.cpp`**

整文件改为：

```cpp
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapermodel.h"

#include "wallpaperitem.h"

#include <QDir>
#include <QFutureWatcher>
#include <QtAlgorithms>
#include <QtConcurrent>
#include <QUrl>

namespace
{

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
        result.groups.append(group);
    }
    return result;
}

} // namespace

WallpaperModel::WallpaperModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int WallpaperModel::count() const
{
    return m_flat.size();
}

bool WallpaperModel::scanInProgress() const
{
    return m_scanning;
}

void WallpaperModel::setScanInProgress(bool inProgress)
{
    if (m_scanning == inProgress) {
        return;
    }
    m_scanning = inProgress;
    Q_EMIT scanInProgressChanged();
}

int WallpaperModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_flat.size();
}

QVariant WallpaperModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_flat.size()) {
        return {};
    }
    auto item = m_flat.at(index.row());
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

void WallpaperModel::addEntries(const QString &key, const QList<WallpaperEntry> &wallpapers)
{
    const QString normKey = WallpaperPath::toUrl(key);
    beginResetModel();
    auto it = m_items.find(normKey);
    if (it != m_items.end()) {
        qDeleteAll(it.value()); // 释放旧组所有 WallpaperItem*（QObject parent 为本模型）
        it.value().clear();
    }
    QList<WallpaperItem *> &group = m_items[normKey];
    for (const WallpaperEntry &entry : wallpapers) {
        group.append(new WallpaperItem(entry, this));
    }
    if (!m_groupOrder.contains(normKey)) {
        m_groupOrder.append(normKey);
    }
    rebuildFlat();
    endResetModel();
}

void WallpaperModel::clear()
{
    beginResetModel();
    for (auto it = m_items.begin(); it != m_items.end(); ++it) {
        qDeleteAll(it.value());
    }
    m_items.clear();
    m_groupOrder.clear();
    m_flat.clear();
    endResetModel();
}

void WallpaperModel::rebuildFlat()
{
    m_flat.clear();
    for (const QString &key : m_groupOrder) {
        m_flat += m_items.value(key);
    }
}

int WallpaperModel::indexOf(const QString &source) const
{
    for (int i = 0; i < m_flat.size(); ++i) {
        if (m_flat.at(i)->source() == source) {
            return i;
        }
    }
    return -1;
}

WallpaperItem *WallpaperModel::get(int i)
{
    if (i < 0 || i >= m_flat.size()) {
        return nullptr;
    }
    return m_flat.at(i);
}

QList<WallpaperItem *> WallpaperModel::byKey(const QString &key)
{
    return m_items.value(WallpaperPath::toUrl(key));
}

QStringList WallpaperModel::keys() const
{
    return m_groupOrder;
}

int WallpaperModel::groupCount() const
{
    return m_items.size();
}

void WallpaperModel::scan(const QStringList &roots)
{
    if (m_scanning) {
        return;
    }
    setScanInProgress(true);
    clear();

    if (!m_watcher) {
        m_watcher = new QFutureWatcher<ScanResult>(this);
        QObject::connect(m_watcher, &QFutureWatcher<ScanResult>::finished, this, [this]() {
            const ScanResult result = m_watcher->result();
            for (const auto &failure : result.failures) {
                Q_EMIT scanFailed(failure.first, failure.second);
            }
            for (const auto &group : result.groups) {
                addEntries(group.key, group.entries);
            }
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWallpapers, roots));
}
```

- [ ] **Step 6: 增量构建**

Run: `cmake --build build`
Expected: 编译通过，无错误（warning 无新增）。

- [ ] **Step 7: 回归现有 QML 测试**

Run: `ctest --test-dir build -R "tst_WallpaperListModel|tst_Parser|tst_Smoke|tst_MainCompile|tst_Thumbnails" --output-on-failure`
Expected: 全部 PASS。
注意：`tst_Parser` 的 `test_scanUrls_addRemove` 若因 `addScanPath` 报错（controller 已改名 `addScanUrl`，属用户 ScanUrls 重构的预存残留），属于既有问题，本任务不修——其余用例应 PASS。

- [ ] **Step 8: Commit**

```bash
git add plugin/wallpaperentry.h plugin/wallpapermodel.h plugin/wallpapermodel.cpp plugin/wallpaperitem.h plugin/wallpaperitem.cpp
git commit -m "refactor: WallpaperModel 按扫描路径分组存储(恢复编译)

m_items 改 QHash<QString,QList<WallpaperItem*>>,新增 m_groupOrder 保序与
m_flat 扁平视图缓存;addEntries 按 key 覆盖整组并 qDeleteAll 旧指针;
byKey 改取整组,新增 keys/groupCount;ScanResult 改 QList<ScanGroup> 按
root 归组;WallpaperItem 删拷贝语义。对外扁平 API 不变,UI 暂不分。
"
```

---

### Task 2: 多 root 分组 QML 测试

验证分组接口从 QML 可用：`keys()` 保序、`groupCount`、`count` 汇总、`byKey` 组内成员、`indexOf` 仍命中。需要第二个扫描根 fixture。

**Files:**
- Create: `test/data/extra/red/index.html`（内容 `<!-- red -->`）
- Create: `test/data/extra/blue/main.html`（内容 `<!-- blue -->`）
- Modify: `test/tst_WallpaperListModel.qml`

**Interfaces:**
- Consumes: Task 1 产出的 `keys()/groupCount()/byKey(key)/indexOf(source)`；`WallpaperModel` 经 `htmlWallpaper.wallpapers` 暴露给 QML。

- [ ] **Step 1: 写失败测试（新增 fixtures + 用例）**

新建 `test/data/extra/red/index.html`：

```html
<!-- red fixture for multi-root grouping test -->
```

新建 `test/data/extra/blue/main.html`：

```html
<!-- blue fixture for multi-root grouping test -->
```

在 `test/tst_WallpaperListModel.qml` 中：

1. 第 24 行后加属性：

```qml
    // 第二个扫描根：red / blue 两个壁纸目录
    property url extraDir: Qt.resolvedUrl("data/extra")
```

2. 新增辅助函数与两个测试函数（放在 `test_outOfBoundsGetReturnsNull` 之后）：

```qml
    // 扫描 [fixtureDir, extraDir] 两个根并等待 scanFinished
    function scanMultiRoots() {
        htmlWallpaper.scanUrls = [fixtureDir, extraDir];
        htmlWallpaper.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
        return htmlWallpaper.wallpapers;
    }

    // 多 root 分组：keys 保序、groupCount、count 汇总、byKey 组内成员
    function test_multiRootGrouping() {
        const model = scanMultiRoots();
        compare(model.count, 8, "期望 8 个壁纸(6+2)，实际 " + model.count);
        compare(model.groupCount(), 2, "期望 2 个分组");

        const keys = model.keys();
        compare(keys.length, 2, "keys 应有 2 项");
        compare(String(keys[0]), String(fixtureDir), "第一组应为 fixtureDir");
        compare(String(keys[1]), String(extraDir), "第二组应为 extraDir");

        // byKey 取整组
        const groupA = model.byKey(fixtureDir);
        verify(groupA !== null, "byKey(fixtureDir) 不应为 null");
        compare(groupA.length, 6, "fixtureDir 组应含 6 个壁纸");
        compare(String(groupA[0].name), "aurora", "fixtureDir 组第一个应为 aurora");

        const groupB = model.byKey(extraDir);
        compare(groupB.length, 2, "extraDir 组应含 2 个壁纸");
        compare(String(groupB[0].name), "blue", "extraDir 组第一个应为 blue(字母序)");

        // 不存在 key → 空数组
        const missing = model.byKey("file:///nonexistent");
        verify(missing !== null, "byKey 不存在 key 应返回空数组而非 null");
        compare(missing.length, 0, "不存在 key 应返回空组");
    }

    // 扁平顺序：groupOrder 顺序 × 组内字母序；indexOf 仍按 source 命中
    function test_flatOrderAcrossGroups() {
        const model = scanMultiRoots();
        compare(String(model.get(0).name), "aurora", "扁平第一个应为 aurora");
        compare(String(model.get(6).name), "blue", "扁平第 7 个(索引 6)应为 blue");

        compare(model.indexOf(String(model.get(0).source)), 0, "aurora 行号应为 0");
        compare(model.indexOf(String(model.get(6).source)), 6, "blue 行号应为 6");
        compare(model.indexOf("file:///nonexistent.html"), -1, "不存在 source 应返回 -1");
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cmake --build build && ctest --test-dir build -R tst_WallpaperListModel --output-on-failure`
Expected: `test_multiRootGrouping` / `test_flatOrderAcrossGroups` FAIL（Task 1 实现已含分组接口，此处"失败"步骤实际应为 PASS；若实现缺失则该测试失败——本步骤用于确认测试被收集且逻辑自洽）。

说明：Task 1 已实现分组接口，此步骤的语义是"测试先行验证接口"；预期 PASS，若 FAIL 说明 Task 1 实现与测试期望不一致，需回查。

- [ ] **Step 3: Commit**

```bash
git add test/data/extra test/tst_WallpaperListModel.qml
git commit -m "test: 新增多 root 分组用例与第二个扫描根 fixtures
验证 keys 保序/groupCount/count 汇总/byKey 组内成员/indexOf 命中。"
```

---

### Task 3: addEntries 覆盖与生命周期 C++ 单测

用 C++ QTest 直接调 `addEntries`，验证同 key 覆盖时旧 `WallpaperItem*` 被释放（QPointer 变 null）、分组数/总数正确、clear 清空全部。用无效 `WallpaperEntry()`（默认构造）即可测纯结构，不依赖文件系统。

**Files:**
- Create: `test/tst_wallpapermode.cpp`
- Modify: `test/CMakeLists.txt`

**Interfaces:**
- Consumes: Task 1 的 `addEntries(key, wallpapers)` / `keys()` / `groupCount()` / `byKey(key)` / `count` / `clear()`。

- [ ] **Step 1: 写失败测试（新建 C++ 测试文件）**

新建 `test/tst_wallpapermode.cpp`：

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
 * WallpaperModel 分组存储的 C++ 单测。
 *
 * 直接构造无效 WallpaperEntry()（目录探测的空条目）验证分组/覆盖/清空等
 * 纯结构逻辑，不依赖文件系统。覆盖测试用 QPointer 断言旧指针已 delete。
 */
class tst_wallpapermode : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void addEntriesGroupsByKey();
    void addEntriesOverwritesSameKey();
    void clearEmptiesAll();
};

void tst_wallpapermode::addEntriesGroupsByKey()
{
    WallpaperModel model;
    QList<WallpaperEntry> groupA;
    groupA.append(WallpaperEntry());
    groupA.append(WallpaperEntry());
    QList<WallpaperEntry> groupB;
    groupB.append(WallpaperEntry());

    model.addEntries(QStringLiteral("file:///root/a"), groupA);
    model.addEntries(QStringLiteral("file:///root/b"), groupB);

    QCOMPARE(model.count(), 3);
    QCOMPARE(model.groupCount(), 2);
    QCOMPARE(model.keys().size(), 2);
    QCOMPARE(model.keys().at(0), QStringLiteral("file:///root/a"));
    QCOMPARE(model.keys().at(1), QStringLiteral("file:///root/b"));
    QCOMPARE(model.byKey(QStringLiteral("file:///root/a")).size(), 2);
    QCOMPARE(model.byKey(QStringLiteral("file:///root/b")).size(), 1);
    QCOMPARE(model.byKey(QStringLiteral("file:///root/nope")).size(), 0);
}

void tst_wallpapermode::addEntriesOverwritesSameKey()
{
    WallpaperModel model;
    QList<WallpaperEntry> first;
    first.append(WallpaperEntry());
    first.append(WallpaperEntry());
    model.addEntries(QStringLiteral("file:///root/a"), first);
    QCOMPARE(model.count(), 2);

    // 记录旧组指针，覆盖后应被 delete
    QList<WallpaperItem *> oldGroup = model.byKey(QStringLiteral("file:///root/a"));
    QPointer<WallpaperItem> survivor(oldGroup.at(0));

    QList<WallpaperEntry> second;
    second.append(WallpaperEntry());
    model.addEntries(QStringLiteral("file:///root/a"), second); // 同 key 覆盖

    QCOMPARE(model.count(), 1, "同 key 覆盖后总数应为 1");
    QCOMPARE(model.groupCount(), 1, "分组数不变");
    QVERIFY(survivor.isNull() || survivor->parent() != &model, "旧 WallpaperItem 应已被 delete");
}

void tst_wallpapermode::clearEmptiesAll()
{
    WallpaperModel model;
    QList<WallpaperEntry> entries;
    entries.append(WallpaperEntry());
    model.addEntries(QStringLiteral("file:///root/a"), entries);
    model.addEntries(QStringLiteral("file:///root/b"), entries);
    QCOMPARE(model.count(), 2);
    QCOMPARE(model.groupCount(), 2);

    model.clear();
    QCOMPARE(model.count(), 0);
    QCOMPARE(model.groupCount(), 0);
    QCOMPARE(model.keys().size(), 0);
}

QTEST_MAIN(tst_wallpapermode)
#include "tst_wallpapermode.moc"
```

- [ ] **Step 2: 注册到 `test/CMakeLists.txt`**

把第 42 行的 `find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)` 改为加 `Concurrent`：

```cmake
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test Concurrent)
```

并在文件末尾（`endif()` 前）追加：

```cmake
    # WallpaperModel 分组存储单测：编译模型 + 数据层 + 门面，链接 QtConcurrent。
    qt_add_executable(tst_wallpapermode tst_wallpapermode.cpp)
    target_sources(tst_wallpapermode PRIVATE
        ../plugin/wallpapermodel.cpp
        ../plugin/wallpaperitem.cpp
        ../plugin/wallpaperentry.cpp
    )
    target_include_directories(tst_wallpapermode PRIVATE ../plugin)
    target_link_libraries(tst_wallpapermode PRIVATE Qt6::Test Qt6::Core Qt6::Concurrent)
    add_test(NAME tst_wallpapermode COMMAND tst_wallpapermode)
    set_tests_properties(tst_wallpapermode PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
```

- [ ] **Step 3: 重新配置 + 构建 + 跑测试**

Run: `cmake --preset native && cmake --build build && ctest --test-dir build -R tst_wallpapermode --output-on-failure`
Expected: 3 个测试全部 PASS。

- [ ] **Step 4: Commit**

```bash
git add test/tst_wallpapermode.cpp test/CMakeLists.txt
git commit -m "test: 新增 WallpaperModel 分组覆盖与生命周期 C++ 单测
验证 addEntries 同 key 覆盖释放旧指针(QPointer)、keys/groupCount 正确、clear 清空。"
```

---

### Task 4: 修复 smoke 对已删除 ScanPathsPanel 的残留引用

**Files:**
- Modify: `test/tst_Smoke.qml`

**Interfaces:**
- Consumes: 无（纯测试文件修正）。

- [ ] **Step 1: 改引用**

把 `test/tst_Smoke.qml` 第 79-81 行的 `test_slideshowComponent_compiles` 整体替换为：

```qml
    function test_scanUrlsPanel_compiles() {
        verify(compiles("view/ScanUrlsPanel.qml"), "ScanUrlsPanel 应可编译");
    }
```

- [ ] **Step 2: 跑 smoke 测试**

Run: `cmake --build build && ctest --test-dir build -R tst_Smoke --output-on-failure`
Expected: 全部 PASS（含新增 `test_scanUrlsPanel_compiles`）。

- [ ] **Step 3: Commit**

```bash
git add test/tst_Smoke.qml
git commit -m "test: smoke 残留引用 ScanPathsPanel 改为 ScanUrlsPanel
ScanPathsPanel.qml 已删除,对应编译 smoke 用例引用已迁移的面板。"
```

---

### 收尾

- [ ] **Step: 全量测试**

Run: `ctest --test-dir build --output-on-failure`
Expected: 所有 C++ 与 QML 测试 PASS（`tst_Parser` 的 `test_scanUrls_addRemove` 若因 `addScanPath` 残留失败，属用户 ScanUrls 重构的预存问题，单独知会用户，不在本计划修复）。
