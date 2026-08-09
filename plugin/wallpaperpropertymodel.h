/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QVariantList>
#include <QVariantMap>

/**
 * @brief project.json 的 general.properties 可配置属性表（只读 ListModel）。
 *
 * 以 QAbstractListModel 存储规范化后的属性定义（每行一个属性，含 key），使
 * QML 可直接作 ListView/Repeater 的 model：delegate 用 model.key / model.type /
 * model.value ...，或经 count / get(i) / byKey(key) 命令式访问。行字段与
 * Wallpaper Engine 的 property 定义一致（key/type/text/value/min/max/step/
 * fraction/precision/options/condition/group/order）。
 *
 * 规范化规则（与旧 HTMLBackend 的属性解析一致）：
 *   - 行按 order 升序；无 order 的属性稳定排到最后；
 *   - type 缺失 → "text"；text 缺失 → key；value 缺失 → 按 type 兜底默认值
 *     （bool→false、slider→min（无 min→0）、combo→首个 option、color→"0 0 0"、
 *     其余→空串）。
 * 模型只读：value 不持久化、不写回、不应用到壁纸（改值仅限 QML 会话内）。
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

    explicit WallpaperPropertyModel(const QVariantMap &properties, QObject *parent = nullptr);

    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 返回第 i 行完整定义（含 key）；越界返回空 map。 */
    Q_INVOKABLE QVariantMap get(int i) const;
    /** 按 key 返回对应定义 map；不存在返回空 map。 */
    Q_INVOKABLE QVariantMap byKey(const QString &key) const;

private:
    QList<QVariantMap> m_rows;
    QHash<QString, int> m_indexByKey;
};
