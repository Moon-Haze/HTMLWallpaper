/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QtTest>

#include "wallpaperproperty.h"

/**
 * C++ 数据层单测。与 QML 测试的分工：解析/规范化/排序等纯逻辑在此用
 * QTest 覆盖；QML 测试只保留扫描/列表行为契约。
 */
class tst_WallpaperProject : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void propertyTypeTextFallback();
    void propertyValueDefaults();
    void propertyOrderFallback();
    void propertyRawPassthrough();
};

void tst_WallpaperProject::propertyTypeTextFallback()
{
    // type 缺省 → "text"；text 缺省 → key
    QVariantMap raw;
    WallpaperProperty p(QStringLiteral("epsilon"), raw);
    QCOMPARE(p.key(), QStringLiteral("epsilon"));
    QCOMPARE(p.type(), QStringLiteral("text"));
    QCOMPARE(p.text(), QStringLiteral("epsilon"));
    QCOMPARE(p.value(), QString()); // text 无 value → 空串

    // 显式 type/text
    QVariantMap raw2{{QStringLiteral("type"), QStringLiteral("slider")},
                     {QStringLiteral("text"), QStringLiteral("Speed")}};
    WallpaperProperty p2(QStringLiteral("speed"), raw2);
    QCOMPARE(p2.type(), QStringLiteral("slider"));
    QCOMPARE(p2.text(), QStringLiteral("Speed"));
}

void tst_WallpaperProject::propertyValueDefaults()
{
    // bool → false
    QVariantMap boolRaw{{QStringLiteral("type"), QStringLiteral("bool")}};
    QCOMPARE(WallpaperProperty(QStringLiteral("b"), boolRaw).value(), QVariant(false));

    // slider → min；无 min → 0
    QVariantMap sliderRaw{{QStringLiteral("type"), QStringLiteral("slider")},
                          {QStringLiteral("min"), 3}};
    QCOMPARE(WallpaperProperty(QStringLiteral("s"), sliderRaw).value(), QVariant(3));
    QVariantMap sliderNoMin{{QStringLiteral("type"), QStringLiteral("slider")}};
    QCOMPARE(WallpaperProperty(QStringLiteral("s2"), sliderNoMin).value(), QVariant(0));

    // combo → 首个 option 的 value；无 options → 0
    QVariantMap comboRaw{{QStringLiteral("type"), QStringLiteral("combo")},
                         {QStringLiteral("options"), QVariantList{QVariantMap{{QStringLiteral("label"), QStringLiteral("A")},
                                                                                {QStringLiteral("value"), QStringLiteral("a")}},
                                                                  QVariantMap{{QStringLiteral("label"), QStringLiteral("B")},
                                                                                {QStringLiteral("value"), QStringLiteral("b")}}}}};
    QCOMPARE(WallpaperProperty(QStringLiteral("c"), comboRaw).value(), QVariant(QStringLiteral("a")));

    // color → "0 0 0"
    QVariantMap colorRaw{{QStringLiteral("type"), QStringLiteral("color")}};
    QCOMPARE(WallpaperProperty(QStringLiteral("col"), colorRaw).value(), QVariant(QStringLiteral("0 0 0")));

    // 显式 value 覆盖兜底
    QVariantMap explicitRaw{{QStringLiteral("type"), QStringLiteral("bool")},
                            {QStringLiteral("value"), true}};
    QCOMPARE(WallpaperProperty(QStringLiteral("be"), explicitRaw).value(), QVariant(true));
}

void tst_WallpaperProject::propertyOrderFallback()
{
    QVariantMap raw;
    QCOMPARE(WallpaperProperty(QStringLiteral("k"), raw).order(), std::numeric_limits<int>::max());

    QVariantMap withOrder{{QStringLiteral("order"), 2}};
    QCOMPARE(WallpaperProperty(QStringLiteral("k"), withOrder).order(), 2);

    // 非数字 order → 缺省
    QVariantMap badOrder{{QStringLiteral("order"), QStringLiteral("x")}};
    QCOMPARE(WallpaperProperty(QStringLiteral("k"), badOrder).order(), std::numeric_limits<int>::max());
}

void tst_WallpaperProject::propertyRawPassthrough()
{
    // 非规范化字段原样透传
    QVariantMap raw{{QStringLiteral("min"), 1},
                    {QStringLiteral("max"), 20},
                    {QStringLiteral("step"), 1},
                    {QStringLiteral("fraction"), true},
                    {QStringLiteral("precision"), 2},
                    {QStringLiteral("condition"), QStringLiteral("a.value === 1")},
                    {QStringLiteral("group"), QStringLiteral("appearance")}};
    WallpaperProperty p(QStringLiteral("s"), raw);
    QCOMPARE(p.min(), QVariant(1));
    QCOMPARE(p.max(), QVariant(20));
    QCOMPARE(p.step(), QVariant(1));
    QCOMPARE(p.fraction(), QVariant(true));
    QCOMPARE(p.precision(), QVariant(2));
    QCOMPARE(p.condition(), QStringLiteral("a.value === 1"));
    QCOMPARE(p.group(), QStringLiteral("appearance"));
    QVERIFY(p.options().isEmpty());
}

QTEST_MAIN(tst_WallpaperProject)
#include "tst_wallpaperproject.moc"
