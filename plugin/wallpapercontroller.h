/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QFutureWatcher>
#include <QList>
#include <QObject>
#include <QStringList>

#include <QtQml/qqml.h>

#include "wallpaperentry.h"
#include "wallpapermodel.h"

/**
 * @brief HTML 壁纸配置的 C++ 门面（QML 类型 WallpaperController）。
 *
 * 供配置界面（config.qml → ScanPathsPanel → ThumbnailsPanel）消费的
 * Controller：持有 scanPaths / selectWallpaper / activeModel 属性与扫描编排，
 * 并为每个扫描根缓存一个单文件夹 WallpaperModel（QList<WallpaperModel *> m_models）。
 *
 * - modelFor(url)：url 对应文件夹的常驻 WallpaperModel*（key 归一化去重建）。
 * - allModel()：懒建的"全部"汇总 WallpaperModel（key = "ALL"），scan 后
 *   clear 重填全部文件夹条目（保活复用，无悬空指针）。
 * - activeModel：当前活动壁纸集合（ScanPathsPanel 点击驱动）——单文件夹时
 *   指向对应 WallpaperModel*，"全部"时指向 allModel() 的汇总 model。
 * - scan()：后台一次扫所有 scanPaths，逐组 setEntries 到对应文件夹 model，
 *   并 addEntries 汇总到 allModel()。
 */
class WallpaperController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(WallpaperController)

    Q_PROPERTY(QString selectWallpaper READ selectWallpaper WRITE setSelectWallpaper NOTIFY selectWallpaperChanged)
    Q_PROPERTY(QStringList scanPaths READ scanPaths WRITE setScanPaths NOTIFY scanPathsChanged)
    Q_PROPERTY(bool scanInProgress READ scanInProgress NOTIFY scanInProgressChanged)
    // 当前活动壁纸集合（单文件夹或"全部"汇总 WallpaperModel*）
    Q_PROPERTY(WallpaperModel *activeModel READ activeModel WRITE setActiveModel NOTIFY activeModelChanged)
    Q_PROPERTY(int activeIndex READ activeIndex WRITE setActiveIndex NOTIFY activeIndexChanged)

public:
    explicit WallpaperController(QObject *parent = nullptr);

    QString selectWallpaper() const;
    void setSelectWallpaper(const QString &paper);

    int activeIndex() const;
    void setActiveIndex(int index);

    QStringList scanPaths() const;
    void setScanPaths(const QStringList &urls);
    bool scanInProgress() const;
    /** 当前活动壁纸集合（nullptr = 尚未设置；由 ScanPathsPanel 点击驱动）。 */
    WallpaperModel *activeModel() const;
    void setActiveModel(WallpaperModel *model);
    /** 已缓存的文件夹 model 数（测试/调试用）。QML 读作方法调用 modelCount()。 */
    Q_INVOKABLE int modelCount() const;

    Q_INVOKABLE void scan();
    Q_INVOKABLE bool addScanPath(const QString &url);
    Q_INVOKABLE void removeScanPath(const QString &url);
    /** 返回 url 对应文件夹的常驻 WallpaperModel*；不存在即新建（key 归一化）。 */
    Q_INVOKABLE WallpaperModel *modelFor(const QString &url);
    /** 返回懒建的"全部"汇总 model；scan 时 clear 重填全部文件夹条目。 */
    Q_INVOKABLE WallpaperModel *allModel();
    /** 扫描根 URL → 显示用文件夹名（去末尾斜杠后取最后一段）。 */
    Q_INVOKABLE QString folderName(const QString &url) const;
    /** 扫描根 URL → 父目录路径（去末尾斜杠后去掉最后一段；根路径返回空）。 */
    Q_INVOKABLE QString parentPath(const QString &url) const;

Q_SIGNALS:
    void selectWallpaperChanged();
    void scanPathsChanged();
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();
    void activeModelChanged();
    void activeIndexChanged();

private:
    WallpaperModel *obtainModel(const QString &url); // modelFor 的实现：创建/复用
    void releaseStaleModels(const QStringList &kept); // 销毁不在 kept 的 model
    void setScanInProgress(bool inProgress);

    QStringList m_scanPaths;

    QList<WallpaperModel *> m_models;

    WallpaperModel *m_allModel = new WallpaperModel(QStringLiteral("ALL"), this); // 懒建"全部"汇总 model（保活复用）
    WallpaperModel *m_activeModel = m_allModel; // 当前活动壁纸集合（防悬空见 releaseStaleModels）

    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
