# 去掉 project.json 解析 + MVC 重构 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 HTMLWallpaper 插件不再解析 project.json,改为直接扫描子目录内 `*.html` 识别壁纸;同时按 MVC 重构(Model 自治扫描、Controller 变薄)并重命名类。

**Architecture:** 数据流保持 `Controller → Model → View`:Controller(WallpaperController)只管 scanPaths 管理、selectWallpaper 状态与信号转发;Model(WallpaperModel + WallpaperItem + WallpaperEntry)自治执行扫描(内部 QtConcurrent worker 枚举目录 → 构造 WallpaperEntry 目录探测值 → 填充自身);QML View 只读 Controller 暴露的 model。

**Tech Stack:** Qt6 (≥6.10)、KF6 (≥6.26)、QML、QAbstractListModel、QtConcurrent、qmltestrunner (Qt6 版)、QTest。

## Global Constraints

- 构建:`cmake --build build`(native preset 已配置);测试:`ctest --test-dir build --output-on-failure -R <name>`
- QML 测试环境:`QT_QPA_PLATFORM=offscreen`(ctest 已设置);qmltestrunner 必须是 Qt6 版(见 test/CMakeLists.txt)
- **类名映射(硬性)**:`HTMLBackend`→`WallpaperController`、`WallpaperListModel`→`WallpaperModel`、`WallpaperProject`→`WallpaperEntry`、`WallpaperProjectJson` 命名空间→`WallpaperPath`、`WallpaperItem` 保留
- **QML 类型名**:注册为 `WallpaperController`(config.qml 与测试全部改用该名)
- 源码注释保持项目既有中文注释风格;所有文件保留 SPDX 头
- 目录探测入口顺序:`index.html` → `index.htm` → `main.html` → `main.htm` → `start.html` → 字典序第一个 `*.html`(QDir::Name 排序)
- preview 探测顺序:`preview.png` / `preview.jpg` / `preview.jpeg` / `preview.gif` / `preview.webp` / `default.png` / `thumbnail.png`
- 收录规则:扫描根下**直接子目录**含 `*.html`/`*.htm` 即收录;无 html 的子目录跳过
- 测试夹具期望:aurora / matrix / missing-entry / neon / nova / offline 共 **6 个**收录;fetch / paramfallback(无 html)**不收录**

---

### Task 1: 核心数据流重构 — WallpaperEntry + 删属性系统 + 精简消费层

**Files:**
- Rename: `plugin/wallpaperproject.h` → `plugin/wallpaperentry.h`
- Rename: `plugin/wallpaperproject.cpp` → `plugin/wallpaperentry.cpp`
- Delete: `plugin/wallpaperproperty.h`、`plugin/wallpaperproperty.cpp`、`plugin/wallpaperpropertyitem.h`、`plugin/wallpaperpropertyitem.cpp`、`plugin/wallpaperpropertymodel.h`、`plugin/wallpaperpropertymodel.cpp`
- Modify: `plugin/wallpaperitem.h`、`plugin/wallpaperitem.cpp`、`plugin/wallpaperlistmodel.h`、`plugin/wallpaperlistmodel.cpp`、`plugin/htmlbackend.cpp`、`plugin/CMakeLists.txt`、`test/CMakeLists.txt`
- Test: `test/tst_wallpaperproject.cpp`(重写)

**Interfaces:**
- Produces(后续任务依赖):
  - `WallpaperEntry`(值类型):`WallpaperEntry(const QString &dirUrl)`;`bool isValid() const`;`QString name()/title()/path()/file()/source()/display()/preview() const`
  - 命名空间 `WallpaperPath`:`QString toUrl(const QString &path)`、`QString pathJoin(const QString &a, const QString &b)`
  - `struct ScanResult { QList<WallpaperEntry> projects; QList<QPair<QString,QString>> failures; }`
- Consumes: 无(本任务从零重构数据层)

- [ ] **Step 1: git mv 重命名数据层文件**

```bash
git mv plugin/wallpaperproject.h plugin/wallpaperentry.h
git mv plugin/wallpaperproject.cpp plugin/wallpaperentry.cpp
git rm plugin/wallpaperproperty.h plugin/wallpaperproperty.cpp \
       plugin/wallpaperpropertyitem.h plugin/wallpaperpropertyitem.cpp \
       plugin/wallpaperpropertymodel.h plugin/wallpaperpropertymodel.cpp
```

- [ ] **Step 2: 重写 `plugin/wallpaperentry.h`** —— 替换为目录探测值类型

关键内容(类名 `WallpaperEntry`,命名空间 `WallpaperPath`):

