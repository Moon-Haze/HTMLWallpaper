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

    // 同 key 覆盖后总数应为 1，分组数不变
    QCOMPARE(model.count(), 1);
    QCOMPARE(model.groupCount(), 1);
    // 旧 WallpaperItem 应已被 delete（QPointer 变 null）
    QVERIFY(survivor.isNull() || survivor->parent() != &model);
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
