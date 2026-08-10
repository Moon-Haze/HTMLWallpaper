/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>

#include "wallpaperproject.h"

class WallpaperItem;

/**
 * @brief 扫描结果壁纸列表模型（HTMLBackend::wallpapers，列表层）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) 与 data()。roles 对齐 WallpaperDelegate / ThumbnailsView
 * 使用的字段：name / title / description / tags / type / visibility / workshopid /
 * path / preview / file / ...（file 是 project.json 的 file 字段，经
 * WallpaperProject 探测兜底）。另含 project.json 扩展元数据 role：
 * monetization / contentrating / ratingsex / ratingviolence / version /
 * workshopurl / supportsAudio（对齐 WallpaperItem）。
 * setEntries(QList<WallpaperProject>) 主线程物化 WallpaperItem*（QObject）。
 */
class WallpaperListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)

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
        PreviewRole,
        MonetizationRole,
        ContentRatingRole,
        RatingSexRole,
        RatingViolenceRole,
        VersionRole,
        WorkshopUrlRole,
        SupportsAudioRole,
        FileRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperListModel(QObject *parent = nullptr);

    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    bool setData(const QModelIndex &index, const QVariant &value, int role) override;
    QHash<int, QByteArray> roleNames() const override;

    /** 整体替换全部条目（扫描完成时主线程调用）；只发一次 reset + countChanged。 */
    void setEntries(const QList<WallpaperProject> &projects);
    void clear();

    /** 兼容原 ListModel：返回第 i 项元数据对象（含 checked）。 */
    Q_INVOKABLE QObject *get(int i) const;

private:
    QList<WallpaperItem *> m_items;
};
