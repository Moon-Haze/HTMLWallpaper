/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>

#include "wallpapermodel.h"

/**
 * @brief 多文件夹合并 model（"全部"视图的数据源，懒建于 controller）。
 *
 * 聚合多个单文件夹 WallpaperModel 为一个扁平 QAbstractListModel：
 * rowCount 各源求和，data 跨源定位行后透传源 data，roleNames 对齐
 * WallpaperModel 五字段。监听各源 modelReset，任一源重置即整体 reset。
 *
 * 生命周期由 WallpaperController 持有（保活复用）；scan 后经 setSources
 * 重挂最新源，不会出现 QML 持引用时被销毁的悬空。
 */
class AllWallpapersModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)
public:
    explicit AllWallpapersModel(QObject *parent = nullptr);

    /** 重建源挂载：断开旧源连接、连接新源、自身整体 reset。 */
    void setSources(const QList<WallpaperModel *> &sources);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 全局扁平行号（跨源聚合，首个非 -1 源映射回全局行）。 */
    int selectedIndex() const;
    /** 设置全局选中行；跨源定位到目标源并单选清空其它源。越界忽略。 */
    void setSelectedIndex(int globalIndex);

Q_SIGNALS:
    void selectedIndexChanged();

private:
    void onSourceReset();
    void onSourceSelectedIndexChanged(); // 源选中变化转发（缓存去重）
    QList<WallpaperModel *> m_sources;
    int m_selectedIndex = -1; // 聚合缓存，仅用于信号去重
};
