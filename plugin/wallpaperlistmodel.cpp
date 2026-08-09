/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperlistmodel.h"

#include "wallpaperitem.h"

#include <QHash>

WallpaperListModel::WallpaperListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int WallpaperListModel::count() const
{
    return m_items.size();
}

int WallpaperListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_items.size();
}

QVariant WallpaperListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }
    const WallpaperItem *item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item->name();
    case TitleRole:
        return item->title();
    case DescriptionRole:
        return item->description();
    case TagsRole:
        return item->tags();
    case TypeRole:
        return item->type();
    case VisibilityRole:
        return item->visibility();
    case WorkshopIdRole:
        return item->workshopid();
    case PathRole:
        return item->path();
    case PreviewRole:
        return item->preview();
    case MonetizationRole:
        return item->monetization();
    case ContentRatingRole:
        return item->contentrating();
    case RatingSexRole:
        return item->ratingsex();
    case RatingViolenceRole:
        return item->ratingviolence();
    case VersionRole:
        return item->version();
    case WorkshopUrlRole:
        return item->workshopurl();
    case SupportsAudioRole:
        return item->supportsAudio();
    case FileRole:
        return item->file();
    default:
        return {};
    }
}

bool WallpaperListModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    Q_UNUSED(index);
    Q_UNUSED(value);
    Q_UNUSED(role);
    return false; // 目前仅支持 setProperty / setExclusiveChecked 写回 checked
}

QHash<int, QByteArray> WallpaperListModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {TitleRole, "title"},
        {DescriptionRole, "description"},
        {TagsRole, "tags"},
        {TypeRole, "type"},
        {VisibilityRole, "visibility"},
        {WorkshopIdRole, "workshopid"},
        {PathRole, "path"},
        {PreviewRole, "preview"},
        {MonetizationRole, "monetization"},
        {ContentRatingRole, "contentrating"},
        {RatingSexRole, "ratingsex"},
        {RatingViolenceRole, "ratingviolence"},
        {VersionRole, "version"},
        {WorkshopUrlRole, "workshopurl"},
        {SupportsAudioRole, "supportsaudio"},
        {FileRole, "file"},
    };
}

void WallpaperListModel::setEntries(const QList<QVariantMap> &metas)
{
    beginResetModel();
    qDeleteAll(m_items);
    m_items.clear();
    m_items.reserve(metas.size());
    for (const QVariantMap &meta : metas) {
        m_items.append(new WallpaperItem(meta, this));
    }
    endResetModel();
    Q_EMIT dataChanged(index(0, 0),
                       index(qMax(0, m_items.size() - 1), 0),
                       {
                           NameRole,
                           TitleRole,
                           DescriptionRole,
                           TagsRole,
                           TypeRole,
                           VisibilityRole,
                           WorkshopIdRole,
                           PathRole,
                           PreviewRole,
                           MonetizationRole,
                           ContentRatingRole,
                           RatingSexRole,
                           RatingViolenceRole,
                           VersionRole,
                           WorkshopUrlRole,
                           SupportsAudioRole,
                           FileRole,
                       });
}

void WallpaperListModel::clear()
{
    beginResetModel();
    qDeleteAll(m_items);
    m_items.clear();
    endResetModel();
}

QObject *WallpaperListModel::get(int i) const
{
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return m_items.at(i);
}