```cpp
#pragma once

#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>

// 通用路径工具(scanPaths 归一化 + 目录拼接),被 Controller 与数据层复用。
namespace WallpaperPath
{
QString toUrl(const QString &path);
QString pathJoin(const QString &a, const QString &b);
} // namespace WallpaperPath

class WallpaperEntry;

struct ScanResult {
    QList<WallpaperEntry> projects; // 解析结果
    QList<QPair<QString, QString>> failures; // (path, error)
};

/**
 * 单个 HTML 壁纸的元数据(值类型,目录探测)。
 * 无 QObject、可拷贝/移动,后台线程可安全构造。默认构造 = 无效标记;
 * 显式构造时枚举 <dir>/ 下的 *.html 选入口、探测预览图,目录缺失或无 html
 * → 保持无效。title 即目录名;source/display 为 file/title 兼容别名。
 */
class WallpaperEntry
{
public:
    WallpaperEntry() = default;
    explicit WallpaperEntry(const QString &dirUrl);
    bool isValid() const;

    QString name() const;
    QString title() const;
    QString path() const;
    QString file() const;
    QString source() const;
    QString display() const;
    QString preview() const;

private:
    QString m_name;
    QString m_path;
    QString m_file;
    QString m_preview;
    bool m_valid = false;
};
```

- [ ] **Step 3: 重写 `plugin/wallpaperentry.cpp`**

核心探测逻辑:

```cpp
#include "wallpaperentry.h"

#include <QDir>
#include <QUrl>

namespace
{
QString basename(const QString &url)
{
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s.mid(s.lastIndexOf(QLatin1Char('/')) + 1);
}

QString findPreview(const QString &dirUrl)
{
    static const QStringList candidates = {
        QStringLiteral("preview.png"), QStringLiteral("preview.jpg"),
        QStringLiteral("preview.jpeg"), QStringLiteral("preview.gif"),
        QStringLiteral("preview.webp"), QStringLiteral("default.png"),
        QStringLiteral("thumbnail.png"),
    };
    const QString dir = QUrl(dirUrl).toLocalFile();
    for (const QString &c : candidates) {
        if (QFile::exists(dir + QLatin1Char('/') + c)) {
            return WallpaperPath::pathJoin(dirUrl, c);
        }
    }
    return {};
}

// 入口选择:常用名优先,否则字典序第一个 *.html。
QString findEntry(const QString &dirUrl)
{
    const QString dir = QUrl(dirUrl).toLocalFile();
    static const QStringList common = {
        QStringLiteral("index.html"), QStringLiteral("index.htm"),
        QStringLiteral("main.html"), QStringLiteral("main.htm"),
        QStringLiteral("start.html"),
    };
    for (const QString &c : common) {
        if (QFile::exists(dir + QLatin1Char('/') + c)) {
            return WallpaperPath::pathJoin(dirUrl, c);
        }
    }
    const QStringList html = QDir(dir).entryList(
        {QStringLiteral("*.html"), QStringLiteral("*.htm")}, QDir::Files, QDir::Name);
    if (!html.isEmpty()) {
        return WallpaperPath::pathJoin(dirUrl, html.first());
    }
    return {};
}
} // namespace

namespace WallpaperPath
{
QString toUrl(const QString &path)
{
    return path.contains(QLatin1String("://")) ? path : QStringLiteral("file://") + path;
}

QString pathJoin(const QString &a, const QString &b)
{
    QString sa = a;
    while (sa.endsWith(QLatin1Char('/'))) {
        sa.chop(1);
    }
    QString sb = b;
    while (sb.startsWith(QLatin1Char('/'))) {
        sb.remove(0, 1);
    }
    return sa + QLatin1Char('/') + sb;
}
} // namespace WallpaperPath

WallpaperEntry::WallpaperEntry(const QString &dirUrl)
{
    const QString url = WallpaperPath::toUrl(dirUrl);
    QDir dir(QUrl(url).toLocalFile());
    if (!dir.exists()) {
        return;
    }
    const QString entry = findEntry(url);
    if (entry.isEmpty()) {
        return; // 无 *.html → 不收录
    }
    m_name = basename(url);
    m_path = url;
    m_file = entry;
    m_preview = findPreview(url);
    m_valid = true;
}

bool WallpaperEntry::isValid() const { return m_valid; }
QString WallpaperEntry::name() const { return m_name; }
QString WallpaperEntry::title() const { return m_name; }
QString WallpaperEntry::path() const { return m_path; }
QString WallpaperEntry::file() const { return m_file; }
QString WallpaperEntry::source() const { return m_file; }
QString WallpaperEntry::display() const { return m_name; }
QString WallpaperEntry::preview() const { return m_preview; }
```

注意:上面用到了 `QFile`,需 `#include <QFile>`。`.cpp` 顶部 SPDX 头保留。

- [ ] **Step 4: 精简 `plugin/wallpaperitem.h`** —— 7 个 Q_PROPERTY,删除属性模型成员

