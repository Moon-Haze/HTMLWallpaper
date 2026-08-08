/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "htmlpropertyitem.h"

HTMLPropertyItem::HTMLPropertyItem(QObject *parent)
    : QObject(parent)
{
}

QString HTMLPropertyItem::key() const
{
    return m_key;
}
void HTMLPropertyItem::setKey(const QString &key)
{
    m_key = key;
    Q_EMIT changed();
}
QString HTMLPropertyItem::type() const
{
    return m_type;
}
void HTMLPropertyItem::setType(const QString &type)
{
    m_type = type;
    Q_EMIT changed();
}
QString HTMLPropertyItem::text() const
{
    return m_text;
}
void HTMLPropertyItem::setText(const QString &text)
{
    m_text = text;
    Q_EMIT changed();
}
QVariant HTMLPropertyItem::propValue() const
{
    return m_propValue;
}
void HTMLPropertyItem::setPropValue(const QVariant &propValue)
{
    m_propValue = propValue;
    Q_EMIT changed();
}
QVariant HTMLPropertyItem::min() const
{
    return m_min;
}
void HTMLPropertyItem::setMin(const QVariant &min)
{
    m_min = min;
    Q_EMIT changed();
}
QVariant HTMLPropertyItem::max() const
{
    return m_max;
}
void HTMLPropertyItem::setMax(const QVariant &max)
{
    m_max = max;
    Q_EMIT changed();
}
QVariant HTMLPropertyItem::step() const
{
    return m_step;
}
void HTMLPropertyItem::setStep(const QVariant &step)
{
    m_step = step;
    Q_EMIT changed();
}
QVariant HTMLPropertyItem::fraction() const
{
    return m_fraction;
}
void HTMLPropertyItem::setFraction(const QVariant &fraction)
{
    m_fraction = fraction;
    Q_EMIT changed();
}
QVariant HTMLPropertyItem::precision() const
{
    return m_precision;
}
void HTMLPropertyItem::setPrecision(const QVariant &precision)
{
    m_precision = precision;
    Q_EMIT changed();
}
QVariantList HTMLPropertyItem::options() const
{
    return m_options;
}
void HTMLPropertyItem::setOptions(const QVariantList &options)
{
    m_options = options;
    Q_EMIT changed();
}
QString HTMLPropertyItem::condition() const
{
    return m_condition;
}
void HTMLPropertyItem::setCondition(const QString &condition)
{
    m_condition = condition;
    Q_EMIT changed();
}
QString HTMLPropertyItem::group() const
{
    return m_group;
}
void HTMLPropertyItem::setGroup(const QString &group)
{
    m_group = group;
    Q_EMIT changed();
}
int HTMLPropertyItem::order() const
{
    return m_order;
}
void HTMLPropertyItem::setOrder(int order)
{
    m_order = order;
    Q_EMIT changed();
}
