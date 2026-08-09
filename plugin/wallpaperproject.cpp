/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperproject.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QRegularExpression>
#include <QUrl>

#include <algorithm>
#include <limits>

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

// project.json 的 tags 是字符串数组，模型 role 不能存字符串数组，序列化成逗号分隔。
QString toTagsString(const QVariant &tags)
{
    if (tags.typeId() == QMetaType::QVariantList) {
        QStringList parts;
        const QVariantList list = tags.toList();
        for (const QVariant &t : list) {
            parts.append(t.toString());
        }
        return parts.join(QStringLiteral(", "));
    }
    return tags.toString();
}

// workshopid 转字符串：数字 0 → 空串（原 QML `data.workshopid || ""` 的 falsy 语义），
// 其它数字按十进制（'g' 精度 15 位，避免大数转科学计数过早截断）。
QString workshopIdString(const QVariant &wid)
{
    if (!wid.isValid() || wid.isNull()) {
        return {};
    }
    const int t = wid.typeId();
    if (t == QMetaType::Double || t == QMetaType::Int || t == QMetaType::LongLong || t == QMetaType::ULongLong || t == QMetaType::UInt) {
        const double d = wid.toDouble();
        return d == 0.0 ? QString() : QString::number(d, 'g', 15);
    }
    return wid.toString();
}

// 入口文件 / 预览图路径：绝对 URL（带 scheme://）原样返回；相对路径基于壁纸目录拼接。
QString resolveEntry(const QString &baseUrl, const QString &path)
{
    if (!QUrl(path).scheme().isEmpty()) {
        return path;
    }
    return WallpaperProjectJson::pathJoin(baseUrl, path);
}

// 在壁纸目录里查找常见预览图文件名，命中返回其 file:// URL，否则空串。
QString findPreview(const QString &dirUrl)
{
    static const QStringList candidates = {
        QStringLiteral("preview.png"),
        QStringLiteral("preview.jpg"),
        QStringLiteral("preview.jpeg"),
        QStringLiteral("preview.gif"),
        QStringLiteral("preview.webp"),
        QStringLiteral("default.png"),
        QStringLiteral("thumbnail.png"),
    };
    const QString dir = QUrl(dirUrl).toLocalFile();
    for (const QString &c : candidates) {
        if (QFile::exists(dir + QLatin1Char('/') + c)) {
            return WallpaperProjectJson::pathJoin(dirUrl, c);
        }
    }
    return {};
}

// 解析 HTML 入口文件（project.json 的 file 字段，绝对 URL）：
// 指定文件存在（或为远程 URL）→ 原样返回；指定的本地文件缺失或未指定 →
// 依次探测常见入口名（index.html/main.html/...），再枚举目录下所有 .html/.htm
// 取字典序第一个；均未命中 → 返回空串。
QString findEntry(const QString &dirUrl, const QString &specified)
{
    if (!specified.isEmpty()) {
        const QString local = QUrl(specified).toLocalFile();
        if (local.isEmpty() || QFile::exists(local)) {
            return specified; // 远程 URL（非 file://）或本地文件存在 → 原样返回
        }
    }
    const QString dir = QUrl(dirUrl).toLocalFile();
    static const QStringList common = {
        QStringLiteral("index.html"),
        QStringLiteral("index.htm"),
        QStringLiteral("main.html"),
        QStringLiteral("main.htm"),
        QStringLiteral("start.html"),
    };
    for (const QString &c : common) {
        if (QFile::exists(dir + QLatin1Char('/') + c)) {
            return WallpaperProjectJson::pathJoin(dirUrl, c);
        }
    }
    const QStringList html = QDir(dir).entryList({QStringLiteral("*.html"), QStringLiteral("*.htm")}, QDir::Files, QDir::Name);
    if (!html.isEmpty()) {
        return WallpaperProjectJson::pathJoin(dirUrl, html.first());
    }
    return {};
}