完整替换为:

```cpp
#pragma once

#include <QObject>

#include "wallpaperentry.h"

/**
 * @brief 单个壁纸元数据的 QObject 门面(接口层,WallpaperModel::get(i)
 * 的返回值,主线程构造)。数据成员是 WallpaperEntry 值类型(后台线程目录
 * 探测的产物),全部 Q_PROPERTY 委托到它。source/display 是 file/title
 * 的兼容别名(对齐 slideFilterModel 与 ThumbnailsView 的 get(i).source)。
 */
class WallpaperItem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString file READ file CONSTANT)
    Q_PROPERTY(QString source READ source CONSTANT)
    Q_PROPERTY(QString display READ display CONSTANT)
    Q_PROPERTY(QString preview READ preview CONSTANT)

public:
    explicit WallpaperItem(const WallpaperEntry &entry, QObject *parent = nullptr);
    explicit WallpaperItem(const WallpaperItem &item, QObject *parent = nullptr);
    WallpaperItem &operator=(const WallpaperItem &item);

    QString name() const { return m_entry.name(); }
    QString title() const { return m_entry.title(); }
    QString path() const { return m_entry.path(); }
    QString file() const { return m_entry.file(); }
    QString source() const { return m_entry.source(); }
    QString display() const { return m_entry.display(); }
    QString preview() const { return m_entry.preview(); }

private:
    WallpaperEntry m_entry; // 数据层(唯一数据来源)
};
```

并同步更新 include:删除 `#include "wallpaperpropertymodel.h"`(原文件顶部两个 include 仅保留 `wallpaperentry.h`)。

- [ ] **Step 5: 精简 `plugin/wallpaperitem.cpp`**

```cpp
#include "wallpaperitem.h"

WallpaperItem::WallpaperItem(const WallpaperEntry &entry, QObject *parent)
    : QObject(parent)
    , m_entry(entry)
{
}

WallpaperItem::WallpaperItem(const WallpaperItem &item, QObject *parent)
    : WallpaperItem(item.m_entry, parent)
{
}

WallpaperItem &WallpaperItem::operator=(const WallpaperItem &item)
{
    if (this != &item) {
        m_entry = item.m_entry;
    }
    return *this;
}
```

- [ ] **Step 6: 精简 `plugin/wallpaperlistmodel.h` / `.cpp`**

- Roles 减为 5 个:`NameRole / TitleRole / PathRole / PreviewRole / FileRole`(删其余 12 个)
- `roleNames()` 只返回 `name/title/path/preview/file`
- `data()` 的 switch 只保留 5 个 case(委托到 item 的同名 getter)
- `setEntries(const QList<WallpaperEntry> &projects)`;`m_items` 内 `WallpaperItem(projects.at(i), this)`;`m_indexByKey.insert(projects.at(i).source(), i)`
- `setEntries` 尾部 dataChanged 的 roles 列表同步减为 5 个
- include 从 `wallpaperproject.h` 改为 `wallpaperentry.h`

- [ ] **Step 7: 简化 `plugin/htmlbackend.cpp` worker**

```cpp
namespace
{
// 后台扫描 worker:只读 QDir + WallpaperEntry 构造,不触碰 QObject。
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
        const QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &sub : subdirs) {
            const QString dirUrl = WallpaperPath::pathJoin(baseUrl, sub);
            WallpaperEntry entry(dirUrl);
            if (entry.isValid()) {
                result.projects.append(entry);
            }
        }
    }
    return result;
}
} // namespace
```

同时:删除 `htmlbackend.cpp` 顶部 `using namespace WallpaperProjectJson;` 与 `#include "wallpaperproperty.h"` 相关;`setScanPaths` 里 `WallpaperProjectJson::toUrl` → `WallpaperPath::toUrl`;`addScanPath`/`removeScanPath` 同样替换。`htmlbackend.h` 暂不改类名(留给 Task 4),但 include 改为 `wallpaperentry.h`。

- [ ] **Step 8: 更新构建** —— `plugin/CMakeLists.txt` 与 `test/CMakeLists.txt`

`plugin/CMakeLists.txt` target_sources 改为:

```cmake
target_sources(plasma_wallpaper_htmlwallpaperplugin PRIVATE
    htmlbackend.cpp
    wallpaperitem.cpp
    wallpaperlistmodel.cpp
    wallpaperentry.cpp
)
```

`test/CMakeLists.txt` 的 `tst_wallpaperproject` target_sources 改为只编 `../plugin/wallpaperentry.cpp`,并删除对 `wallpaperproperty.cpp` 等 3 个文件的引用(该测试已不 include 属性头)。

- [ ] **Step 9: 重写 `test/tst_wallpaperproject.cpp`** —— 目录探测单测

