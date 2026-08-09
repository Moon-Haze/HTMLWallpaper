/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariantMap>

#include "wallpaperpropertymodel.h"

/**
 * @brief 单个壁纸的元数据（HTMLBackend::currentWallpaper 与
 * WallpaperListModel::get(i) 的返回值）。
 *
 * 以 QObject 形式暴露，使 QML 里 `parser.currentWallpaper === null`（未解析
 * 时返回 nullptr）与 `currentWallpaper.title` 等属性访问都符合直觉。
 * file 是 project.json 的 file 字段（html 壁纸入口文件，绝对 URL），entry
 * 是它的兼容别名；display/source 是对齐 slideFilterModel 的只读别名
 * （display=title、source=entry），WallpaperDelegate 无需区分数据源即可渲染。
 * monetization / contentrating / ratingsex / ratingviolence / version /
 * workshopurl / supportsAudio 为 html-wallpapers 各壁纸 project.json 中的
 * 扩展元数据（部分壁纸缺失，缺省为 false / 空串 / 0）。
 * general 是 project.json 的 general 容器，以 WallpaperGeneral（QObject）
 * 形式暴露：内含 properties 可配置属性表与 supportsaudioprocessing 音频
 * 处理开关。generalProperties / supportsaudioprocessing 是其中两者的便捷
 * 别名（委托到 general 对象）。注意 supportsaudioprocessing（仅 general
 * 内原始值）区别于 supportsAudio（合并了顶层的 supportsAudio 字段）。
 */
class WallpaperItem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString description READ description CONSTANT)
    Q_PROPERTY(QString tags READ tags CONSTANT)
    Q_PROPERTY(QString type READ type CONSTANT)
    Q_PROPERTY(QString visibility READ visibility CONSTANT)
    Q_PROPERTY(QString workshopid READ workshopid CONSTANT)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString file READ file CONSTANT)
    Q_PROPERTY(QString preview READ preview CONSTANT)
    Q_PROPERTY(bool monetization READ monetization CONSTANT)
    Q_PROPERTY(QString contentrating READ contentrating CONSTANT)
    Q_PROPERTY(QString ratingsex READ ratingsex CONSTANT)
    Q_PROPERTY(QString ratingviolence READ ratingviolence CONSTANT)
    Q_PROPERTY(int version READ version CONSTANT)
    Q_PROPERTY(QString workshopurl READ workshopurl CONSTANT)
    Q_PROPERTY(WallpaperPropertyModel *properties READ properties CONSTANT)
    Q_PROPERTY(bool supportsaudioprocessing READ supportsaudioprocessing CONSTANT)
    Q_PROPERTY(bool supportsAudio READ supportsAudio CONSTANT)

public:
    explicit WallpaperItem(const QVariantMap &meta, QObject *parent = nullptr);

    QString name() const;
    QString title() const;
    QString description() const;
    QString tags() const;
    QString type() const;
    QString visibility() const;
    QString workshopid() const;
    QString path() const;
    QString file() const;
    QString preview() const;
    bool monetization() const;
    QString contentrating() const;
    QString ratingsex() const;
    QString ratingviolence() const;
    int version() const;
    QString workshopurl() const;
    const WallpaperPropertyModel *properties() const;
    bool supportsaudioprocessing() const;
    bool supportsAudio() const;

private:
    QString m_name;
    QString m_title;
    QString m_description;
    QString m_tags;
    QString m_type;
    QString m_visibility;
    QString m_workshopid;
    QString m_path;
    QString m_file;
    QString m_preview;
    bool m_monetization = false;
    QString m_contentrating;
    QString m_ratingsex;
    QString m_ratingviolence;
    int m_version = 0;
    QString m_workshopurl;
    bool m_supportsAudio = false;
    WallpaperPropertyModel m_properties;
    bool m_supportsaudioprocessing = false;
};
