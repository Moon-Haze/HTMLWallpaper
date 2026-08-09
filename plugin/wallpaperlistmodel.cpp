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
    case EntryRole:
        return item->entry();
    case PreviewRole:
        return item->preview();
    case DisplayRole:
        return item->title();
    case SourceRole:
        return item->entry();
    case CheckedRole:
        return item->checked();
    default:
        return {};
    }
}

bool WallpaperListModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size() || role != CheckedRole) {
        return false;
    }
    m_items.at(index.row())->setChecked(value.toBool());
    Q_EMIT dataChanged(index, index, {CheckedRole});
    return true;
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
        {EntryRole, "entry"},
        {PreviewRole, "preview"},
        {DisplayRole, "display"},
        {SourceRole, "source"},
        {CheckedRole, "checked"},
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

    // 默认选中第一项：保证单选/轮播始终有确定状态（重置完成后设置并刷新）
    if (!m_items.isEmpty()) {
        m_items.first()->setChecked(true);
    }
    Q_EMIT dataChanged(index(0, 0), index(qMax(0, m_items.size() - 1), 0), {CheckedRole});

    Q_EMIT countChanged();
}

void WallpaperListModel::clear()
{
    setEntries({});
}

QObject *WallpaperListModel::get(int i) const
{
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return m_items.at(i);
}

void WallpaperListModel::setProperty(int i, const QString &property, const QVariant &value)
{
    if (property == QLatin1String("checked")) {
        setData(index(i, 0), value, CheckedRole);
    }
}

void WallpaperListModel::setExclusiveChecked(int idx, bool checked)
{
    if (idx < 0 || idx >= m_items.size()) {
        return;
    }
    m_items.at(idx)->setChecked(checked);
    if (checked) {
        // 勾选本项时取消其余所有项，保证至多一项被勾选
        for (int i = 0; i < m_items.size(); ++i) {
            if (i != idx) {
                m_items.at(i)->setChecked(false);
            }
        }
    }
    Q_EMIT dataChanged(this->index(0, 0), this->index(m_items.size() - 1, 0), {CheckedRole});
}
