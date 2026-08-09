/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "htmlbackend.h"

#include "wallpaperitem.h"
#include "wallpaperlistmodel.h"

#include <QDir>
#include <QFile>
#include <QFutureWatcher>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QPair>
#include <QRegularExpression>
#include <QUrl>
#include <QVariantMap>
#include <QtConcurrent>

// ---------------------------------------------------------------------------
// 扫描 worker 的结果聚合（后台线程只产生纯数据，主线程消费）
// ---------------------------------------------------------------------------

struct HTMLBackendScanResult {
    QList<QVariantMap> wallpapers;
    QList<QPair<QString, QString>> failures; // (path, error)
};

// ---------------------------------------------------------------------------
// 纯函数辅助（不触碰任何 QObject，可安全地在后台线程调用）
// ---------------------------------------------------------------------------

namespace
{

// 归一化为带 scheme 的 URL：裸路径（"/usr/share/..."）补 file:// 前缀。
QString toUrl(const QString &p)
{
    const QString s = p;
    return s.contains(QLatin1String("://")) ? s : QStringLiteral("file://") + s;
}

// 去 a 尾部斜杠 + 去 b 前导斜杠后拼接。
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

QString basename(const QString &url)
{
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s.mid(s.lastIndexOf(QLatin1Char('/')) + 1);
}

// 判断某 project.json 的 type 是否属于可加载的 HTML 类壁纸。
// type 缺失或不在黑名单 → 视为 HTML（收录）。
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

// project.json 的 tags 是字符串数组，但模型 role 不能存字符串数组，序列化成逗号分隔。
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
    const QString s = path;
    if (!QUrl(s).scheme().isEmpty()) {
        return s;
    }
    return pathJoin(baseUrl, s);
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
            return pathJoin(dirUrl, c);
        }
    }
    return {};
}

// 解析 HTML 入口文件（project.json 的 file 字段，绝对 URL）：
// 指定文件存在（或为远程 URL）→ 原样返回；指定的本地文件缺失或未指定 →
// 依次探测常见入口名（index.html/main.html/...），再枚举目录下所有 .html/.htm
// 取字典序第一个；均未命中 → 返回空串（调用方保留原默认值，由页面加载阶段兜底）。
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
            return pathJoin(dirUrl, c);
        }
    }
    const QStringList html = QDir(dir).entryList({QStringLiteral("*.html"), QStringLiteral("*.htm")}, QDir::Files, QDir::Name);
    if (!html.isEmpty()) {
        return pathJoin(dirUrl, html.first());
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
        qWarning().noquote() << "HTMLBackend: invalid JSON in" << path << error.errorString();
        return {};
    }
    return doc.object().toVariantMap();
}

