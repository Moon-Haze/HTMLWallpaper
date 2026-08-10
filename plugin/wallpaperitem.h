/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>

#include "wallpaperproject.h"
#include "wallpaperpropertymodel.h"

/**
 * @brief 单个壁纸元数据的 QObject 门面（接口层，WallpaperListModel::get(i)
 * 的返回值，主线程构造）。
 *
 * 数据成员是 WallpaperProject 值类型（后台线程解析的产物），全部 Q_PROPERTY
 * 委托到它；属性表经 WallpaperPropertyModel 接口层暴露（构造时物化）。
 * source/display 是 file/title 的兼容别名（对齐 slideFilterModel 与
 * ThumbnailsView 的 get(i).source）。
 * monetization / contentrating / ratingsex / ratingviolence / version /
 * workshopurl / supportsAudio 为 html-wallpapers 各壁纸 project.json 中的
 * 扩展元数据（部分壁纸缺失，缺省为 false / 空串 / 0）。
 * supportsaudioprocessing（仅 general 内原始值）区别于 supportsAudio
 * （合并了顶层的 supportsAudio 字段）。
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
    Q_PROPERTY(QString source READ source CONSTANT)
    Q_PROPERTY(QString display READ display CONSTANT)
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
    explicit WallpaperItem(const WallpaperProject &project, QObject *parent = nullptr);

    QString name() const { return m_project.name(); }
    QString title() const { return m_project.title(); }
    QString description() const { return m_project.description(); }
    QString tags() const { return m_project.tags(); }
    QString type() const { return m_project.type(); }
    QString visibility() const { return m_project.visibility(); }
    QString workshopid() const { return m_project.workshopid(); }
    QString path() const { return m_project.path(); }
    QString file() const { return m_project.file(); }
    QString source() const { return m_project.source(); }
    QString display() const { return m_project.display(); }
    QString preview() const { return m_project.preview(); }
    bool monetization() const { return m_project.monetization(); }
    QString contentrating() const { return m_project.contentrating(); }
    QString ratingsex() const { return m_project.ratingsex(); }
    QString ratingviolence() const { return m_project.ratingviolence(); }
    int version() const { return m_project.version(); }
    QString workshopurl() const { return m_project.workshopurl(); }
    WallpaperPropertyModel *properties() { return &m_properties; }
    bool supportsaudioprocessing() const { return m_project.supportsaudioprocessing(); }
    bool supportsAudio() const { return m_project.supportsAudio(); }

private:
    WallpaperProject m_project;                  // 数据层（唯一数据来源）
    WallpaperPropertyModel m_properties{this};   // 接口层 ListModel，构造时 setEntries
};
