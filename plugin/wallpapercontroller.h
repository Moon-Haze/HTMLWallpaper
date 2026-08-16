/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/** @file wallpapercontroller.h
 * HTML 壁纸配置的 C++ 门面（QML 类型 WallpaperController）声明。
 * 持有扫描编排、扫描根缓存与"全部"汇总 model，供配置界面消费。
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
    /**
     * @brief 构造空 controller。
     * @param parent Qt 父对象。
     * @note 初始 activeModel 指向懒建的 allModel()（始终非 nullptr）。
     */
    explicit WallpaperController(QObject *parent = nullptr);

    /**
     * @brief 当前选中壁纸的 file（activeModel 选中行的 FileRole；无选中返回空串）。
     * @return 选中壁纸的 file URL；无选中返回空串。
     */
    QString selectWallpaper() const;
    /**
     * @brief 按 file 定位 activeModel 的选中行（未命中忽略）。
     * @param paper 目标壁纸的 file URL。
     */
    void setSelectWallpaper(const QString &paper);

    /**
     * @brief 当前活动 model 的选中行（activeModel 为空返回 -1）。
     * @return 选中行行号；-1 = 无选中。
     */
    int activeIndex() const;
    /**
     * @brief 设置当前活动 model 的选中行（越界忽略）。
     * @param index 目标行号（-1 表示清空选中）。
     */
    void setActiveIndex(int index);

    /**
     * @brief 待扫描的根目录 URL 列表。
     * @return 扫描根 URL 列表。
     */
    QStringList scanPaths() const;
    /**
     * @brief 整体替换待扫描根目录列表（触发 scanPathsChanged）。
     * @param urls 新的扫描根 URL 列表。
     */
    void setScanPaths(const QStringList &urls);
    /**
     * @brief 是否正在后台扫描（scan() 置位、完成后复位）。
     * @return true 扫描进行中 / false 空闲。
     */
    bool scanInProgress() const;
    /**
     * @brief 当前活动壁纸集合（由 ScanPathsPanel 点击驱动）。
     * @return 单文件夹 model 或 allModel() 的汇总 model；未设置时指向
     *         allModel()，不会返回 nullptr（防悬空见 releaseStaleModels）。
     */
    WallpaperModel *activeModel() const;
    /**
     * @brief 切换当前活动壁纸集合（等值忽略；切换后按序 emit 关联信号）。
     * @param model 新的活动 model（应为已缓存文件夹 model 或 allModel()）。
     */
    void setActiveModel(WallpaperModel *model);
    /**
     * @brief 已缓存的文件夹 model 数（测试/调试用）。
     * @return m_models 中常驻的文件夹 model 个数。
     * @note QML 中读作方法调用 modelCount()。
     */
    Q_INVOKABLE int modelCount() const;

    /**
     * @brief 后台全量扫描所有 scanPaths，结果写回各文件夹 model 与 allModel()。
     * @note 已在扫描中则直接返回；完成后 emit scanFinished（含各 scanFailed）。
     */
    Q_INVOKABLE void scan();
    /**
     * @brief 追加一个扫描根（已存在返回 false，不重复添加）。
     * @param url 待追加的扫描根 URL。
     * @return true 追加成功 / false 已存在。
     */
    Q_INVOKABLE bool addScanPath(const QString &url);
    /**
     * @brief 移除一个扫描根（不存在则无操作）。
     * @param url 待移除的扫描根 URL。
     */
    Q_INVOKABLE void removeScanPath(const QString &url);
    /**
     * @brief 返回 url 对应文件夹的常驻 WallpaperModel*；不存在即新建（key 归一化）。
     * @param url 扫描根 URL。
     * @return 对应文件夹 model（新建或缓存复用）。
     */
    Q_INVOKABLE WallpaperModel *modelFor(const QString &url);
    /**
     * @brief 返回懒建的"全部"汇总 model；scan 时 clear 重填全部文件夹条目。
     * @return "全部"标签对应的汇总 model（始终非空，保活复用）。
     */
    Q_INVOKABLE WallpaperModel *allModel();
    /**
     * @brief 扫描根 URL → 显示用文件夹名（去末尾斜杠后取最后一段）。
     * @param url 扫描根 URL。
     * @return 文件夹名；URL 只含根斜杠时返回空串。
     */
    Q_INVOKABLE QString folderName(const QString &url) const;
    /**
     * @brief 扫描根 URL → 父目录路径（去末尾斜杠后去掉最后一段；根路径返回空）。
     * @param url 扫描根 URL。
     * @return 父目录路径；已是根路径时返回空串。
     */
    Q_INVOKABLE QString parentPath(const QString &url) const;

Q_SIGNALS:
    /**
     * @brief 选中壁纸变化（selectWallpaper 属性变更）。
     */
    void selectWallpaperChanged();
    /**
     * @brief 扫描根列表变化（scanPaths 属性变更）。
     */
    void scanPathsChanged();
    /**
     * @brief 一次 scan() 完成（全部结果已写回模型）。
     */
    void scanFinished();
    /**
     * @brief 某个扫描根失败。
     * @param path  扫描根 URL。
     * @param error 错误信息。
     */
    void scanFailed(const QString &path, const QString &error);
    /**
     * @brief 扫描进行状态翻转（scanInProgress 属性变更）。
     */
    void scanInProgressChanged();
    /**
     * @brief 当前活动壁纸集合切换。
     */
    void activeModelChanged();
    /**
     * @brief 当前活动选中行变化。
     */
    void activeIndexChanged();

private:
    /**
     * @brief modelFor 的实现：按归一化 key 在缓存中查找，未命中则新建并缓存。
     * @param url 扫描根 URL（函数内部归一化）。
     * @return 对应文件夹 model（新建或缓存复用）。
     */
    WallpaperModel *obtainModel(const QString &url);
    /**
     * @brief 销毁不在 kept（仍保留的扫描根）缓存中的 model，防内存泄漏。
     * @param kept 应保留的扫描根 URL 列表。
     */
    void releaseStaleModels(const QStringList &kept);
    /**
     * @brief 置位/复位扫描状态并 emit scanInProgressChanged（等值忽略）。
     * @param inProgress 新的扫描状态。
     */
    void setScanInProgress(bool inProgress);

    QStringList m_scanPaths; // 待扫描的根目录 URL 列表

    QList<WallpaperModel *> m_models; // 每个扫描根一个常驻文件夹 model（key 唯一）

    WallpaperModel *m_allModel = new WallpaperModel(QStringLiteral("ALL"), this); // 懒建"全部"汇总 model（保活复用）
    WallpaperModel *m_activeModel = m_allModel; // 当前活动壁纸集合（防悬空见 releaseStaleModels）

    bool m_scanning = false; // 是否正在后台扫描
    QFutureWatcher<ScanResult> *m_watcher = nullptr; // 扫描结果 watcher（懒建，复用）
};
