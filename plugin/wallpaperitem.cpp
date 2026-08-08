/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperitem.h"

#include <QStringLiteral>

WallpaperItem::WallpaperItem(const QVariantMap &meta, QObject *parent)
    : QObject(parent)
    , m_name(meta.value(QStringLiteral("name")).toString())
    , m_title(meta.value(QStringLiteral("title")).toString())
    , m_description(meta.value(QStringLiteral("description")).toString())
    , m_tags(meta.value(QStringLiteral("tags")).toString())
    , m_type(meta.value(QStringLiteral("type")).toString())
    , m_visibility(meta.value(QStringLiteral("visibility")).toString())
    , m_workshopid(meta.value(QStringLiteral("workshopid")).toString())
    , m_path(meta.value(QStringLiteral("path")).toString())
    , m_entry(meta.value(QStringLiteral("entry")).toString())
    , m_preview(meta.value(QStringLiteral("preview")).toString())
{
}

QString WallpaperItem::name() const
{
    return m_name;
}

QString WallpaperItem::title() const
{
    return m_title;
}

QString WallpaperItem::description() const
{
    return m_description;
}

QString WallpaperItem::tags() const
{
    return m_tags;
}

QString WallpaperItem::type() const
{
    return m_type;
}

QString WallpaperItem::visibility() const
{
    return m_visibility;
}

QString WallpaperItem::workshopid() const
{
    return m_workshopid;
}

QString WallpaperItem::path() const
{
    return m_path;
}

QString WallpaperItem::entry() const
{
    return m_entry;
}

QString WallpaperItem::preview() const
{
    return m_preview;
}

bool WallpaperItem::checked() const
{
    return m_checked;
}

void WallpaperItem::setChecked(bool checked)
{
    if (m_checked == checked) {
        return;
    }
    m_checked = checked;
    Q_EMIT checkedChanged();
}
