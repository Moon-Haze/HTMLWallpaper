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
        disconnect(src, &WallpaperModel::selectedIndexChanged, this, &AllWallpapersModel::onSourceSelectedIndexChanged);
    }
    m_sources = sources;
    // 重挂后旧 lastChanged 源可能已释放或不再是源，先重置（getter 走兜底遍历）
    m_lastChangedSource = nullptr;
    for (WallpaperModel *src : m_sources) {
        connect(src, &WallpaperModel::modelReset, this, &AllWallpapersModel::onSourceReset);
        connect(src, &WallpaperModel::selectedIndexChanged, this, &AllWallpapersModel::onSourceSelectedIndexChanged);
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

int AllWallpapersModel::selectedIndex() const
{
    // 优先"最后变化的源"：直接操作源 model 制造多源选中时，getter 反映
    // 最新一次写入，而非被首个非 -1 源的残留选中遮蔽（如 A==1 后再设
    // B==0，应返回 B 的全局行而非 A 的）。该源需仍在挂载中且有选中。
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

int AllWallpapersModel::offsetOf(const WallpaperModel *src) const
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

void AllWallpapersModel::setSelectedIndex(int globalIndex)
{
    if (globalIndex < -1 || globalIndex >= rowCount()) {
        return; // 越界忽略，语义对齐 WallpaperModel
    }
    WallpaperModel *target = nullptr;
    int localRow = -1;
    if (globalIndex >= 0) {
        // remaining 递减跨源定位（与 data() 同源逻辑）
        int remaining = globalIndex;
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
    // 单选语义：清除非目标源选中；globalIndex == -1 时 target 为空 → 清空全部
    for (WallpaperModel *src : m_sources) {
        if (src != target && src->selectedIndex() >= 0) {
            src->setSelectedIndex(-1);
        }
    }
    if (target) {
        target->setSelectedIndex(localRow);
    }
    // 自身不 emit：源 setter 触发的 selectedIndexChanged 经转发统一收敛；
    // 幂等调用（值未变）时源不发信号 → 本方法 0 次 emit，符合"无变化不通知"。
}

void AllWallpapersModel::onSourceSelectedIndexChanged()
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