```cpp
#include <QtTest>

#include "wallpaperentry.h"

#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QUrl>

class tst_WallpaperEntry : public QObject
{
    Q_OBJECT
private:
    static QString fixtureUrl(const QString &name);
    static QString tmpUrl(QTemporaryDir &dir, const QStringList &files);
private Q_SLOTS:
    void entryDetectsIndexHtml();
    void entryPrefersIndexOverOthers();
    void entryFallsBackToFirstHtml();
    void entryInvalidWithoutHtml();
    void entryProbesPreview();
    void titleEqualsName();
    void toUrlAndPathJoin();
};

QString tst_WallpaperEntry::fixtureUrl(const QString &name)
{
    return QUrl::fromLocalFile(QFileInfo(QStringLiteral("data/wallpapers/") + name).absoluteFilePath()).toString();
}

QString tst_WallpaperEntry::tmpUrl(QTemporaryDir &dir, const QStringList &files)
{
    for (const QString &f : files) {
        QFile file(dir.filePath(f));
        file.open(QIODevice::WriteOnly);
        file.close();
    }
    return QUrl::fromLocalFile(dir.path()).toString();
}

void tst_WallpaperEntry::entryDetectsIndexHtml()
{
    WallpaperEntry p(fixtureUrl(QStringLiteral("aurora")));
    QVERIFY(p.isValid());
    QCOMPARE(p.name(), QStringLiteral("aurora"));
    QVERIFY(p.file().endsWith(QStringLiteral("/data/wallpapers/aurora/index.html")));
    QCOMPARE(p.source(), p.file());
    QCOMPARE(p.display(), QStringLiteral("aurora"));
}

void tst_WallpaperEntry::entryPrefersIndexOverOthers()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    WallpaperEntry p(tmpUrl(dir, {QStringLiteral("zzz.html"), QStringLiteral("index.html")}));
    QVERIFY(p.isValid());
    QVERIFY(p.file().endsWith(QStringLiteral("/index.html")));
}

void tst_WallpaperEntry::entryFallsBackToFirstHtml()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    WallpaperEntry p(tmpUrl(dir, {QStringLiteral("zzz.html"), QStringLiteral("aaa.html")}));
    QVERIFY(p.isValid());
    QVERIFY(p.file().endsWith(QStringLiteral("/aaa.html"))); // 字典序第一个
}

void tst_WallpaperEntry::entryInvalidWithoutHtml()
{
    WallpaperEntry fetch(fixtureUrl(QStringLiteral("fetch"))); // 目录无 html
    QVERIFY(!fetch.isValid());

    WallpaperEntry missing(fixtureUrl(QStringLiteral("does-not-exist")));
    QVERIFY(!missing.isValid());
}

void tst_WallpaperEntry::entryProbesPreview()
{
    WallpaperEntry nova(fixtureUrl(QStringLiteral("nova")));
    QVERIFY(nova.isValid());
    QVERIFY(nova.preview().endsWith(QStringLiteral("/data/wallpapers/nova/preview.jpg")));

    WallpaperEntry aurora(fixtureUrl(QStringLiteral("aurora"))); // 无 preview 文件
    QVERIFY(aurora.isValid());
    QVERIFY(aurora.preview().isEmpty());
}

void tst_WallpaperEntry::titleEqualsName()
{
    WallpaperEntry matrix(fixtureUrl(QStringLiteral("matrix")));
    QVERIFY(matrix.isValid());
    QCOMPARE(matrix.title(), QStringLiteral("matrix"));
    QVERIFY(matrix.file().endsWith(QStringLiteral("/data/wallpapers/matrix/main.html")));
}

void tst_WallpaperEntry::toUrlAndPathJoin()
{
    QCOMPARE(WallpaperPath::toUrl(QStringLiteral("/a/b")), QStringLiteral("file:///a/b"));
    QCOMPARE(WallpaperPath::toUrl(QStringLiteral("https://x/")), QStringLiteral("https://x/"));
    QCOMPARE(WallpaperPath::pathJoin(QStringLiteral("file:///a/"), QStringLiteral("/b")), QStringLiteral("file:///a/b"));
    QCOMPARE(WallpaperPath::pathJoin(QStringLiteral("file:///a"), QStringLiteral("b")), QStringLiteral("file:///a/b"));
}

QTEST_MAIN(tst_WallpaperEntry)
#include "tst_wallpaperproject.moc"
```

注意:末尾 `#include` 保留 `.moc` 文件名 `tst_wallpaperproject.moc`(AUTOMOC 按 .cpp 文件名生成);若 rename 测试文件则同步。保持测试文件名为 `tst_wallpaperproject.cpp`(add_test NAME 不变)。

- [ ] **Step 10: 编译并运行 C++ 测试**

