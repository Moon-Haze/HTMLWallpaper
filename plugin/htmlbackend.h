/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QJSEngine>
#include <QObject>
#include <QStringList>
#include <QVariantList>

#include <QtQml/qqml.h>

#include "wallpaperlistmodel.h"

// QML 类型注册（QML_ELEMENT / Q_OBJECT 的 moc）要求 Q_PROPERTY 指向的类型完整，
// 故上面直接 include 各模型头而非 forward 声明。m_watcher 用不完整类型指针即可。
template<typename T>
class QFutureWatcher;
struct HTMLBackendScanResult;

/**
 * @brief 解析“html-wallpapers”格式 HTML 壁纸的 C++ 后端。
 *
 * 等价替代原 QML 的 HtmlWallpaperParser.qml（扫描 project.json、提供壁纸
 * 列表模型、求值 condition、颜色换算），供配置界面（config.qml →
 * SlideshowComponent → ThumbnailsComponent / PropertyPanel / WallpaperDelegate）
 * 消费。可配置属性表（general.properties）以只读 ListModel（WallpaperPropertyModel）
 * 形式暴露在 WallpaperItem::general.properties 上，属性值不存储、不序列化、
 * 不应用到壁纸（改值只在 QML 会话内临时生效）。
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
 *     parser.scan();                       // 扫描 rootPaths → wallpapers 模型
 *     parser.parseWallpaper(selectedPath)  // 解析单壁纸 → currentWallpaper
 */
class HTMLBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(HTMLBackend)

    /**
     * 待扫描的壁纸根目录（可多个）。默认匹配 main.xml 中 SlidePaths 的默认值。
     * QML 里是字符串数组，可直接作 ListView 的 model（delegate 用 modelData）。
     * 修改时不自动重扫，由 QML 层 onRootPathsChanged 触发 scan。
     */
    Q_PROPERTY(QStringList rootPaths READ rootPaths WRITE setRootPaths NOTIFY rootPathsChanged)
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

    QStringList rootPaths() const;
    void setRootPaths(const QStringList &paths);
    bool requireWebType() const;
    void setRequireWebType(bool requireWebType);
    QStringList nonHtmlTypes() const;
    void setNonHtmlTypes(const QStringList &nonHtmlTypes);
    bool scanInProgress() const;
    WallpaperListModel *wallpapers() const;

    // —— 扫描 / 解析入口 ——
    /** 顺序扫描 rootPaths，把各根下的合法壁纸填入 wallpapers；完成后发 scanFinished。 */
    Q_INVOKABLE void scan();
    /** 增加一个扫描根目录；重复路径忽略，返回是否新增成功。 */
    Q_INVOKABLE bool addScanPath(const QString &path);
    /** 移除一个扫描根目录。 */
    Q_INVOKABLE void removeScanPath(const QString &path);

Q_SIGNALS:
    /** 扫描全部完成（可能部分子目录解析失败，已在日志警告）。 */
    void scanFinished();
    /** 解析单个壁纸完成；参数为元数据对象。 */
    void wallpaperParsed(WallpaperItem *metadata);
    /** 某个根目录无法读取时发出（path：根目录 url，error：底层错误字符串）。 */
    void scanFailed(const QString &path, const QString &error);
    void rootPathsChanged();
    void requireWebTypeChanged();
    void nonHtmlTypesChanged();
    void scanInProgressChanged();
    void currentWallpaperChanged();

private:
    void setScanInProgress(bool inProgress);

    QStringList m_rootPaths;
    QStringList m_nonHtmlTypes{QStringLiteral("video"), QStringLiteral("scene"), QStringLiteral("application"), QStringLiteral("audio")};
    bool m_requireWebType = true;
    bool m_scanning = false;
    WallpaperListModel *m_wallpapers = nullptr;
    QFutureWatcher<HTMLBackendScanResult> *m_watcher = nullptr;
    QJSEngine m_engine;
};
