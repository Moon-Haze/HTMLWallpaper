/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QStringList>

#include <QtQml/qqml.h>

#include "wallpapermodel.h"

/**
 * @brief HTML 壁纸配置的 C++ 门面（QML 类型 WallpaperController）。
 *
 * 供配置界面（config.qml → ScanPathsPanel → ThumbnailsPanel）消费的薄
 * Controller：只负责 scanPaths / selectWallpaper 属性管理 + scan() 一行转发 +
 * 转发 Model（WallpaperModel，后台线程自治扫描）的扫描信号。扫描/解析逻辑
 * 已全部下沉到数据层，本类不再持有任何扫描状态或类型过滤。
 *
 * 典型用法（QML）：
 *
 *     import com.github.moon_haze.htmlwallpaper
 *     WallpaperController { id: controller }
 *     controller.scanAll();  // 扫描 scanPaths → wallpapers 模型
 */
class WallpaperController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(WallpaperController)

    Q_PROPERTY(QString selectWallpaper READ selectWallpaper WRITE setSelectWallpaper NOTIFY selectWallpaperChanged)
    Q_PROPERTY(QStringList scanPaths READ scanPaths WRITE setScanPaths NOTIFY scanPathsChanged)

public:
    explicit WallpaperController(QObject *parent = nullptr);
    QString selectWallpaper() const;
    void setSelectWallpaper(const QString &wallpaper);
    QStringList scanPaths() const;
    void setScanPaths(const QStringList &urls);

    Q_INVOKABLE bool addScanPath(const QString &url);
    Q_INVOKABLE void removeScanPath(const QString &url);

Q_SIGNALS:
    void selectWallpaperChanged();
    void scanPathsChanged();
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    QString m_selectWallpaper;
    QStringList m_scanPaths;
};
