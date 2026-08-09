/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperproperty.h"

#include <QStringLiteral>

namespace
{

// 属性 value 缺失时的兜底默认值（与旧 HTMLBackend / WallpaperPropertyModel 一致）。
QVariant defaultValue(const QVariantMap &raw, const QString &type)
{
    if (type == QLatin1String("bool")) {
        return false;
    }
    if (type == QLatin1String("slider")) {
        bool ok = false;
        const int m = raw.value(QStringLiteral("min")).toInt(&ok);
        return ok ? m : 0;
    }
    if (type == QLatin1String("combo")) {
        const QVariantList opts = raw.value(QStringLiteral("options")).toList();
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

WallpaperProperty::WallpaperProperty(const QString &key, const QVariantMap &raw)
    : m_key(key)
    , m_type(raw.value(QStringLiteral("type"), QStringLiteral("text")).toString())
    , m_text(raw.value(QStringLiteral("text"), key).toString())
    , m_value(raw.value(QStringLiteral("value")))
    , m_min(raw.value(QStringLiteral("min")))
    , m_max(raw.value(QStringLiteral("max")))
    , m_step(raw.value(QStringLiteral("step")))
    , m_fraction(raw.value(QStringLiteral("fraction")))
    , m_precision(raw.value(QStringLiteral("precision")))
    , m_options(raw.value(QStringLiteral("options")).toList())
    , m_condition(raw.value(QStringLiteral("condition")).toString())
    , m_group(raw.value(QStringLiteral("group")).toString())
{
    if (!raw.contains(QStringLiteral("value"))) {
        m_value = defaultValue(raw, m_type);
    }
    bool ok = false;
    const int o = raw.value(QStringLiteral("order")).toInt(&ok);
    m_order = ok ? o : std::numeric_limits<int>::max();
}
