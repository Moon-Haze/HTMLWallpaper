/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QDir>
#include <QFile>
#include <QPointer>
#include <QTemporaryDir>
#include <QtTest>

#include "allwallpapersmodel.h"
#include "wallpaperitem.h"
#include "wallpapermodel.h"
#include <QSignalSpy>

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
    void selectedIndexDefaultIsMinusOne();
    void selectedIndexSetAndEmit();
    void selectedIndexOutOfRangeIgnored();
    void selectedIndexResetsOnAddEntries();
    void selectedIndexResetsOnClear();
    void mergeAggregatesAcrossSources();
    void mergeResetsOnSourceReset();
    void mergeSelectedIndexForwardsToSource();
    void mergeSelectedIndexSingleSelectClearsOthers();
    void mergeSelectedIndexGetterAggregates();
    void mergeSelectedIndexMinusOneClearsAll();
    void mergeSetSourcesRemountRecomputes();
    void mergeSelectedIndexForwardsSourceSignal();
    void mergeGetCrossesSources();
    void mergeIndexOfCrossesSources();
    void mergeRejectsAddEntriesAndClear();
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

void tst_wallpapermodel::selectedIndexDefaultIsMinusOne()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QCOMPARE(model.selectedIndex(), -1);
}

void tst_wallpapermodel::selectedIndexSetAndEmit()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    model.addEntries({WallpaperEntry(), WallpaperEntry()});
    QSignalSpy spy(&model, &WallpaperModel::selectedIndexChanged);

    model.setSelectedIndex(0);
    QCOMPARE(model.selectedIndex(), 0);
    QCOMPARE(spy.count(), 1);

    // 同值幂等：不重复 emit
    model.setSelectedIndex(0);
    QCOMPARE(spy.count(), 1);

    model.setSelectedIndex(-1);
    QCOMPARE(model.selectedIndex(), -1);
    QCOMPARE(spy.count(), 2);
}

void tst_wallpapermodel::selectedIndexOutOfRangeIgnored()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    model.addEntries({WallpaperEntry(), WallpaperEntry()});
    QSignalSpy spy(&model, &WallpaperModel::selectedIndexChanged);

    // 越上界（== count）与越下界（< -1）均忽略，值不变、无 emit
    model.setSelectedIndex(2);
    model.setSelectedIndex(-2);
    QCOMPARE(model.selectedIndex(), -1);
    QCOMPARE(spy.count(), 0);
}

void tst_wallpapermodel::selectedIndexResetsOnAddEntries()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    model.addEntries({WallpaperEntry()});
    model.setSelectedIndex(0);
    QSignalSpy spy(&model, &WallpaperModel::selectedIndexChanged);

    // 整组替换后行号身份失效 → 清选中
    model.addEntries({WallpaperEntry(), WallpaperEntry()});
    QCOMPARE(model.selectedIndex(), -1);
    QCOMPARE(spy.count(), 1);
}

void tst_wallpapermodel::selectedIndexResetsOnClear()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    model.addEntries({WallpaperEntry()});
    model.setSelectedIndex(0);
    QSignalSpy spy(&model, &WallpaperModel::selectedIndexChanged);

    model.clear();
    QCOMPARE(model.selectedIndex(), -1);
    QCOMPARE(spy.count(), 1);
}

void tst_wallpapermodel::mergeAggregatesAcrossSources()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    QList<WallpaperEntry> ea, eb;
    ea.append(WallpaperEntry());
    ea.append(WallpaperEntry());
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString dirB = QDir(tmp.path()).filePath(QStringLiteral("b"));
    QVERIFY(QDir().mkpath(dirB));
    QFile index(dirB + QStringLiteral("/index.html"));
    QVERIFY(index.open(QIODevice::WriteOnly));
    index.write("<!doctype html>");
    index.close();
    eb.append(WallpaperEntry(WallpaperPath::toUrl(dirB)));
    modelA.addEntries(ea);
    modelB.addEntries(eb);

    WallpaperModel merged(QString{});
    merged.setSources({&modelA, &modelB});
    QCOMPARE(merged.rowCount(), 3);
    QCOMPARE(merged.count(), 3); // 聚合模式 count 与 rowCount 一致
    QCOMPARE(merged.data(merged.index(2, 0), WallpaperModel::NameRole).toString(), QStringLiteral("b"));

    WallpaperModel merged2(QString{});
    merged2.setSources({&modelB});
    QCOMPARE(merged2.rowCount(), 1);
}

void tst_wallpapermodel::mergeResetsOnSourceReset()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel merged(QString{});
    merged.setSources({&modelA});

    QSignalSpy resetSpy(&merged, &QAbstractItemModel::modelReset);
    modelA.addEntries({WallpaperEntry()}); // 源重置 → 聚合 model 也应 reset
    QCOMPARE(resetSpy.count(), 1);
}

// A(2 行) + B(1 行)：全局扁平索引写跨源转发到对应源 model 的局部行
void tst_wallpapermodel::mergeSelectedIndexForwardsToSource()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA, &modelB});

    // 行 0 落在 A 局部行 0
    merged.setSelectedIndex(0);
    QCOMPARE(modelA.selectedIndex(), 0);
    QCOMPARE(merged.selectedIndex(), 0);
    // 行 2 落在 B 局部行 0（偏移 2）
    merged.setSelectedIndex(2);
    QCOMPARE(modelB.selectedIndex(), 0);
    QCOMPARE(merged.selectedIndex(), 2);
}

