/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QtTest>

#include "wallpaperproject.h"
#include "wallpaperproperty.h"
#include "wallpaperpropertyitem.h"
#include "wallpaperpropertymodel.h"

#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QUrl>

/**
 * C++ 数据层单测。与 QML 测试的分工：解析/规范化/排序等纯逻辑在此用
 * QTest 覆盖；QML 测试只保留扫描/列表行为契约。
 */
class tst_WallpaperProject : public QObject
{
    Q_OBJECT

private:
    // 把 fixtures 相对路径转成绝对 file:// URL（ctest WORKING_DIRECTORY=test/）
    static QString fixtureUrl(const QString &name);

private Q_SLOTS:
    void propertyTypeTextFallback();
    void propertyValueDefaults();
    void propertyOrderFallback();
    void propertyRawPassthrough();
    void projectParsesAurora();
    void projectParsesMatrix_properties();
    void projectParsesMissingEntry();
    void projectAutoDetectsPreview();
    void projectFailsWithoutJson();
    void propertyModelOrdering_paramfallback();
    void isHtmlTypeFilters();
    void entryResolution_absoluteUrl();
    void entryResolution_subPathAndQuery();
    void propertyModelMaterializes();
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

QString tst_WallpaperProject::fixtureUrl(const QString &name)
{
    return QUrl::fromLocalFile(QFileInfo(QStringLiteral("data/wallpapers/") + name).absoluteFilePath()).toString();
}

void tst_WallpaperProject::projectParsesAurora()
{
    WallpaperProject p(fixtureUrl(QStringLiteral("aurora")));
    QVERIFY(p.isValid());
    QCOMPARE(p.name(), QStringLiteral("aurora"));
    QCOMPARE(p.title(), QStringLiteral("Aurora"));
    QCOMPARE(p.tags(), QStringLiteral("aurora, sky"));
    QCOMPARE(p.type(), QStringLiteral("web"));
    QCOMPARE(p.visibility(), QStringLiteral("public"));
    QCOMPARE(p.workshopid(), QStringLiteral("1234567890"));
    QVERIFY(p.file().endsWith(QStringLiteral("/data/wallpapers/aurora/index.html")));
    QCOMPARE(p.source(), p.file());
    QCOMPARE(p.display(), QStringLiteral("Aurora"));
    QVERIFY(p.preview().endsWith(QStringLiteral("/data/wallpapers/aurora/preview.jpg")));
    QCOMPARE(p.monetization(), false);
    QCOMPARE(p.contentrating(), QStringLiteral("Everyone"));
    QCOMPARE(p.ratingsex(), QStringLiteral("none"));
    QCOMPARE(p.ratingviolence(), QStringLiteral("none"));
    QCOMPARE(p.version(), 3);
    QCOMPARE(p.workshopurl(), QStringLiteral("steam://url/CommunityFilePage/1234567890"));
    QCOMPARE(p.supportsAudio(), true);
    QVERIFY(p.properties().isEmpty()); // aurora 无 general
}

void tst_WallpaperProject::projectParsesMatrix_properties()
{
    WallpaperProject p(fixtureUrl(QStringLiteral("matrix")));
    QVERIFY(p.isValid());
    QVERIFY(p.file().endsWith(QStringLiteral("/data/wallpapers/matrix/main.html")));
    QCOMPARE(p.supportsaudioprocessing(), false);
    const auto &props = p.properties();
    QCOMPARE(props.size(), 4);
    // 按 order 排序：speed(1) color(2) glow(3) charset(4)
    QCOMPARE(props.at(0).key(), QStringLiteral("speed"));
    QCOMPARE(props.at(1).key(), QStringLiteral("color"));
    QCOMPARE(props.at(2).key(), QStringLiteral("glow"));
    QCOMPARE(props.at(3).key(), QStringLiteral("charset"));
    QCOMPARE(props.at(0).value(), 5);
    QCOMPARE(props.at(0).min(), 1);
    QCOMPARE(props.at(0).max(), 20);
    QCOMPARE(props.at(1).value(), QVariant(QStringLiteral("0 1 0")));
    QCOMPARE(props.at(2).value(), true);
    QCOMPARE(props.at(3).value(), QVariant(QStringLiteral("katakana")));
    QCOMPARE(props.at(3).options().size(), 2);
}

void tst_WallpaperProject::projectParsesMissingEntry()
{
    WallpaperProject p(fixtureUrl(QStringLiteral("missing-entry")));
    QVERIFY(p.isValid());
    // file 指向不存在的 ghost.html → 自动探测 real.html
    QVERIFY(p.file().endsWith(QStringLiteral("/data/wallpapers/missing-entry/real.html")));
}

void tst_WallpaperProject::projectAutoDetectsPreview()
{
    WallpaperProject p(fixtureUrl(QStringLiteral("nova")));
    QVERIFY(p.isValid());
    QVERIFY(p.preview().endsWith(QStringLiteral("/data/wallpapers/nova/preview.jpg")));
}

void tst_WallpaperProject::projectFailsWithoutJson()
{
    WallpaperProject neon(fixtureUrl(QStringLiteral("neon"))); // 目录无 project.json
    QVERIFY(!neon.isValid());

    WallpaperProject missing(fixtureUrl(QStringLiteral("does-not-exist")));
    QVERIFY(!missing.isValid());
}

void tst_WallpaperProject::propertyModelOrdering_paramfallback()
{
    WallpaperProject p(fixtureUrl(QStringLiteral("paramfallback")));
    QVERIFY(p.isValid());
    const auto &props = p.properties();
    QCOMPARE(props.size(), 5);
    // order 升序：beta(1) alpha(2) delta(3) gamma(4)；无 order 的 epsilon 稳定排最后
    QCOMPARE(props.at(0).key(), QStringLiteral("beta"));
    QCOMPARE(props.at(1).key(), QStringLiteral("alpha"));
    QCOMPARE(props.at(2).key(), QStringLiteral("delta"));
    QCOMPARE(props.at(3).key(), QStringLiteral("gamma"));
    QCOMPARE(props.at(4).key(), QStringLiteral("epsilon"));
    // value 兜底
    QCOMPARE(props.at(0).value(), false);    // bool → false
    QCOMPARE(props.at(1).value(), 3);        // slider 无 value → min=3
    QCOMPARE(props.at(2).value(), QVariant(QStringLiteral("a")));  // combo → 首个 option value
    QCOMPARE(props.at(3).value(), QVariant(QStringLiteral("0 0 0"))); // color
    QCOMPARE(props.at(4).value(), QString()); // text → ""
    // type/text 兜底
    QCOMPARE(props.at(4).type(), QStringLiteral("text"));
    QCOMPARE(props.at(4).text(), QStringLiteral("epsilon"));
}

void tst_WallpaperProject::isHtmlTypeFilters()
{
    using namespace WallpaperProjectJson;
    const QStringList nonHtml{QStringLiteral("video"), QStringLiteral("scene"), QStringLiteral("application"), QStringLiteral("audio")};
    // type 缺失 → 收录
    QVERIFY(isHtmlType(QString(), nonHtml));
    // 黑名单过滤（大小写不敏感）
    QVERIFY(!isHtmlType(QStringLiteral("video"), nonHtml));
    QVERIFY(!isHtmlType(QStringLiteral("SCENE"), nonHtml));
    QVERIFY(!isHtmlType(QStringLiteral("Application"), nonHtml));
    // HTML 类收录：web/color/group
    QVERIFY(isHtmlType(QStringLiteral("web"), nonHtml));
    QVERIFY(isHtmlType(QStringLiteral("Web"), nonHtml));
    QVERIFY(isHtmlType(QStringLiteral("color"), nonHtml));
    QVERIFY(isHtmlType(QStringLiteral("group"), nonHtml));
}

void tst_WallpaperProject::entryResolution_absoluteUrl()
{
    // 远程/绝对 URL 原样保留（不拼接壁纸目录）
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    QFile proj(dir.filePath(QStringLiteral("project.json")));
    QVERIFY(proj.open(QIODevice::WriteOnly));
    proj.write(R"({"title":"T","type":"web","file":"https://example.com/a.html"})");
    proj.close();

    WallpaperProject p(QUrl::fromLocalFile(dir.path()).toString());
    QVERIFY(p.isValid());
    QCOMPARE(p.file(), QStringLiteral("https://example.com/a.html"));
}

void tst_WallpaperProject::entryResolution_subPathAndQuery()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    // 相对子路径 + query 保留：img/bg.html?x=1 → 基于目录拼接
    QFile proj(dir.filePath(QStringLiteral("project.json")));
    QVERIFY(proj.open(QIODevice::WriteOnly));
    proj.write(R"({"title":"T","type":"web","file":"img/bg.html?x=1"})");
    proj.close();

    WallpaperProject p(QUrl::fromLocalFile(dir.path()).toString());
    QVERIFY(p.isValid());
    // 注：期望值用字符串拼接而非 QUrl::fromLocalFile —— fromLocalFile 会把 '?'
    // 编码为 %3F，与实现（字符串 pathJoin，保留原始 query）不符；注释意图为"query 保留"。
    QCOMPARE(p.file(), QStringLiteral("file://") + dir.path() + QStringLiteral("/img/bg.html?x=1"));
}

void tst_WallpaperProject::propertyModelMaterializes()
{
    WallpaperProject p(fixtureUrl(QStringLiteral("matrix")));
    QVERIFY(p.isValid());

    WallpaperPropertyModel model;
    model.setEntries(p.properties());
    QCOMPARE(model.count(), 4);

    // data(role) 委托
    QCOMPARE(model.data(model.index(0), WallpaperPropertyModel::KeyRole).toString(), QStringLiteral("speed"));
    QCOMPARE(model.data(model.index(1), WallpaperPropertyModel::ValueRole).toString(), QStringLiteral("0 1 0"));

    // get(i) 返回 QObject* 属性访问
    WallpaperPropertyItem *first = model.get(0);
    QVERIFY(first != nullptr);
    QCOMPARE(first->key(), QStringLiteral("speed"));
    QCOMPARE(first->value(), 5);
    QCOMPARE(first->order(), 1);

    // byKey 命中 / 未命中
    WallpaperPropertyItem *color = model.byKey(QStringLiteral("color"));
    QVERIFY(color != nullptr);
    QCOMPARE(color->value(), QVariant(QStringLiteral("0 1 0")));
    QVERIFY(model.byKey(QStringLiteral("nope")) == nullptr);

    // 越界 get → nullptr
    QVERIFY(model.get(-1) == nullptr);
    QVERIFY(model.get(4) == nullptr);
}

QTEST_MAIN(tst_WallpaperProject)
#include "tst_wallpaperproject.moc"
