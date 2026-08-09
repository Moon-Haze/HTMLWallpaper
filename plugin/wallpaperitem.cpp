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
    , m_file(meta.value(QStringLiteral("file")).toString())
    , m_preview(meta.value(QStringLiteral("preview")).toString())
    , m_monetization(meta.value(QStringLiteral("monetization")).toBool())
    , m_contentrating(meta.value(QStringLiteral("contentrating")).toString())
    , m_ratingsex(meta.value(QStringLiteral("ratingsex")).toString())
    , m_ratingviolence(meta.value(QStringLiteral("ratingviolence")).toString())
    , m_version(meta.value(QStringLiteral("version")).toInt())
    , m_workshopurl(meta.value(QStringLiteral("workshopurl")).toString())
    , m_supportsAudio(meta.value(QStringLiteral("supportsAudio")).toBool())
    , m_properties(meta.value(QStringLiteral("general")).toMap().value(QStringLiteral("properties")).toMap(), this)
    , m_supportsaudioprocessing(meta.value(QStringLiteral("supportsaudioprocessing")).toBool())
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

QString WallpaperItem::file() const
{
    return m_file;
}

QString WallpaperItem::preview() const
{
    return m_preview;
}

bool WallpaperItem::monetization() const
{
    return m_monetization;
}

QString WallpaperItem::contentrating() const
{
    return m_contentrating;
}

QString WallpaperItem::ratingsex() const
{
    return m_ratingsex;
}

QString WallpaperItem::ratingviolence() const
{
    return m_ratingviolence;
}

int WallpaperItem::version() const
{
    return m_version;
}

QString WallpaperItem::workshopurl() const
{
    return m_workshopurl;
}

const WallpaperPropertyModel *WallpaperItem::properties() const
{
    return &m_properties;
}

bool WallpaperItem::supportsaudioprocessing() const
{
    return m_supportsaudioprocessing;
}

bool WallpaperItem::supportsAudio() const
{
    return m_supportsAudio;
}
