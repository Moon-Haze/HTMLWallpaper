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
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QPair>
#include <QRegularExpression>
#include <QUrl>
#include <QVariantMap>
#include <QtConcurrent>

#include <algorithm>
#include <limits>

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
    meta.insert(QStringLiteral("entry"), resolveEntry(dirUrl, entryFile));
    meta.insert(QStringLiteral("preview"), previewFile.isEmpty() ? QString() : resolveEntry(dirUrl, previewFile));
    return meta;
}

// 属性 value 缺失时的兜底默认值（与旧 QML _defaultValue 一致）。
QVariant defaultValue(const QVariantMap &p)
{
    const QString type = p.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("bool")) {
        return false;
    }
    if (type == QLatin1String("slider")) {
        bool ok = false;
        const int m = p.value(QStringLiteral("min")).toInt(&ok);
        return ok ? m : 0;
    }
    if (type == QLatin1String("combo")) {
        const QVariantList opts = p.value(QStringLiteral("options")).toList();
        if (!opts.isEmpty()) {
            return opts.first().toMap().value(QStringLiteral("value"));
        }
        return 0;
    }
    if (type == QLatin1String("color")) {
        return QStringLiteral("0 0 0");
    }
    return QString();
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

WallpaperItem *HTMLBackend::currentWallpaper() const
{
    return m_currentWallpaper;
}

void HTMLBackend::setCurrentWallpaper(WallpaperItem *currentWallpaper)
{
    if (m_currentWallpaper == currentWallpaper) {
        return;
    }
    m_currentWallpaper = currentWallpaper;
    Q_EMIT currentWallpaperChanged();
}

