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
public:
    explicit AllWallpapersModel(QObject *parent = nullptr);

    /** 重建源挂载：断开旧源连接、连接新源、自身整体 reset。 */
    void setSources(const QList<WallpaperModel *> &sources);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    void onSourceReset();
    QList<WallpaperModel *> m_sources;
};
