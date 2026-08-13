/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>
#include <QVariantMap>

#include "wallpaperproperty.h"

// 路径/URL/类型工具：同时被 WallpaperProject 内部与 htmlbackend.cpp 的
// scanPaths 归一化、scanWallpapers 后台 worker 复用，故导出为命名空间函数。
namespace WallpaperProjectJson
{
/** 归一化为带 scheme 的 URL：裸路径（"/usr/share/..."）补 file:// 前缀。 */
QString toUrl(const QString &path);
/** 去 a 尾部斜杠 + 去 b 前导斜杠后拼接。 */
QString pathJoin(const QString &a, const QString &b);
/**
 * 判断某 project.json 的 type 是否属于可加载的 HTML 类壁纸。
 * type 缺失或不在黑名单 → 视为 HTML（收录）；大小写不敏感。
 */
bool isHtmlType(const QString &type, const QStringList &nonHtmlTypes);
} // namespace WallpaperProjectJson

// ScanResult 在 WallpaperProject 类定义前引用 QList<WallpaperProject>，需前置声明。
class WallpaperProject;

/** 后台扫描的结果聚合（纯值，线程安全；主线程消费）。 */
struct ScanResult {
    QList<WallpaperProject> projects; // 解析结果
    QList<QPair<QString, QString>> failures; // (path, error)
};

/**
 * @brief 单个 HTML 壁纸的元数据（值类型，封装 project.json 解析）。
 *
 * 无 QObject、可拷贝/移动，后台线程可安全构造（scanWallpapers 在后台线程
 * 逐个构造）。默认构造对象 = 解析失败标记（isValid() == false）；显式构造
 * 时读 <dir>/project.json，文件缺失 / JSON 非法 / 非对象 → 保持空对象。
 *
 * 字段对齐 WallpaperItem 的 Q_PROPERTY 契约：
 *   - file：入口绝对 URL（project.json 的 file 字段，缺省 "index.html"，
 *     相对路径基于壁纸目录解析；指向的本地文件缺失时自动探测）；
 *   - source / display：file / title 的兼容别名；
 *   - preview：预览绝对 URL（缺失时自动探测常见预览图文件名）；
 *   - properties()：general.properties 解析 + 按 order 稳定排序后的属性表。
 */
class WallpaperProject
{
public:
    WallpaperProject() = default;
    explicit WallpaperProject(const QString &dirUrl);
    bool isValid() const;

    QString name() const;

    QString title() const;
    QString description() const;
    QString tags() const;
    QString type() const;
    QString visibility() const;
    QString workshopid() const;
    QString path() const;
    QString file() const;
    QString source() const;
    QString display() const;
    QString preview() const;
    bool monetization() const;
    QString contentrating() const;
    QString ratingsex() const;
    QString ratingviolence() const;
    int version() const;
    QString workshopurl() const;
    const QList<WallpaperProperty> &properties() const;
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
    QString m_contentrating;
    QString m_ratingsex;
    QString m_ratingviolence;
    QString m_workshopurl;
    QList<WallpaperProperty> m_properties;
    bool m_monetization = false;
    int m_version = 0;
    bool m_supportsaudioprocessing = false;
    bool m_supportsAudio = false;
    bool m_valid = false;
};
