/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <qobject.h>
#include <qtmetamacros.h>

#include "wallpaperentry.h"
#include "wallpaperitem.h"

/**
 * @brief 单个文件夹的壁纸列表模型（WallpaperModel::modelFor 的返回）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) 与 data()。roles 对齐 WallpaperDelegate / ThumbnailsView
 * 使用的字段：name / title / path / preview / file（file 是目录探测选出的
 * *.html 入口）。
 *
 * 单文件夹语义：一个实例只装一个扫描根（key，归一化 URL）的壁纸。
 * setEntries(entries) 整组替换本文件夹条目（同文件夹重扫即覆盖）；
 * addEntries(entries) 追加实体到末尾（不清空已有条目）。
 * 无扫描逻辑、无后台线程——扫描编排由 WallpaperController 承担。
 */
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(QString key READ key CONSTANT) // 本文件夹归一化 URL
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        PreviewRole,
        FileRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperModel(const QString &key, QObject *parent = nullptr);

    QString key() const;
    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 整组替换本文件夹全部条目；同文件夹重扫即覆盖。主线程调用；reset 一次。 */
    Q_INVOKABLE void setEntries(const QList<WallpaperEntry> &wallpapers);
    /** 追加实体到列表末尾（保留已有条目）；insertRows 通知视图。主线程调用。 */
    Q_INVOKABLE void addEntries(const QList<WallpaperEntry> &wallpapers);

    void clear();

    /** 兼容原 ListModel：返回第 i 项属性门面对象；越界返回 nullptr。 */
    Q_INVOKABLE WallpaperItem *get(int i);

    /** 本文件夹选中行（-1 = 无选中）。越界（< -1 或 >= count）忽略。 */
    int selectedIndex() const;
    void setSelectedIndex(int index);

Q_SIGNALS:
    void selectedIndexChanged();

private:
    QString m_key; // 本文件夹归一化 URL
    QList<WallpaperItem *> m_items; // 本文件夹的壁纸项（QObject parent = 本 model）
    int m_selectedIndex = -1; // 本文件夹选中行（-1 = 无选中）
};
