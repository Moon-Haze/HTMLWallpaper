/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QList>

#include "wallpaperproperty.h"

class WallpaperPropertyItem;

/**
 * @brief project.json 的 general.properties 可配置属性表（只读 ListModel，列表层）。
 *
 * 与 WallpaperListModel 同构：无参构造，经 setEntries(QList<WallpaperProperty>)
 * 物化 WallpaperPropertyItem*（QObject 行）。排序/兜底规范化由数据层
 * WallpaperProperty 完成（后台线程），本类主线程只物化 + 供 QML 访问。
 *
 * QML 用法：delegate 用 roles（key/type/text/value/min/max/step/fraction/
 * precision/options/condition/group/order），或经 count/get(i)/byKey(key)
 * 命令式访问（返回 WallpaperPropertyItem，可 .key/.value 等属性访问）。
 */
class WallpaperPropertyModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)

public:
    enum Roles {
        KeyRole = Qt::UserRole + 1,
        TypeRole,
        TextRole,
        ValueRole,
        MinRole,
        MaxRole,
        StepRole,
        FractionRole,
        PrecisionRole,
        OptionsRole,
        ConditionRole,
        GroupRole,
        OrderRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperPropertyModel(QObject *parent = nullptr);

    /** 整体替换全部属性行（扫描完成时主线程调用）；只发一次 reset。 */
    void setEntries(const QList<WallpaperProperty> &properties);

    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 返回第 i 行属性门面对象；越界返回 nullptr。 */
    Q_INVOKABLE WallpaperPropertyItem *get(int i) const;
    /** 按 key 返回属性门面对象；不存在返回 nullptr。 */
    Q_INVOKABLE WallpaperPropertyItem *byKey(const QString &key) const;

private:
    QList<WallpaperPropertyItem *> m_items;
    QHash<QString, int> m_indexByKey;
};
