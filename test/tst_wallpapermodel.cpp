/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QPointer>
#include <QtTest>

#include "wallpapermodel.h"
#include "wallpaperitem.h"
#include "allwallpapersmodel.h"
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
    void mergeAggregatesAcrossSources();
    void mergeResetsOnSourceReset();
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

QTEST_MAIN(tst_wallpapermodel)
#include "tst_wallpapermodel.moc"
