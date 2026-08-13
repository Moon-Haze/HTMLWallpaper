/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperpropertyitem.h"

WallpaperPropertyItem::WallpaperPropertyItem(const WallpaperProperty &property, QObject *parent)
    : QObject(parent)
    , m_property(property)
{
}

WallpaperPropertyItem::WallpaperPropertyItem(const WallpaperPropertyItem &item, QObject *parent)
    : WallpaperPropertyItem(item.m_property, parent)
{
}
WallpaperPropertyItem &WallpaperPropertyItem::operator=(const WallpaperPropertyItem &item)
{
    if (this != &item) {
        this->m_property = item.m_property;
    }
    return *this;
}

QString WallpaperPropertyItem::key() const
{
    return m_property.key();
}
QString WallpaperPropertyItem::type() const
{
    return m_property.type();
}
QString WallpaperPropertyItem::text() const
{
    return m_property.text();
}
QVariant WallpaperPropertyItem::value() const
{
    return m_property.value();
}
QVariant WallpaperPropertyItem::min() const
{
    return m_property.min();
}
QVariant WallpaperPropertyItem::max() const
{
    return m_property.max();
}
QVariant WallpaperPropertyItem::step() const
{
    return m_property.step();
}
QVariant WallpaperPropertyItem::fraction() const
{
    return m_property.fraction();
}
QVariant WallpaperPropertyItem::precision() const
{
    return m_property.precision();
}
QVariantList WallpaperPropertyItem::options() const
{
    return m_property.options();
}
QString WallpaperPropertyItem::condition() const
{
    return m_property.condition();
}
QString WallpaperPropertyItem::group() const
{
    return m_property.group();
}
int WallpaperPropertyItem::order() const
{
    return m_property.order();
}