// 读 <目录>/project.json → QVariantMap；文件缺失 / JSON 非法 → 空 map。
QVariantMap loadProjectJson(const QString &dirUrl)
{
    const QString path = QUrl(dirUrl).toLocalFile() + QStringLiteral("/project.json");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    const QByteArray raw = file.readAll();
    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning().noquote() << "WallpaperProject: invalid JSON in" << path << error.errorString();
        return {};
    }
    return doc.object().toVariantMap();
}

// 解析 general.properties → 按 order 稳定排序的属性列表；无 order 者稳定排最后。
QList<WallpaperProperty> parseProperties(const QVariantMap &properties)
{
    QList<WallpaperProperty> list;
    list.reserve(properties.size());
    for (auto it = properties.constBegin(); it != properties.constEnd(); ++it) {
        list.append(WallpaperProperty(it.key(), it.value().toMap()));
    }
    std::stable_sort(list.begin(), list.end(), [](const WallpaperProperty &a, const WallpaperProperty &b) {
        return a.order() < b.order();
    });
    return list;
}

} // namespace

namespace WallpaperProjectJson
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

bool isHtmlType(const QString &type, const QStringList &nonHtmlTypes)
{
    if (type.isEmpty()) {
        return true;
    }
    const QString lower = type.toLower();
    for (const QString &t : nonHtmlTypes) {
        if (lower == t.toLower()) {
            return false;
        }
    }
    return true;
}

} // namespace WallpaperProjectJson

WallpaperProject::WallpaperProject(const QString &dirUrl)
{
    const QString url = WallpaperProjectJson::toUrl(dirUrl);
    const QVariantMap data = loadProjectJson(url);
    if (data.isEmpty()) {
        return; // 无 project.json / 解析失败 → 保持空对象
    }

    const QString name = basename(url);
    const QString entryFile = data.value(QStringLiteral("file"), QStringLiteral("index.html")).toString();
    const QString previewFile = data.value(QStringLiteral("preview")).toString();
    const QString entry = resolveEntry(url, entryFile);

    m_name = name;
    m_title = data.value(QStringLiteral("title"), name).toString();
    m_description = data.value(QStringLiteral("description")).toString();
    m_tags = toTagsString(data.value(QStringLiteral("tags")));
    m_type = data.value(QStringLiteral("type"), QStringLiteral("web")).toString();
    m_visibility = data.value(QStringLiteral("visibility")).toString();
    m_workshopid = workshopIdString(data.value(QStringLiteral("workshopid")));
    m_path = url;
    m_file = entry;
    m_preview = previewFile.isEmpty() ? QString() : resolveEntry(url, previewFile);
    m_monetization = data.value(QStringLiteral("monetization")).toBool();
    m_contentrating = data.value(QStringLiteral("contentrating")).toString();
    m_ratingsex = data.value(QStringLiteral("ratingsex")).toString();
    m_ratingviolence = data.value(QStringLiteral("ratingviolence")).toString();
    m_version = data.value(QStringLiteral("version")).toInt();
    m_workshopurl = data.value(QStringLiteral("workshopurl")).toString();

    // 预览探测：preview 缺失 → 自动探测目录下常见预览图。
    if (m_preview.isEmpty()) {
        m_preview = findPreview(url);
    }
    // 入口存在性兜底：指定入口（或缺省 index.html）指向的本地文件缺失时，
    // 自动探测目录下其它 html 入口；探测失败则保留原始解析值。
    if (!m_file.isEmpty()) {
        const QString found = findEntry(url, m_file);
        if (!found.isEmpty()) {
            m_file = found;
        }
    }

    // general 容器：properties（可配置属性表）+ supportsaudioprocessing。
    const QVariantMap general = data.value(QStringLiteral("general")).toMap();
    m_properties = parseProperties(general.value(QStringLiteral("properties")).toMap());
    m_supportsaudioprocessing = general.value(QStringLiteral("supportsaudioprocessing")).toBool();
    // 音频支持：顶层 supportsAudio（FetchTerminal）或 general.supportsaudioprocessing
    // （AudioVisualizer / CanvasBg）任一为 true 即视为支持；缺失 → false。
    m_supportsAudio = data.value(QStringLiteral("supportsAudio")).toBool() || m_supportsaudioprocessing;

    m_valid = true;
}
