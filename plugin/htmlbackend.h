/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QStringList>

#include <QtQml/qqml.h>
#include <qcontainerfwd.h>

#include "wallpaperlistmodel.h"
#include "wallpaperentry.h" // ScanResult / WallpaperPath

// QML 类型注册（QML_ELEMENT / Q_OBJECT 的 moc）要求 Q_PROPERTY 指向的类型完整，
// 故上面直接 include 各模型头而非 forward 声明。m_watcher 用不完整类型指针即可。
template<typename T>
class QFutureWatcher;

/**
 * @brief 解析"html-wallpapers"格式 HTML 壁纸的 C++ 后端（QML 门面）。
 *
 * 等价替代原 QML 的 HtmlWallpaperParser.qml（扫描 project.json、提供壁纸
 * 列表模型），供配置界面（config.qml → ScanPathsPanel →
 * ThumbnailsView / WallpaperDelegate）消费。扫描/解析逻辑已解耦到
 * 数据层（WallpaperProject / WallpaperProperty，后台线程执行）；本类只
 * 负责 scanPaths 管理等属性 + scan() 异步调度 + 结果聚合。
 *
 * 目录约定（Wallpaper Engine 风格）：
 *
 *     <根目录>/<壁纸名>/
 *         ├── project.json   —— 元数据 + 可配置属性
 *         ├── index.html     —— 入口页面（"file" 字段可覆盖）
 *         └── preview.*      —— 预览图（"preview" 字段相对路径，缺省自动探测）
 *
 * 典型用法（QML）：
 *
 *     import com.github.moon_haze.htmlwallpaper
 *     HTMLBackend { id: parser }
 *     parser.scan();  // 扫描 scanPaths → wallpapers 模型（delegate 走 roles，
 *                     // ThumbnailsView 走 get(i).source，PropertyPanel 未来
 *                     // 走 get(i).properties.get(j)/byKey）
 */
class HTMLBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(HTMLBackend)

    Q_PROPERTY(QString selectWallpaper READ selectWallpaper WRITE setSelectWallpaper NOTIFY selectWallpaperChanged)
    /**
     * 待扫描的壁纸根目录（可多个）。默认匹配 main.xml 中 ScanPaths 的默认值。
     * QML 里是字符串数组，可直接作 ListView 的 model（delegate 用 modelData）。
     * 修改时不自动重扫，由 QML 层 onScanPathsChanged 触发 scan。
     */
    Q_PROPERTY(QStringList scanPaths READ scanPaths WRITE setScanPaths NOTIFY scanPathsChanged)
    /**
     * 是否按类型过滤扫描结果。true 时只收录 HTML 类壁纸（web/color/group 等），
     * 明确非 HTML 的（video/scene/application/audio）过滤掉；type 缺失时按 HTML 处理。
     */
    Q_PROPERTY(bool requireWebType READ requireWebType WRITE setRequireWebType NOTIFY requireWebTypeChanged)
    /** 明确非 HTML 的 Wallpaper Engine 类型黑名单（对应旧 _nonHtmlTypes）。 */
    Q_PROPERTY(QStringList nonHtmlTypes READ nonHtmlTypes WRITE setNonHtmlTypes NOTIFY nonHtmlTypesChanged)
    /** 扫描流程进行中标志（避免重复触发 scan()）。 */
    Q_PROPERTY(bool scanInProgress READ scanInProgress NOTIFY scanInProgressChanged)
    /** 扫描结果：壁纸列表模型，可直接作 GridView/ListView 的 model。 */
    Q_PROPERTY(WallpaperListModel *wallpapers READ wallpapers CONSTANT)

public:
    explicit HTMLBackend(QObject *parent = nullptr);
    QString selectWallpaper() const;
    void setSelectWallpaper(const QString &wallpaper);
    QStringList scanPaths() const;
    void setScanPaths(const QStringList &paths);
    bool requireWebType() const;
    void setRequireWebType(bool requireWebType);
    QStringList nonHtmlTypes() const;
    void setNonHtmlTypes(const QStringList &nonHtmlTypes);
    bool scanInProgress() const;
    WallpaperListModel *wallpapers() const;

    // —— 扫描入口 ——
    /** 顺序扫描 scanPaths，把各根下的合法壁纸填入 wallpapers；完成后发 scanFinished。 */
    Q_INVOKABLE void scan();
    /** 增加一个扫描根目录；重复路径忽略，返回是否新增成功。 */
    Q_INVOKABLE bool addScanPath(const QString &path);
    /** 移除一个扫描根目录。 */
    Q_INVOKABLE void removeScanPath(const QString &path);

Q_SIGNALS:
    void selectWallpaperChanged();
    /** 扫描全部完成（可能部分子目录解析失败，已在日志警告）。 */
    void scanFinished();
    /** 某个根目录无法读取时发出（path：根目录 url，error：底层错误字符串）。 */
    void scanFailed(const QString &path, const QString &error);
    void scanPathsChanged();
    void requireWebTypeChanged();
    void nonHtmlTypesChanged();
    void scanInProgressChanged();

private:
    void setScanInProgress(bool inProgress);

    QString m_selectWallpaper;
    QStringList m_scanPaths;
    QStringList m_nonHtmlTypes{QStringLiteral("video"), QStringLiteral("scene"), QStringLiteral("application"), QStringLiteral("audio")};
    bool m_requireWebType = true;
    bool m_scanning = false;
    WallpaperListModel *m_wallpapers = nullptr;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
