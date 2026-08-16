# CLAUDE.md

## C++ 代码注释规范

本项目的 C++ 代码（`plugin/` 下所有 `.h`/`.cpp`）注释必须遵循以下结构化 Doxygen 规范。QML 侧（`package/` 下 `.qml`）沿用项目既有中文行内注释习惯，不在本规范约束内。

### 1. 注释结构：必须使用多行结构化格式

- `/**` 单独占一行，`@brief` 位于其下一行，`*/` 单独收尾。
- **禁止**单行简写 `/** @brief ... */`。

```cpp
/**
 * @brief 以扫描根 key 构造单文件夹模型。
 * @param key    本文件夹归一化 URL（归一化规则与
 *               WallpaperController::modelFor 一致）。
 * @param parent Qt 父对象（controller 持有的 model 传 controller）。
 */
explicit WallpaperModel(const QString &key, QObject *parent = nullptr);
```

### 2. 标签使用规则

| 场景                               | 必填标签                                             |
| ---------------------------------- | ---------------------------------------------------- |
| 任何函数/方法                      | `@brief`                                             |
| 函数有参数                         | 每个参数各一个 `@param <参数名>`（名称须与签名一致） |
| 函数有返回值                       | `@return`（**void 或构造函数除外**）                 |
| 补充说明（边界、副作用、调用约定） | `@note`                                              |
| 模板函数/成员                      | `@tparam R`（模板参数名）                            |
| 类 / 结构体 / 命名空间 / 信号      | `@brief`；信号带参数时补 `@param`                    |

### 3. 多参数对齐

多个 `@param` 时参数名右对齐，描述说明从同一列开始（见上例 `key` 与 `parent` 描述对齐到同一列）。

### 4. 返回值与参数描述要具体

- 必须写明具体返回语义与**边界情况**：如"越界返回空串""无选中返回空串""-1 = 无选中""越界忽略"。
- `@param` 描述参数用途，不重复类型。

### 5. 私有成员变量必须注释

- 一行能说清的用行尾注释：`QStringList m_scanPaths; // 待扫描的根目录 URL 列表`
- 需多行说明的用结构化块注释（`@brief` + `@note`）。

### 6. 文件头：保留 SPDX 许可头与 `@file` 块

- 每个文件顶部保留 `SPDX-FileCopyrightText` / `SPDX-License-Identifier`（GPL-2.0-or-later，REUSE 合规要求），**不得删改**。
- `@file 文件名` 块用一到三行概括该文件职责。

### 7. `.cpp` 实现注释用 `//` 说明"为什么"

头文件写"是什么/边界"，实现文件用行注释解释"为什么这样做"（如 reset 通知、防御性边界检查、线性查找用途）。

### 8. 模板函数示例

```cpp
/**
 * @brief 返回第 i 项在角色 R 下的字符串字段（模板版，无对象开销）。
 * @tparam R 取值角色（见 Roles 枚举）。
 * @param i 行号。
 * @return 对应字段字符串；越界返回空串。
 */
template<Roles R>
QString get(int i) const;
```

### 格式基准文件

格式的对齐基准为 [plugin/wallpapermodel.h](plugin/wallpapermodel.h)：多参数右对齐、`@tparam`、私有成员结构化注释均以此文件为准。
