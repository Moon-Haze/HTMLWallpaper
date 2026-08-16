/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QtTest>

#include "wallpapermodel.h"
#include <QSignalSpy>

/**
 * WallpaperModel 单文件夹语义的 C++ 单测。
 *
 * 直接构造无效 WallpaperEntry()（目录探测的空条目）验证单文件夹的
 * 追加/清空/roles 等纯结构逻辑，不依赖文件系统。
 */
class tst_wallpapermodel : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void keyRoundTrip();
    void addEntriesAppends();
    void clearEmptiesAll();
    void dataRolesAndGet();
    void getRTemplateByRole();
    void selectedIndexDefaultIsMinusOne();
    void selectedIndexSetAndEmit();
    void selectedIndexOutOfRangeIgnored();
};

void tst_wallpapermodel::keyRoundTrip()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    QCOMPARE(model.key(), QStringLiteral("file:///root/a"));
}

void tst_wallpapermodel::addEntriesAppends()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    model.addEntries({WallpaperEntry(), WallpaperEntry()});
    QCOMPARE(model.count(), 2);
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.rowCount(model.index(0, 0)), 0); // 无子项
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

void tst_wallpapermodel::getRTemplateByRole()
{
    WallpaperModel model(QStringLiteral("file:///root/a"));
    model.addEntries({WallpaperEntry()});

    // 无效 WallpaperEntry 的各字段为空；模板按角色取到对应字段值
    QCOMPARE(model.get<WallpaperModel::FileRole>(0), QString());
    QCOMPARE(model.get<WallpaperModel::NameRole>(0), QString());
    QCOMPARE(model.get<WallpaperModel::PathRole>(0), QString());
    QCOMPARE(model.get<WallpaperModel::PreviewRole>(0), QString());

    // 越界返回空 QVariant（不崩溃）
    QVERIFY(model.get<WallpaperModel::FileRole>(-1).isNull());
    QVERIFY(model.get<WallpaperModel::FileRole>(5).isNull());
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

QTEST_MAIN(tst_wallpapermodel)
#include "tst_wallpapermodel.moc"