// 把 project.json 顶层对象整理成统一的壁纸元数据；非 HTML 类型返回空 map。
QVariantMap parseMetadata(const QString &dirUrl, const QVariantMap &data, bool requireWebType, const QStringList &nonHtmlTypes)
{
    if (requireWebType && !isHtmlType(data.value(QStringLiteral("type")).toString(), nonHtmlTypes)) {
        return {};
    }
    const QString name = basename(dirUrl);
    const QString entryFile = data.value(QStringLiteral("file"), QStringLiteral("index.html")).toString();
    const QString previewFile = data.value(QStringLiteral("preview")).toString();
    QVariantMap meta;
    meta.insert(QStringLiteral("name"), name);
    meta.insert(QStringLiteral("title"), data.value(QStringLiteral("title"), name).toString());
    meta.insert(QStringLiteral("description"), data.value(QStringLiteral("description")).toString());
    meta.insert(QStringLiteral("tags"), toTagsString(data.value(QStringLiteral("tags"))));
    meta.insert(QStringLiteral("type"), data.value(QStringLiteral("type"), QStringLiteral("web")).toString());
    meta.insert(QStringLiteral("visibility"), data.value(QStringLiteral("visibility")).toString());
    meta.insert(QStringLiteral("workshopid"), workshopIdString(data.value(QStringLiteral("workshopid"))));
    meta.insert(QStringLiteral("path"), dirUrl);
    // file：project.json 的 file 字段，指向 html 壁纸的入口文件（相对路径基于壁纸目录解析为绝对 URL）
    const QString entry = resolveEntry(dirUrl, entryFile);
    meta.insert(QStringLiteral("file"), entry);
    // entry：file 的兼容别名（对齐 slideFilterModel 的历史命名，source=entry）
    meta.insert(QStringLiteral("entry"), entry);
    // preview：预览缩略图相对路径，同样基于壁纸目录解析为绝对 URL；缺失 → 空串（由扫描时自动探测补上）
    meta.insert(QStringLiteral("preview"), previewFile.isEmpty() ? QString() : resolveEntry(dirUrl, previewFile));

    // —— 扩展元数据：覆盖 html-wallpapers 各壁纸 project.json 中的顶层字段 ——
    // monetization：是否商业壁纸；缺失 → false
    meta.insert(QStringLiteral("monetization"), data.value(QStringLiteral("monetization")).toBool());
    // 内容分级：contentrating（整体）与 ratingsex / ratingviolence（分项）；缺失 → 空串
    meta.insert(QStringLiteral("contentrating"), data.value(QStringLiteral("contentrating")).toString());
    meta.insert(QStringLiteral("ratingsex"), data.value(QStringLiteral("ratingsex")).toString());
    meta.insert(QStringLiteral("ratingviolence"), data.value(QStringLiteral("ratingviolence")).toString());
    // 壁纸版本号；缺失 → 0
    meta.insert(QStringLiteral("version"), data.value(QStringLiteral("version")).toInt());
    meta.insert(QStringLiteral("workshopurl"), data.value(QStringLiteral("workshopurl")).toString());
    // general 容器：原样保留整个 general 对象（properties 可配置属性表 +
    // supportsaudioprocessing）；缺失 → 空 map
    const QVariantMap general = data.value(QStringLiteral("general")).toMap();
    meta.insert(QStringLiteral("general"), general);
    // 注意：properties 缺省时 value() 返回无效 QVariant，需 toMap() 兜底为空 map，
    // 否则 QML 侧 m.generalProperties 是 undefined 而非空对象
    meta.insert(QStringLiteral("generalProperties"), general.value(QStringLiteral("properties")).toMap());
    meta.insert(QStringLiteral("supportsaudioprocessing"), general.value(QStringLiteral("supportsaudioprocessing")).toBool());
    // 音频支持：顶层 supportsAudio（FetchTerminal）或 general.supportsaudioprocessing
    // （AudioVisualizer / CanvasBg）任一为 true 即视为支持；缺失 → false
    const bool supportsAudio = data.value(QStringLiteral("supportsAudio")).toBool() || general.value(QStringLiteral("supportsaudioprocessing")).toBool();
    meta.insert(QStringLiteral("supportsAudio"), supportsAudio);
    return meta;
}

// "R G B"（各 0~1）→ "#RRGGBB"；非 3 分量或含 NaN → 黑。仅接受字符串输入。
QString colorToHexImpl(const QString &value)
{
    const QStringList parts = value.trimmed().split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    if (parts.size() != 3) {
        return QStringLiteral("#000000");
    }
    QString hex;
    for (const QString &part : parts) {
        bool ok = false;
        const double d = part.toDouble(&ok);
        if (!ok) {
            return QStringLiteral("#000000");
        }
        const int c = qRound(qBound(0.0, d, 1.0) * 255.0);
        hex += QStringLiteral("%1").arg(c, 2, 16, QLatin1Char('0'));
    }
    return QLatin1Char('#') + hex;
}

