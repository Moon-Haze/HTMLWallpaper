/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <limits>

/**
 * @brief project.json 的 general.properties 中单个可配置属性（值类型）。
 *
 * 无 QObject、可拷贝/移动，后台线程可安全构造（扫描 worker 在后台线程
 * 解析属性表时使用）。规范化规则（与旧 WallpaperPropertyModel 一致）：
 *   - type 缺失 → "text"；text 缺失 → key；
 *   - value 缺失 → 按 type 兜底默认值（bool→false、slider→min（无 min→0）、
 *     combo→首个 option 的 value、color→"0 0 0"、其余→空串）；
 *   - order 缺失 → int max（order 排序在 WallpaperProject::parseProperties
 *     做稳定排序，无 order 者稳定排最后）。
 * min/max/step/fraction/precision/options/condition/group 原样透传（缺省为
 * 无效 QVariant / 空列表 / 空串）。
 */
class WallpaperProperty
{
public:
    WallpaperProperty() = default;
    WallpaperProperty(const QString &key, const QVariantMap &raw);

    QString key() const;
    QString type() const;
    QString text() const;
    QVariant value() const;
    QVariant min() const;
    QVariant max() const;
    QVariant step() const;
    QVariant fraction() const;
    QVariant precision() const;
    QVariantList options() const;
    QString condition() const;
    QString group() const;
    int order() const;

private:
    QString m_key;
    QString m_type;
    QString m_text;
    QVariant m_value;
    QVariant m_min;
    QVariant m_max;
    QVariant m_step;
    QVariant m_fraction;
    QVariant m_precision;
    QVariantList m_options;
    QString m_condition;
    QString m_group;
    int m_order = std::numeric_limits<int>::max();
};