```bash
cmake --build build   # 需重新配置以拾取 CMakeLists 变更:cmake --preset native
ctest --test-dir build --output-on-failure -R tst_wallpaperproject
```

Expected: build 成功;tst_wallpaperproject 6 个用例 PASS。

- [ ] **Step 11: 提交**

```bash
git add -A plugin test docs
git commit -m "refactor: 数据层改为目录探测(WallpaperEntry),删除属性系统

- WallpaperProject → WallpaperEntry:构造改为枚举子目录 *.html 选入口
- 删除 WallpaperProperty/PropertyModel/PropertyItem 属性系统
- WallpaperItem/WallpaperListModel 精简字段,worker 去掉 type 过滤

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: WallpaperListModel → WallpaperModel(自治扫描)

**Files:**
- Rename: `plugin/wallpaperlistmodel.h` → `plugin/wallpapermodel.h`、`plugin/wallpaperlistmodel.cpp` → `plugin/wallpapermodel.cpp`
- Modify: `plugin/wallpaperitem.h`(include 更新)、`plugin/htmlbackend.h`(wallpapers 类型 + include)、`plugin/htmlbackend.cpp`(删 worker,scan 转发)、`plugin/CMakeLists.txt`

**Interfaces:**
- Produces: `WallpaperModel` 新增 `Q_INVOKABLE void scan(const QStringList &roots)`、`Q_PROPERTY(bool scanInProgress READ scanInProgress NOTIFY scanInProgressChanged)`、信号 `scanFinished()` / `scanFailed(QString path, QString error)` / `scanInProgressChanged()`
- Consumes: `WallpaperEntry`、`ScanResult`、`WallpaperPath`(Task 1)

- [ ] **Step 1: git mv 并更新 include**

```bash
git mv plugin/wallpaperlistmodel.h plugin/wallpapermodel.h
git mv plugin/wallpaperlistmodel.cpp plugin/wallpapermodel.cpp
```

`wallpaperitem.h`、`wallpaperitem.cpp`、`htmlbackend.h`、`htmlbackend.cpp`、`plugin/CMakeLists.txt` 中的 `wallpaperlistmodel.h` include 与 `WallpaperListModel` 引用全部改 `wallpapermodel.h` / `WallpaperModel`。

- [ ] **Step 2: `wallpapermodel.h` 增加自治扫描接口**

```cpp
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

    void setEntries(const QList<WallpaperEntry> &projects);
    void clear();
    Q_INVOKABLE int indexOf(const QString &source) const;
    Q_INVOKABLE WallpaperItem *get(int i);
    Q_INVOKABLE WallpaperItem *byKey(const QString &key);

    // —— 自治扫描 ——
    Q_INVOKABLE void scan(const QStringList &roots);

Q_SIGNALS:
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    void setScanInProgress(bool inProgress);

    QList<WallpaperItem> m_items;
    QHash<QString, int> m_indexByKey;
    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
```

头部 include:`#include <QFutureWatcher>` 前置声明 `template<typename T> class QFutureWatcher;` + `#include "wallpaperentry.h"`;`wallpaperitem.h` include 保留。`.cpp` 增加 `#include <QtConcurrent>`。

- [ ] **Step 3: `wallpapermodel.cpp` 实现自治扫描 + 迁移 worker**

把 Task 1 中 `htmlbackend.cpp` 的 `scanWallpapers` worker 原样移入本文件(匿名命名空间),并新增:

```cpp
bool WallpaperModel::scanInProgress() const { return m_scanning; }

void WallpaperModel::setScanInProgress(bool inProgress)
{
    if (m_scanning == inProgress) {
        return;
    }
    m_scanning = inProgress;
    Q_EMIT scanInProgressChanged();
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
            setEntries(result.projects);
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWallpapers, roots));
}
```

- [ ] **Step 4: `htmlbackend.cpp` 删除 worker,scan() 转发 + 转发 Model 信号**

删除匿名命名空间 `scanWallpapers`、`<QtConcurrent>` / `<QFutureWatcher>` 相关代码、`setScanInProgress` 调用、`m_scanning` / `m_watcher` 成员。`scan()` 改为一行转发,构造函数 connect Model 信号(否则扫描后 `scanFinished` 信号断链,tst_Parser 收不到):

```cpp
HTMLBackend::HTMLBackend(QObject *parent)
    : QObject(parent)
    , m_wallpapers(new WallpaperModel(this))
{
    connect(m_wallpapers, &WallpaperModel::scanFinished, this, &HTMLBackend::scanFinished);
    connect(m_wallpapers, &WallpaperModel::scanFailed, this, &HTMLBackend::scanFailed);
    connect(m_wallpapers, &WallpaperModel::scanInProgressChanged, this, &HTMLBackend::scanInProgressChanged);
}

void HTMLBackend::scan()
{
    m_wallpapers->scan(m_scanPaths);
}
```

