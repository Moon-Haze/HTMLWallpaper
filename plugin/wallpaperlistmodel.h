/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QVariantMap>

class WallpaperItem;

/**
 * @brief 扫描结果壁纸列表模型（HTMLBackend::wallpapers）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) / setProperty(i, key, value) 与 data()/setData() 组合。
 * roles 对齐 WallpaperDelegate / ThumbnailsComponent 使用的字段：
 * name / title / description / tags / type / visibility / workshopid / path /
 * entry / preview / display / source / checked。checked 写回经 setData 转发
 * 到 WallpaperItem 并发 dataChanged（网格勾选框即时刷新）。
 */
class WallpaperListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        TitleRole,
        DescriptionRole,
        TagsRole,
        TypeRole,
        VisibilityRole,
        WorkshopIdRole,
        PathRole,
        EntryRole,
        PreviewRole,
        DisplayRole,
        SourceRole,
        CheckedRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperListModel(QObject *parent = nullptr);

    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    bool setData(const QModelIndex &index, const QVariant &value, int role) override;
    QHash<int, QByteArray> roleNames() const override;

    /** 整体替换全部条目（扫描完成时主线程调用）；只发一次 reset + countChanged。 */
    void setEntries(const QList<QVariantMap> &metas);
    void clear();

    /** 兼容原 ListModel：返回第 i 项元数据对象（含 checked）。 */
    Q_INVOKABLE QObject *get(int i) const;
    /** 兼容原 ListModel：写回单个属性（当前支持 "checked"）。 */
    Q_INVOKABLE void setProperty(int i, const QString &property, const QVariant &value);

    /**
     * 单选互斥写回：勾选本项（checked=true）时自动取消其余所有项，
     * 保证至多一项被勾选；取消本项（checked=false）时仅取消本项，允许全不选。
     * index 越界直接返回。成功后发 dataChanged 刷新全表。
     */
    Q_INVOKABLE void setExclusiveChecked(int idx, bool checked);

Q_SIGNALS:
    void countChanged();

private:
    QList<WallpaperItem *> m_items;
};
