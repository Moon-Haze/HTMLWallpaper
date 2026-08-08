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

#include "htmlpropertyitem.h"
#include "wallpaperitem.h"
#include "wallpaperlistmodel.h"

// QML 类型注册（QML_ELEMENT / Q_OBJECT 的 moc）要求 Q_PROPERTY 指向的类型完整，
// 故上面直接 include 各模型头而非 forward 声明。m_watcher 用不完整类型指针即可。
template <typename T>
class QFutureWatcher;
struct HTMLBackendScanResult;

/**
 * @brief 解析“html-wallpapers”格式 HTML 壁纸的 C++ 后端。
 *
 * 等价替代原 QML 的 HtmlWallpaperParser.qml（扫描 project.json、提供壁纸
 * 列表模型、解析可配置属性、序列化属性、求值 condition），供配置界面
 * （config.qml → SlideshowComponent → ThumbnailsComponent / PropertyPanel
 * / WallpaperDelegate）消费。API 表面与旧解析器保持一致，QML 消费方仅需
 * 把 import 语句与类型名改为 HTMLBackend。
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
 *     parser.parseWallpaper(selectedPath)  // 解析单壁纸 → currentWallpaper/currentProperties
 */
class HTMLBackend : public QObject {
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
    Q_PROPERTY(WallpaperListModel* wallpapers READ wallpapers CONSTANT)
    /** 最近一次 parseWallpaper() 的解析结果元数据；尚未解析/无 project.json 时为 null。 */
    Q_PROPERTY(WallpaperItem* currentWallpaper READ currentWallpaper WRITE setCurrentWallpaper NOTIFY currentWallpaperChanged)
    /** 当前壁纸的可配置属性列表（按 order 排序）。元素为 HTMLPropertyItem（可写回）。 */
    Q_PROPERTY(QVariantList currentProperties READ currentProperties NOTIFY currentPropertiesChanged)

public:
    explicit HTMLBackend(QObject* parent = nullptr);

    QStringList rootPaths() const;
    void setRootPaths(const QStringList& paths);
    bool requireWebType() const;
    void setRequireWebType(bool requireWebType);
    QStringList nonHtmlTypes() const;
    void setNonHtmlTypes(const QStringList& nonHtmlTypes);
    bool scanInProgress() const;
    WallpaperListModel* wallpapers() const;
    WallpaperItem* currentWallpaper() const;
    void setCurrentWallpaper(WallpaperItem* currentWallpaper);
    QVariantList currentProperties() const;

    // —— 扫描 / 解析入口 ——
    /** 顺序扫描 rootPaths，把各根下的合法壁纸填入 wallpapers；完成后发 scanFinished。 */
    Q_INVOKABLE void scan();
    /** 解析单个壁纸目录 → currentWallpaper / currentProperties，完成后发 wallpaperParsed。 */
    Q_INVOKABLE void parseWallpaper(const QString& path);
    /** 增加一个扫描根目录；重复路径忽略，返回是否新增成功。 */
    Q_INVOKABLE bool addScanPath(const QString& path);
    /** 移除一个扫描根目录。 */
    Q_INVOKABLE void removeScanPath(const QString& path);

    // —— 属性序列化 / 协议辅助（UI 层调用）——
    /** 把 currentProperties 序列化成 query string（?k=v&...）；color 转 #RRGGBB；空值跳过。 */
    Q_INVOKABLE QString buildQueryString() const;
    /** 把 currentProperties 序列化成 { key: value } JSON 字符串（push applyUserProperties 用）。 */
    Q_INVOKABLE QString buildPropertiesJson() const;
    /** 把当前属性拼到入口 HTML 的 URL 上（页面可读 location.search）。 */
    Q_INVOKABLE QString applyPropertiesToUrl(const QString& baseUrl) const;
    /** Wallpaper Engine 颜色值 "R G B"（各 0~1）→ "#RRGGBB"；非字符串/非法输入返回黑。 */
    Q_INVOKABLE QString colorToHex(const QVariant& value) const;
    /** 求值 condition 表达式（如 "theme.value === 'custom'"）；空/异常宽松返回 true。 */
    Q_INVOKABLE bool evaluateCondition(const QVariant& condition, const QVariantMap& props);
    /** 把 currentProperties 按组分类，返回 [{ group, title, items }]（items 为 HTMLPropertyItem*）。 */
    Q_INVOKABLE QVariantList propertyGroups() const;

    // —— 解析内部函数（测试与复用暴露；语义与旧 QML 同名私有函数一致）——
    // 返回 QVariant 而非 QVariantMap：requireWebType 过滤命中时返回 JS null
    // （旧 QML 返回 null；空 QVariantMap 在 QML 里是 {} 而非 null，测试断言 === null）。
    Q_INVOKABLE QVariant _parseMetadata(const QString& dirUrl, const QVariantMap& data);
    Q_INVOKABLE void _parseProperties(const QVariantMap& properties);
    Q_INVOKABLE QString _pathJoin(const QString& a, const QString& b) const;
    Q_INVOKABLE QString _basename(const QString& url) const;

Q_SIGNALS:
    /** 扫描全部完成（可能部分子目录解析失败，已在日志警告）。 */
    void scanFinished();
    /** 解析单个壁纸完成；参数为元数据对象。 */
    void wallpaperParsed(WallpaperItem* metadata);
    /** 某个根目录无法读取时发出（path：根目录 url，error：底层错误字符串）。 */
    void scanFailed(const QString& path, const QString& error);
    void rootPathsChanged();
    void requireWebTypeChanged();
    void nonHtmlTypesChanged();
    void scanInProgressChanged();
    void currentWallpaperChanged();
    void currentPropertiesChanged();

private:
    void parsePropertiesIntoItems(const QVariantMap& properties);
    void setScanInProgress(bool inProgress);

    QStringList m_rootPaths;
    QStringList m_nonHtmlTypes { QStringLiteral("video"), QStringLiteral("scene"),
        QStringLiteral("application"), QStringLiteral("audio") };
    bool m_requireWebType = true;
    bool m_scanning = false;
    QList<HTMLPropertyItem*> m_properties;
    WallpaperItem* m_currentWallpaper = nullptr;
    WallpaperListModel* m_wallpapers = nullptr;
    QFutureWatcher<HTMLBackendScanResult>* m_watcher = nullptr;
    QJSEngine m_engine;
};