`htmlbackend.h`:删除 `#include "wallpaperproject.h"`、`QFutureWatcher` 前置声明、`setScanInProgress` 声明、`m_watcher` / `m_scanning` 成员;`wallpapers()` 返回类型改 `WallpaperModel *`;`scanInProgress()` 改为委托 Model(保留该属性,`requireWebType` / `nonHtmlTypes` 留到 Task 3 一并删除):

```cpp
bool HTMLBackend::scanInProgress() const { return m_wallpapers->scanInProgress(); }
```

同时把 `htmlbackend.cpp` 顶部 `using namespace WallpaperProjectJson;`(若残留)改 `WallpaperPath`。

- [ ] **Step 5: 更新 `plugin/CMakeLists.txt`**

target_sources 中 `wallpaperlistmodel.cpp` → `wallpapermodel.cpp`。

- [ ] **Step 6: 编译验证**

```bash
cmake --preset native && cmake --build build
```

Expected: 构建成功(注意此时 `HTMLBackend::setScanInProgress` 等引用已清;若 `htmlbackend.h` 仍有 scanInProgress 属性依赖,可在 Task 4 一并收敛,本任务保持最小编译通过)。

- [ ] **Step 7: 提交**

```bash
git add -A plugin
git commit -m "refactor: WallpaperListModel → WallpaperModel,自治扫描

- 扫描 worker 从 Controller 移入 Model(WallpaperModel::scan)
- Model 暴露 scanInProgress/scanFinished/scanFailed
- Controller::scan 简化为一行转发

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: HTMLBackend → WallpaperController(变薄 + QML 类型名)

**Files:**
- Rename: `plugin/htmlbackend.h` → `plugin/wallpapercontroller.h`、`plugin/htmlbackend.cpp` → `plugin/wallpapercontroller.cpp`
- Modify: `plugin/CMakeLists.txt`、`package/contents/ui/config.qml`、`test/tst_Parser.qml`、`test/tst_WallpaperListModel.qml`、`test/tst_Smoke.qml`

**Interfaces:**
- Produces: QML 类型 `WallpaperController`(QML_NAMED_ELEMENT),属性 `selectWallpaper` / `scanPaths` / `wallpapers`(WallpaperModel*),方法 `scan()` / `addScanPath()` / `removeScanPath()`,信号 `selectWallpaperChanged` / `scanPathsChanged` / `scanFinished` / `scanFailed` / `scanInProgressChanged`
- Consumes: `WallpaperModel`(Task 2)

- [ ] **Step 1: git mv 并全局替换标识符**

```bash
git mv plugin/htmlbackend.h plugin/wallpapercontroller.h
git mv plugin/htmlbackend.cpp plugin/wallpapercontroller.cpp
```

在 `plugin/CMakeLists.txt`、`package/contents/ui/config.qml`、`test/tst_Parser.qml`、`test/tst_WallpaperListModel.qml`、`test/tst_Smoke.qml` 中,把 `htmlbackend.h` include、`HTMLBackend` 标识符、`htmlbackend.cpp` 源文件名全部替换为 `wallpapercontroller.h` / `WallpaperController` / `wallpapercontroller.cpp`。QML 测试中的实例化字符串:

```qml
parser = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; WallpaperController {}", testCase);
```

- [ ] **Step 2: `wallpapercontroller.h` 变薄 + 转发信号**

删除:头注释中的 project.json 目录约定、`requireWebType` / `nonHtmlTypes` 属性(含 getter/setter/信号/成员/默认值)、`m_scanning` / `m_watcher` / `setScanInProgress`。新增对 Model 信号的转发:

```cpp
class WallpaperController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(WallpaperController)

    Q_PROPERTY(QString selectWallpaper READ selectWallpaper WRITE setSelectWallpaper NOTIFY selectWallpaperChanged)
    Q_PROPERTY(QStringList scanPaths READ scanPaths WRITE setScanPaths NOTIFY scanPathsChanged)
    Q_PROPERTY(WallpaperModel *wallpapers READ wallpapers CONSTANT)

public:
    explicit WallpaperController(QObject *parent = nullptr);
    QString selectWallpaper() const;
    void setSelectWallpaper(const QString &wallpaper);
    QStringList scanPaths() const;
    void setScanPaths(const QStringList &paths);
    WallpaperModel *wallpapers() const;

    Q_INVOKABLE void scan();
    Q_INVOKABLE bool addScanPath(const QString &path);
    Q_INVOKABLE void removeScanPath(const QString &path);