// 单选语义：设置新源选中时清空其它源选中
void tst_wallpapermodel::mergeSelectedIndexSingleSelectClearsOthers()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA, &modelB});

    modelA.setSelectedIndex(1);
    QCOMPARE(modelA.selectedIndex(), 1);
    // 全局行 2 落在 B → A 选中被清空
    merged.setSelectedIndex(2);
    QCOMPARE(modelA.selectedIndex(), -1);
    QCOMPARE(modelB.selectedIndex(), 0);
    QCOMPARE(merged.selectedIndex(), 2);
}

// getter 实时聚合：首个非 -1 源映射回全局行
void tst_wallpapermodel::mergeSelectedIndexGetterAggregates()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA, &modelB});

    modelA.setSelectedIndex(1);
    QCOMPARE(merged.selectedIndex(), 1);
    // 直接设 B（第二源，offset=2）局部 0 → 全局 2：getter 应反映最后
    // 变化的源（B），而非被首个非 -1 源（A）的残留选中遮蔽
    modelB.setSelectedIndex(0);
    QCOMPARE(merged.selectedIndex(), 2);
}

void tst_wallpapermodel::mergeSelectedIndexMinusOneClearsAll()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA, &modelB});

    merged.setSelectedIndex(1);
    QCOMPARE(merged.selectedIndex(), 1);
    // -1 = 清除全部源选中
    merged.setSelectedIndex(-1);
    QCOMPARE(modelA.selectedIndex(), -1);
    QCOMPARE(modelB.selectedIndex(), -1);
    QCOMPARE(merged.selectedIndex(), -1);
}

// 重挂源后聚合值重算：保活源保留选中，删源丢失
void tst_wallpapermodel::mergeSetSourcesRemountRecomputes()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString{});

    modelA.setSelectedIndex(0);
    merged.setSources({&modelA});
    QCOMPARE(merged.selectedIndex(), 0);

    // 换到 B（无选中）→ 聚合值回到 -1
    merged.setSources({&modelB});
    QCOMPARE(merged.selectedIndex(), -1);
}

// 源 selectedIndexChanged 转发到合并 model
void tst_wallpapermodel::mergeSelectedIndexForwardsSourceSignal()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA});

    QSignalSpy spy(&merged, &WallpaperModel::selectedIndexChanged);
    modelA.setSelectedIndex(0);
    modelA.setSelectedIndex(1);
    modelA.setSelectedIndex(-1);
    QCOMPARE(spy.count(), 3);
}

// 聚合模式 get 跨源定位：全局行 → 所属源的本地 WallpaperItem*
void tst_wallpapermodel::mergeGetCrossesSources()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA, &modelB});

    QVERIFY(merged.get(0) == modelA.get(0));
    QVERIFY(merged.get(1) == modelA.get(1));
    QVERIFY(merged.get(2) == modelB.get(0));
    QCOMPARE(merged.get(-1), nullptr);
    QCOMPARE(merged.get(3), nullptr);
}

// 聚合模式 indexOf 跨源定位：source URL → 全局行
void tst_wallpapermodel::mergeIndexOfCrossesSources()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString dirA = QDir(tmp.path()).filePath(QStringLiteral("a"));
    QVERIFY(QDir().mkpath(dirA));
    const QString dirB = QDir(tmp.path()).filePath(QStringLiteral("b"));
    QVERIFY(QDir().mkpath(dirB));
    QFile idxA(dirA + QStringLiteral("/index.html"));
    QVERIFY(idxA.open(QIODevice::WriteOnly));
    idxA.write("<!doctype html>");
    idxA.close();
    QFile idxB(dirB + QStringLiteral("/index.html"));
    QVERIFY(idxB.open(QIODevice::WriteOnly));
    idxB.write("<!doctype html>");
    idxB.close();

    modelA.addEntries({WallpaperEntry(WallpaperPath::toUrl(dirA))});
    modelB.addEntries({WallpaperEntry(WallpaperPath::toUrl(dirB))});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA, &modelB});

    QCOMPARE(merged.indexOf(WallpaperPath::toUrl(dirA + QStringLiteral("/index.html"))), 0);
    QCOMPARE(merged.indexOf(WallpaperPath::toUrl(dirB + QStringLiteral("/index.html"))), 1);
    QCOMPARE(merged.indexOf(QStringLiteral("file:///nonexistent.html")), -1);
}

// 聚合模式是只读视图：addEntries/clear 非法调用被忽略（无 modelReset 副作用）
void tst_wallpapermodel::mergeRejectsAddEntriesAndClear()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    WallpaperModel merged(QString{});
    merged.setSources({&modelA});
    QCOMPARE(merged.rowCount(), 2);

    QSignalSpy spy(&merged, &QAbstractItemModel::modelReset);
    merged.addEntries({WallpaperEntry()});
    QCOMPARE(spy.count(), 0);
    merged.clear();
    QCOMPARE(spy.count(), 0);
    QCOMPARE(modelA.rowCount(), 2);
}

QTEST_MAIN(tst_wallpapermodel)
#include "tst_wallpapermodel.moc"
