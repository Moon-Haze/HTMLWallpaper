/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapermodel.h"

#include "wallpaperitem.h"

WallpaperModel::WallpaperModel(const QString &key, QObject *parent)
    : QAbstractListModel(parent)
    , m_key(key)
{
}

QString WallpaperModel::key() const
{
    return m_key;
}

int WallpaperModel::count() const
{
    return rowCount();
}

int WallpaperModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    if (m_isAggregate) {
        int total = 0;
        for (const WallpaperModel *src : m_sources) {
            total += src->rowCount();
        }
        return total;
    }
    return m_items.size();
}

QVariant WallpaperModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0) {
        return {};
    }
    if (m_isAggregate) {
        if (index.row() >= rowCount()) {
            return {};
        }
        // remaining 递减跨源定位（原 AllWallpapersModel 逻辑）
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
    if (index.row() >= m_items.size()) {
        return {};
    }
    auto item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item->name();
    case PathRole:
        return item->path();
    case PreviewRole:
        return item->preview();
    case FileRole:
        return item->file();
    default:
        return {};
    }
}

QHash<int, QByteArray> WallpaperModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {PathRole, "path"},
        {PreviewRole, "preview"},
        {FileRole, "file"},
    };
}

void WallpaperModel::addEntries(const QList<WallpaperEntry> &wallpapers)
{
    if (m_isAggregate) {
        return; // 聚合模式只读视图，非法调用忽略
    }
    beginResetModel();
    for (WallpaperItem *p : m_items) {
        delete p; // 释放旧条目（QObject parent = 本 model）
    }
    m_items.clear();
    for (const WallpaperEntry &entry : wallpapers) {
        m_items.append(new WallpaperItem(entry, this));
    }
    endResetModel();
    resetSelectedIndexIfNeeded();
}

void WallpaperModel::clear()
{
    if (m_isAggregate) {
        return; // 聚合模式只读视图，非法调用忽略
    }
    beginResetModel();
    for (WallpaperItem *p : m_items) {
        delete p;
    }
    m_items.clear();
    endResetModel();
    resetSelectedIndexIfNeeded();
}

bool WallpaperModel::isAggregate() const
{
    return m_isAggregate;
}

void WallpaperModel::setSources(const QList<WallpaperModel *> &sources)
{
    for (WallpaperModel *src : m_sources) {
        disconnect(src, &WallpaperModel::modelReset, this, &WallpaperModel::onSourceReset);
        disconnect(src, &WallpaperModel::selectedIndexChanged, this, &WallpaperModel::onSourceSelectedIndexChanged);
    }
    m_sources = sources;
    m_isAggregate = true;
    // 重挂后旧 lastChanged 源可能已释放或不再是源，先重置（getter 走兜底遍历）
    m_lastChangedSource = nullptr;
    for (WallpaperModel *src : m_sources) {
        connect(src, &WallpaperModel::modelReset, this, &WallpaperModel::onSourceReset);
        connect(src, &WallpaperModel::selectedIndexChanged, this, &WallpaperModel::onSourceSelectedIndexChanged);
    }
    beginResetModel();
    endResetModel();
    // 重挂后聚合值可能变化（保活源保留 / 删源丢失），与缓存同步
    const int idx = selectedIndex();
    if (idx != m_selectedIndex) {
        m_selectedIndex = idx;
        Q_EMIT selectedIndexChanged();
    }
}

void WallpaperModel::onSourceReset()
{
    beginResetModel();
    endResetModel();
}

// 整组替换后行号身份失效，清选中（仅原值非 -1 时通知，无变化不 emit）
void WallpaperModel::resetSelectedIndexIfNeeded()
{
    if (m_selectedIndex != -1) {
        m_selectedIndex = -1;
        Q_EMIT selectedIndexChanged();
    }
}

int WallpaperModel::selectedIndex() const
{
    if (m_isAggregate) {
        // 优先"最后变化的源"：直接操作源 model 制造多源选中时，getter 反映
        // 最新一次写入，而非被首个非 -1 源的残留选中遮蔽
        if (m_lastChangedSource && m_sources.contains(m_lastChangedSource) && m_lastChangedSource->selectedIndex() >= 0) {
            return offsetOf(m_lastChangedSource) + m_lastChangedSource->selectedIndex();
        }
        // 兜底：单选不变量（合并 setter 写路径保证）下遍历首个非 -1 源即可
        int offset = 0;
        for (const WallpaperModel *src : m_sources) {
            const int local = src->selectedIndex();
            if (local >= 0) {
                return offset + local;
            }
            offset += src->rowCount();
        }
        return -1;
    }
    return m_selectedIndex;
}

void WallpaperModel::setSelectedIndex(int index)
{
    if (index < -1 || index >= rowCount()) {
        return; // 越界忽略，语义对齐（叶子与聚合）
    }
    if (m_isAggregate) {
        WallpaperModel *target = nullptr;
        int localRow = -1;
        if (index >= 0) {
            int remaining = index;
            for (WallpaperModel *src : m_sources) {
                const int count = src->rowCount();
                if (remaining < count) {
                    target = src;
                    localRow = remaining;
                    break;
                }
                remaining -= count;
            }
        }
        // 单选语义：清除非目标源选中；index == -1 时 target 为空 → 清空全部
        for (WallpaperModel *src : m_sources) {
            if (src != target && src->selectedIndex() >= 0) {
                src->setSelectedIndex(-1);
            }
        }
        if (target) {
            target->setSelectedIndex(localRow);
        }
        return; // 源 setter 触发的 selectedIndexChanged 经转发统一收敛
    }
    if (m_selectedIndex == index) {
        return;
    }
    m_selectedIndex = index;
    Q_EMIT selectedIndexChanged();
}

int WallpaperModel::offsetOf(const WallpaperModel *src) const
{
    int offset = 0;
    for (const WallpaperModel *s : m_sources) {
        if (s == src) {
            break;
        }
        offset += s->rowCount();
    }
    return offset;
}

void WallpaperModel::onSourceSelectedIndexChanged()
{
    // 记录最后变化的源，供 getter 优先返回（多源残留选中时反映最新写入）
    m_lastChangedSource = qobject_cast<WallpaperModel *>(sender());
    // 源选中变化转发，缓存去重（setter 跨源切换时可能瞬时 emit -1 再终值，可接受）
    const int idx = selectedIndex();
    if (idx != m_selectedIndex) {
        m_selectedIndex = idx;
        Q_EMIT selectedIndexChanged();
    }
}

int WallpaperModel::indexOf(const QString &source) const
{
    if (m_isAggregate) {
        int offset = 0;
        for (const WallpaperModel *src : m_sources) {
            const int local = src->indexOf(source);
            if (local >= 0) {
                return offset + local;
            }
            offset += src->rowCount();
        }
        return -1;
    }
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i)->file() == source) {
            return i;
        }
    }
    return -1;
}

WallpaperItem *WallpaperModel::get(int i)
{
    if (m_isAggregate) {
        if (i < 0 || i >= rowCount()) {
            return nullptr;
        }
        int remaining = i;
        for (WallpaperModel *src : m_sources) {
            const int count = src->rowCount();
            if (remaining < count) {
                return src->get(remaining);
            }
            remaining -= count;
        }
        return nullptr;
    }
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return m_items.at(i);
}