Q_SIGNALS:
    void selectWallpaperChanged();
    void scanPathsChanged();
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    QString m_selectWallpaper;
    QStringList m_scanPaths;
    WallpaperModel *m_wallpapers = nullptr;
};
```

头部 include:`wallpapermodel.h`、`wallpaperentry.h`(WallpaperPath)。

- [ ] **Step 3: `wallpapercontroller.cpp` 构造时连接 Model 信号转发**

```cpp
#include "wallpapercontroller.h"
#include "wallpapermodel.h"

WallpaperController::WallpaperController(QObject *parent)
    : QObject(parent)
    , m_wallpapers(new WallpaperModel(this))
{
    connect(m_wallpapers, &WallpaperModel::scanFinished, this, &WallpaperController::scanFinished);
    connect(m_wallpapers, &WallpaperModel::scanFailed, this, &WallpaperController::scanFailed);
    connect(m_wallpapers, &WallpaperModel::scanInProgressChanged, this, &WallpaperController::scanInProgressChanged);
}
```

`setScanPaths` / `addScanPath` / `removeScanPath` 里 `WallpaperPath::toUrl` 归一化保留;`scan()` 保持 `m_wallpapers->scan(m_scanPaths)`。文件顶部保留 SPDX 头与 `#include <QUrl>` 等。所有 setter 的 `Q_EMIT` 保留。

- [ ] **Step 4: 编译验证**

```bash
cmake --preset native && cmake --build build
```

Expected: 构建成功;QML 测试此时运行会因断言旧期望失败(Task 6 收敛),但类型解析不再报 `HTMLBackend not found`。

- [ ] **Step 5: 提交**

```bash
git add -A plugin package test
git commit -m "refactor: HTMLBackend → WallpaperController,变薄为纯 Controller

- 删除 requireWebType/nonHtmlTypes 过滤与内部扫描状态
- 转发 WallpaperModel 的 scanFinished/scanFailed/scanInProgressChanged
- QML 类型名改为 WallpaperController

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: QML 层清理(main.qml 去参数 / main.xml / PropertyPanel / 注释)

**Files:**
- Modify: `package/contents/ui/main.qml`、`package/contents/config/main.xml`、`package/contents/ui/config.qml`、`package/contents/ui/view/ScanPathsPanel.qml`
- Delete: `package/contents/ui/view/PropertyPanel.qml`
- Test: `test/tst_MainCompile.qml`、`test/tst_Smoke.qml`

- [ ] **Step 1: 删除 PropertyPanel.qml**

```bash
git rm package/contents/ui/view/PropertyPanel.qml
```

`test/tst_Smoke.qml` 删除 `test_propertyPanel_compiles` 函数(引用已删组件)。

- [ ] **Step 2: `main.qml` 删除参数注入**

删除:`_propertiesJson` / `_injectedJson` 属性、`_pageUrl()` / `_injectProperties()` 函数、`onValueChanged` 中 `WallpaperProperties` 分支、`Component.onCompleted` 中 `_propertiesJson` 赋值。`_applyUrl()` 简化为:

```qml
function _applyUrl(): void {
    webView.url = wallpaper._displayPage;
}
```

`onValueChanged` 保留 `SelectWallpaper` 分支即可。更新文件头注释(去掉"混合注入"描述)。

- [ ] **Step 3: `main.xml` 删除配置项**

删除 `WallpaperProperties` 的 `<entry>` 块(保留 SelectWallpaper / ZoomFactor / InsecureHTTPS / ScanPaths)。

- [ ] **Step 4: 更新 `config.qml` 注释**

删除第 35-37 行注释中"扫描扫描目录下的 project.json"表述,改为"扫描扫描目录下含 *.html 的壁纸子目录";`HTMLBackend` → `WallpaperController` 已在 Task 3 完成,本步只清注释。

- [ ] **Step 5: 更新 `ScanPathsPanel.qml` 注释**

删除第 30-35 行注释中关于 `WallpaperItem::properties` / `WallpaperPropertyModel` / `wallpaperProperties` 的表述,改为说明数据源为 `htmlWallpaper.wallpapers`(WallpaperModel)。

- [ ] **Step 6: `tst_MainCompile.qml` 删除 query 拼接测试**

删除 `test_pageUrl_mixed`(测 `_pageUrl`,已删);保留 `test_main_compiles`。

- [ ] **Step 7: 编译 + 相关测试**

```bash
cmake --build build
ctest --test-dir build --output-on-failure -R 'tst_MainCompile|tst_Smoke'
```

Expected: 两个 QML 测试编译通过、不依赖已删组件的用例 PASS。

- [ ] **Step 8: 提交**

```bash
git add -A package test
git commit -m "refactor: 清理 QML 层,删除 WallpaperProperties 注入与 PropertyPanel