// 后台扫描：只做纯数据读取（QFile + QJsonDocument），不触碰任何 QObject。
HTMLBackendScanResult scanWorker(const QStringList &roots, bool requireWebType, const QStringList &nonHtmlTypes)
{
    HTMLBackendScanResult result;
    for (const QString &base : roots) {
        const QString baseUrl = toUrl(base);
        const QString localDir = QUrl(baseUrl).toLocalFile();
        QDir dir(localDir);
        if (!dir.exists()) {
            result.failures.append({base, QStringLiteral("cannot list directory")});
            continue;
        }
        const QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &sub : subdirs) {
            const QString dirUrl = pathJoin(baseUrl, sub);
            const QVariantMap data = loadProjectJson(dirUrl);
            if (data.isEmpty()) {
                continue; // 无 project.json 的子目录静默跳过（与旧实现一致）
            }
            QVariantMap meta = parseMetadata(dirUrl, data, requireWebType, nonHtmlTypes);
            if (meta.isEmpty()) {
                continue; // 非 HTML 类型过滤
            }
            const QString previewFile = meta.value(QStringLiteral("preview")).toString();
            if (previewFile.isEmpty()) {
                const QString p = findPreview(dirUrl);
                if (!p.isEmpty()) {
                    meta.insert(QStringLiteral("preview"), p);
                }
            }
            // file 存在性兜底：project.json 的 file（或缺省 index.html）指向的
            // 本地文件不存在时，自动探测目录下其它 html 入口，保证列表里的
            // file/entry 始终是可加载的绝对 URL（file/entry 同源同步修正）
            const QString entryFile = meta.value(QStringLiteral("file")).toString();
            if (!entryFile.isEmpty()) {
                const QString found = findEntry(dirUrl, entryFile);
                if (!found.isEmpty() && found != entryFile) {
                    meta.insert(QStringLiteral("file"), found);
                    meta.insert(QStringLiteral("entry"), found);
                }
            }
            result.wallpapers.append(meta);
        }
    }
    return result;
}

} // namespace

// ---------------------------------------------------------------------------
// HTMLBackend
// ---------------------------------------------------------------------------

HTMLBackend::HTMLBackend(QObject *parent)
    : QObject(parent)
    , m_wallpapers(new WallpaperListModel(this))
{
}

QStringList HTMLBackend::rootPaths() const
{
    return m_rootPaths;
}

void HTMLBackend::setRootPaths(const QStringList &paths)
{
    QStringList normalized;
    normalized.reserve(paths.size());
    for (const QString &p : paths) {
        normalized.append(toUrl(p));
    }
    if (m_rootPaths == normalized) {
        return;
    }
    m_rootPaths = normalized;
    Q_EMIT rootPathsChanged();
}

bool HTMLBackend::requireWebType() const
{
    return m_requireWebType;
}

void HTMLBackend::setRequireWebType(bool requireWebType)
{
    if (m_requireWebType == requireWebType) {
        return;
    }
    m_requireWebType = requireWebType;
    Q_EMIT requireWebTypeChanged();
}

QStringList HTMLBackend::nonHtmlTypes() const
{
    return m_nonHtmlTypes;
}

void HTMLBackend::setNonHtmlTypes(const QStringList &nonHtmlTypes)
{
    if (m_nonHtmlTypes == nonHtmlTypes) {
        return;
    }
    m_nonHtmlTypes = nonHtmlTypes;
    Q_EMIT nonHtmlTypesChanged();
}

bool HTMLBackend::scanInProgress() const
{
    return m_scanning;
}

void HTMLBackend::setScanInProgress(bool inProgress)
{
    if (m_scanning == inProgress) {
        return;
    }
    m_scanning = inProgress;
    Q_EMIT scanInProgressChanged();
}

WallpaperListModel *HTMLBackend::wallpapers() const
{
    return m_wallpapers;
}

bool HTMLBackend::addScanPath(const QString &path)
{
    const QString p = toUrl(path);
    if (m_rootPaths.contains(p)) {
        return false;
    }
    m_rootPaths.append(p);
    Q_EMIT rootPathsChanged();
    return true;
}

void HTMLBackend::removeScanPath(const QString &path)
{
    const QString p = toUrl(path);
    if (!m_rootPaths.contains(p)) {
        return;
    }
    m_rootPaths.removeAll(p);
    Q_EMIT rootPathsChanged();
}

void HTMLBackend::scan()
{
    if (m_scanning) {
        return;
    }
    setScanInProgress(true);
    m_wallpapers->clear();

    // 快照传给后台线程：worker 只读这些值拷贝，绝不触碰任何 QObject 成员。
    const QStringList roots = m_rootPaths;
    const bool requireWebType = m_requireWebType;
    const QStringList nonHtmlTypes = m_nonHtmlTypes;

    if (!m_watcher) {
        m_watcher = new QFutureWatcher<HTMLBackendScanResult>(this);
        QObject::connect(m_watcher, &QFutureWatcher<HTMLBackendScanResult>::finished, this, [this]() {
            const HTMLBackendScanResult result = m_watcher->result();
            for (const auto &failure : result.failures) {
                Q_EMIT scanFailed(failure.first, failure.second);
            }
            m_wallpapers->setEntries(result.wallpapers);
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWorker, roots, requireWebType, nonHtmlTypes));
}
