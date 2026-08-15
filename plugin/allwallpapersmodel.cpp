/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "allwallpapersmodel.h"

#include "wallpapermodel.h"

AllWallpapersModel::AllWallpapersModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

void AllWallpapersModel::setSources(const QList<WallpaperModel *> &sources)
{
    for (WallpaperModel *src : m_sources) {
        disconnect(src, &WallpaperModel::modelReset, this, &AllWallpapersModel::onSourceReset);
    }
    m_sources = sources;
    for (WallpaperModel *src : m_sources) {
        connect(src, &WallpaperModel::modelReset, this, &AllWallpapersModel::onSourceReset);
    }
    beginResetModel();
    endResetModel();
}

int AllWallpapersModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    int total = 0;
    for (const WallpaperModel *src : m_sources) {
        total += src->rowCount();
    }
    return total;
}

QVariant AllWallpapersModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount()) {
        return {};
    }
    int remaining = index.row();
    for (const WallpaperModel *src : m_sources) {
        const int count = src->rowCount();
        if (remaining < count) {
            return src->data(src->index(remaining, 0), role);
        }
        remaining -= count;
    }
    return {};
}

QHash<int, QByteArray> AllWallpapersModel::roleNames() const
{
    // 硬编码对齐 WallpaperModel::roleNames（五字段），QML role 名一致
    return {
        {WallpaperModel::NameRole, "name"},
        {WallpaperModel::TitleRole, "title"},
        {WallpaperModel::PathRole, "path"},
        {WallpaperModel::PreviewRole, "preview"},
        {WallpaperModel::FileRole, "file"},
    };
}

void AllWallpapersModel::onSourceReset()
{
    beginResetModel();
    endResetModel();
}