- main.qml 去掉参数注入,只渲染 SelectWallpaper 入口
- main.xml 删除 WallpaperProperties 配置项
- 删除 view/PropertyPanel.qml

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: dev 调试程序清理

**Files:**
- Modify: `dev/src/DevConfigMap.cpp`、`dev/qml/DevShell.qml`、`dev/src/main.cpp`

- [ ] **Step 1: `dev/src/DevConfigMap.cpp` 删除属性键**

删除 `setProperty("WallpaperProperties", QStringLiteral("{}"));` 行。

- [ ] **Step 2: `dev/qml/DevShell.qml` 删除注入与注释**

删除 setSource 初始属性中的 `cfg_WallpaperProperties: "{}"`,并更新第 22-23 行注释("调整参数 → 同步给预览面板"改为"选中壁纸 → 同步给预览面板")。

- [ ] **Step 3: `dev/src/main.cpp` 更新注释**

更新第 34-36 行注释:去掉"HTMLBackend 内部用 QFile 直接读 project.json",改为"WallpaperController 后台扫描子目录 *.html,无需旧 QML 解析"。

- [ ] **Step 4: 编译验证**

```bash
cmake --build build
```

Expected: 构建成功(dev 目标一并编译)。

- [ ] **Step 5: 提交**

```bash
git add -A dev
git commit -m "chore: 清理 dev 调试程序的 WallpaperProperties 残留

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: QML 测试期望收敛 + 全量验证

**Files:**
- Modify: `test/tst_Parser.qml`、`test/tst_WallpaperListModel.qml`
- Test: 全量 `ctest`

- [ ] **Step 1: `test/tst_Parser.qml` 更新期望**

- 头部注释:收录集改为 aurora / matrix / missing-entry / neon / nova / offline 共 6 个;fetch / paramfallback(无 html)不收录
- `test_scanCollectsWebWallpapers` 中:
  - 删除对 `aurora.workshopid / tags / contentrating / ratingsex / ratingviolence / version / workshopurl / supportsAudio / monetization` 的断言(字段已删)
  - 删除 `matrix.properties` 相关断言、`matrix.supportsaudioprocessing`
  - `aurora.title` 断言改为 `"aurora"`(title = name);`aurora.display` 改为 `"aurora"`
  - `nova.title` 改为 `"nova"`;`missing.title` 改为 `"missing-entry"`
  - 新增收录断言:`neon` 与 `offline` 存在,`fetch` 与 `paramfallback` 不存在
  - `matrix.file` 断言保留(`main.html`);`missing.file` 保留(`real.html`);`nova.preview` 保留(`preview.jpg`)
  - 删除 `test_scanPaths_addRemove` 中任何对已删属性的引用(若无则保留)

- [ ] **Step 2: `test/tst_WallpaperListModel.qml` 更新期望**

同样:删除 `workshopid / tags / contentrating / version / supportsAudio` 断言;`aurora.title` → `"aurora"`;删除 `matrix.properties` 与 `supportsaudioprocessing` 断言;`test_fileFallbackWhenMissing` 的 `missing.title` → `"missing-entry"`;`scanWallpapers()` 注释更新收录集。

- [ ] **Step 3: 运行全量测试**

```bash
cmake --preset native && cmake --build build
ctest --test-dir build --output-on-failure
```

Expected: 全部测试 PASS(`tst_wallpaperproject`、`tst_Parser`、`tst_WallpaperListModel`、`tst_Smoke`、`tst_MainCompile`、`tst_ThumbnailsHighlight`)。

- [ ] **Step 4: 复查删除的 API 无残留引用**

```bash
grep -rn "HTMLBackend\|WallpaperProperty\|WallpaperListModel\|WallpaperProject\|project.json\|requireWebType\|nonHtmlTypes\|WallpaperProperties\|supportsAudio\|workshopid\|monetization\|contentrating" plugin/ package/ dev/ test/ --include="*.h" --include="*.cpp" --include="*.qml" --include="*.xml" --include="CMakeLists.txt" | grep -v build/ || echo "无残留"
```

Expected: 除 README/历史或有意保留的注释外,无对已删 API 的引用。

- [ ] **Step 5: 提交**

```bash
git add -A test
git commit -m "test: 更新 QML 测试期望为目录探测收录集(6 个壁纸)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## 验证清单(全部完成后)

1. `cmake --preset native && cmake --build build` 成功
2. `ctest --test-dir build --output-on-failure` 全 PASS
3. `grep -rn "project.json\|WallpaperProperty\|HTMLBackend\|WallpaperProject\|WallpaperListModel" plugin/ package/ dev/ test/` 无已删 API 残留
4. 手动:`htmlwallpaper-config-dev`(dev 程序)打开配置面板,扫描 `test/data/wallpapers` 显示 6 个壁纸,点选应用正常
