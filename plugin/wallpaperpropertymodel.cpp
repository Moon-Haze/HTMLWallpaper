/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperpropertymodel.h"

#include <QStringLiteral>

#include <algorithm>
#include <limits>

namespace
{

// 属性 value 缺失时的兜底默认值（与旧 QML _defaultValue / HTMLBackend 一致）。
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

} // namespace

WallpaperPropertyModel::WallpaperPropertyModel(const QVariantMap &properties, QObject *parent)
    : QAbstractListModel(parent)
{
    // 规范化：先按 order 收集排序键，再稳定排序，最后归一化字段（type/text/value 兜底）。
    struct Row {
        QString key;
        QVariantMap map;
        int order;
    };
    // 注意：变量名不能用 "slots" —— Qt 定义 #define slots Q_SLOTS（moc 关键字宏），
    // 普通代码里展开为空，会导致 "declaration does not declare anything" 编译错误。
    QList<Row> rows;
    rows.reserve(properties.size());
    for (auto it = properties.constBegin(); it != properties.constEnd(); ++it) {
        QVariantMap row = it.value().toMap();
        bool ok = false;
        const int order = row.value(QStringLiteral("order")).toInt(&ok);
        rows.push_back({it.key(), row, ok ? order : std::numeric_limits<int>::max()});
    }
    // 按 order 升序；无 order 的属性稳定排到最后（与旧 HTMLBackend 解析一致）
    std::stable_sort(rows.begin(), rows.end(), [](const Row &a, const Row &b) {
        return a.order < b.order;
    });

    m_rows.reserve(rows.size());
    for (Row &r : rows) {
        r.map.insert(QStringLiteral("key"), r.key);
        if (!r.map.contains(QStringLiteral("type"))) {
            r.map.insert(QStringLiteral("type"), QStringLiteral("text"));
        }
        if (!r.map.contains(QStringLiteral("text"))) {
            r.map.insert(QStringLiteral("text"), r.key);
        }
        if (!r.map.contains(QStringLiteral("value"))) {
            r.map.insert(QStringLiteral("value"), defaultValue(r.map));
        }
        r.map.insert(QStringLiteral("order"), r.order);
        m_indexByKey.insert(r.key, m_rows.size());
        m_rows.append(r.map);
    }
}

int WallpaperPropertyModel::count() const
{
    return m_rows.size();
}

int WallpaperPropertyModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_rows.size();
}

QVariant WallpaperPropertyModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) {
        return {};
    }
    const QVariantMap &row = m_rows.at(index.row());
    switch (role) {
    case KeyRole:
        return row.value(QStringLiteral("key"));
    case TypeRole:
        return row.value(QStringLiteral("type"));
    case TextRole:
        return row.value(QStringLiteral("text"));
    case ValueRole:
        return row.value(QStringLiteral("value"));
    case MinRole:
        return row.value(QStringLiteral("min"));
    case MaxRole:
        return row.value(QStringLiteral("max"));
    case StepRole:
        return row.value(QStringLiteral("step"));
    case FractionRole:
        return row.value(QStringLiteral("fraction"));
    case PrecisionRole:
        return row.value(QStringLiteral("precision"));
    case OptionsRole:
        return row.value(QStringLiteral("options"));
    case ConditionRole:
        return row.value(QStringLiteral("condition"));
    case GroupRole:
        return row.value(QStringLiteral("group"));
    case OrderRole:
        return row.value(QStringLiteral("order"));
    default:
        return {};
    }
}

QHash<int, QByteArray> WallpaperPropertyModel::roleNames() const
{
    return {
        {KeyRole, "key"},
        {TypeRole, "type"},
        {TextRole, "text"},
        {ValueRole, "value"},
        {MinRole, "min"},
        {MaxRole, "max"},
        {StepRole, "step"},
        {FractionRole, "fraction"},
        {PrecisionRole, "precision"},
        {OptionsRole, "options"},
        {ConditionRole, "condition"},
        {GroupRole, "group"},
        {OrderRole, "order"},
    };
}

QVariantMap WallpaperPropertyModel::get(int i) const
{
    if (i < 0 || i >= m_rows.size()) {
        return {};
    }
    return m_rows.at(i);
}

QVariantMap WallpaperPropertyModel::byKey(const QString &key) const
{
    const int i = m_indexByKey.value(key, -1);
    if (i < 0) {
        return {};
    }
    return m_rows.at(i);
}