QVariantList HTMLBackend::currentProperties() const
{
    QVariantList list;
    list.reserve(m_properties.size());
    for (const HTMLPropertyItem *item : m_properties) {
        list.append(QVariant::fromValue(const_cast<HTMLPropertyItem *>(item)));
    }
    return list;
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
        connect(m_watcher, &QFutureWatcher<HTMLBackendScanResult>::finished, this, [this]() {
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

void HTMLBackend::parseWallpaper(const QString &path)
{
    const QString dirUrl = toUrl(path);
    const QVariantMap data = loadProjectJson(dirUrl);
    if (data.isEmpty()) {
        qWarning().noquote() << "HTMLBackend: no project.json in" << dirUrl;
        setCurrentWallpaper(nullptr);
        parsePropertiesIntoItems({});
        Q_EMIT currentPropertiesChanged();
        return;
    }
    const QVariant meta = _parseMetadata(dirUrl, data);
    if (meta.isNull()) {
        // requireWebType 过滤：非 HTML 类型，按“无壁纸”处理
        setCurrentWallpaper(nullptr);
        parsePropertiesIntoItems({});
        Q_EMIT currentPropertiesChanged();
        Q_EMIT wallpaperParsed(nullptr);
        return;
    }
    auto *item = new WallpaperItem(meta.toMap(), this);
    setCurrentWallpaper(item);
    parsePropertiesIntoItems(data.value(QStringLiteral("general")).toMap().value(QStringLiteral("properties")).toMap());
    Q_EMIT currentPropertiesChanged();
    Q_EMIT wallpaperParsed(item);
}

QString HTMLBackend::buildQueryString() const
{
    QStringList parts;
    for (const HTMLPropertyItem *item : m_properties) {
        const QVariant v = item->propValue();
        if (v.isNull() || (v.typeId() == QMetaType::QString && v.toString().isEmpty())) {
            continue;
        }
        QString str;
        if (v.typeId() == QMetaType::Bool) {
            str = v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
        } else if (item->type() == QLatin1String("color")) {
            str = colorToHex(v);
        } else {
            str = v.toString();
        }
        const QString key = QString::fromUtf8(QUrl::toPercentEncoding(item->key()));
        const QString val = QString::fromUtf8(QUrl::toPercentEncoding(str));
        parts << key + QLatin1Char('=') + val;
    }
    return parts.join(QLatin1Char('&'));
}

QString HTMLBackend::buildPropertiesJson() const
{
    QJsonObject obj;
    for (const HTMLPropertyItem *item : m_properties) {
        QVariant v = item->propValue();
        if (v.isNull() || (v.typeId() == QMetaType::QString && v.toString().isEmpty())) {
            continue;
        }
        if (item->type() == QLatin1String("color")) {
            v = colorToHex(v);
        }
        obj.insert(item->key(), QJsonValue::fromVariant(v));
    }
    return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

QString HTMLBackend::applyPropertiesToUrl(const QString &baseUrl) const
{
    const QString query = buildQueryString();
    if (query.isEmpty()) {
        return baseUrl;
    }
    return baseUrl + (baseUrl.contains(QLatin1Char('?')) ? QStringLiteral("&") : QStringLiteral("?")) + query;
}

QString HTMLBackend::colorToHex(const QVariant &value) const
{
    if (value.typeId() != QMetaType::QString) {
        return QStringLiteral("#000000");
    }
    return colorToHexImpl(value.toString());
}

bool HTMLBackend::evaluateCondition(const QVariant &condition, const QVariantMap &props)
{
    const QString cond = condition.toString().trimmed();
    if (cond.isEmpty()) {
        return true;
    }
    // 与旧 QML 的 Function.apply(null, keys.concat(["return ("+cond+")"])) 等价：
    // 每个属性键作为参数名注入，表达式通过 .value 引用属性值。
    const QStringList keys = props.keys();
    const QString src = QStringLiteral("(function(") + keys.join(QStringLiteral(",")) + QStringLiteral(") { return (") + cond + QStringLiteral("); })");
    QJSValue fn = m_engine.evaluate(src);
    if (!fn.isCallable()) {
        return true; // 语法错误（如 "theme.value ==="）→ 宽松 true
    }
    QJSValueList args;
    for (const QString &k : keys) {
        QJSValue wrapper = m_engine.newObject();
        wrapper.setProperty(QStringLiteral("value"), m_engine.toScriptValue(props.value(k)));
        args.append(wrapper);
    }
    const QJSValue result = fn.call(args);
    if (result.isError()) {
        return true;
    }
    return result.toBool();
}

QVariantList HTMLBackend::propertyGroups() const
{
    QStringList order;
    QMap<QString, QVariantList> map;
    QMap<QString, QString> titles;
    QString anchor; // 当前激活的组锚点
    for (const HTMLPropertyItem *item : m_properties) {
        if (item->type() == QLatin1String("group")) {
            anchor = item->key();
            if (!map.contains(anchor)) {
                map.insert(anchor, {});
                order.append(anchor);
            }
            titles.insert(anchor, item->text().isEmpty() ? anchor : item->text());
            continue;
        }
        const QString g = item->group().isEmpty() ? anchor : item->group();
        if (!map.contains(g)) {
            map.insert(g, {});
            order.append(g);
        }
        if (!g.isEmpty() && !titles.contains(g)) {
            titles.insert(g, g);
        }
        map[g].append(QVariant::fromValue(const_cast<HTMLPropertyItem *>(item)));
    }
    QVariantList groups;
    for (const QString &g : order) {
        QVariantMap group;
        group.insert(QStringLiteral("group"), g);
        group.insert(QStringLiteral("title"), titles.value(g, g));
        group.insert(QStringLiteral("items"), map.value(g));
        groups.append(group);
    }
    return groups;
}

QVariant HTMLBackend::_parseMetadata(const QString &dirUrl, const QVariantMap &data)
{
    QVariantMap meta = parseMetadata(dirUrl, data, m_requireWebType, m_nonHtmlTypes);
    if (meta.isEmpty()) {
        // 过滤命中（非 HTML 类型）：返回 QObject* null，QML 里即 JS null
        return QVariant::fromValue<QObject *>(nullptr);
    }
    return meta;
}

void HTMLBackend::_parseProperties(const QVariantMap &properties)
{
    parsePropertiesIntoItems(properties);
    Q_EMIT currentPropertiesChanged();
}

void HTMLBackend::parsePropertiesIntoItems(const QVariantMap &properties)
{
    qDeleteAll(m_properties);
    m_properties.clear();

    struct Slot {
        QString key;
        QVariantMap map;
        int order;
    };
    // 注意：变量名不能用 "slots" —— Qt 定义 #define slots Q_SLOTS（moc 关键字宏），
    // 普通代码里展开为空，会导致 "declaration does not declare anything" 编译错误。
    QList<Slot> slotList;
    slotList.reserve(properties.size());
    for (auto it = properties.constBegin(); it != properties.constEnd(); ++it) {
        const QVariantMap p = it.value().toMap();
        bool ok = false;
        const int order = p.value(QStringLiteral("order")).toInt(&ok);
        slotList.push_back({it.key(), p, ok ? order : std::numeric_limits<int>::max()});
    }
    // 按 order 升序；无 order 的属性稳定排到最后（与旧 QML sort + JS 稳定排序一致）
    std::stable_sort(slotList.begin(), slotList.end(), [](const Slot &a, const Slot &b) {
        return a.order < b.order;
    });

    for (const Slot &s : slotList) {
        auto *item = new HTMLPropertyItem(this);
        item->setKey(s.key);
        item->setType(s.map.value(QStringLiteral("type"), QStringLiteral("text")).toString());
        item->setText(s.map.value(QStringLiteral("text"), s.key).toString());
        item->setPropValue(s.map.contains(QStringLiteral("value")) ? s.map.value(QStringLiteral("value")) : defaultValue(s.map));
        item->setMin(s.map.value(QStringLiteral("min")));
        item->setMax(s.map.value(QStringLiteral("max")));
        item->setStep(s.map.value(QStringLiteral("step")));
        item->setFraction(s.map.value(QStringLiteral("fraction")));
        item->setPrecision(s.map.value(QStringLiteral("precision")));
        item->setOptions(s.map.value(QStringLiteral("options")).toList());
        item->setCondition(s.map.value(QStringLiteral("condition")).toString());
        item->setGroup(s.map.value(QStringLiteral("group")).toString());
        item->setOrder(s.order);
        m_properties.append(item);
    }
}

QString HTMLBackend::_pathJoin(const QString &a, const QString &b) const
{
    return pathJoin(a, b);
}

QString HTMLBackend::_basename(const QString &url) const
{
    return basename(url);
}
