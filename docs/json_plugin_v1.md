# JSON 插件协议 v1

本项目只接受 JSON 插件。插件本身不执行脚本，只描述一个磁力搜索源的请求地址、响应格式和字段映射。

当前 v1 支持两类来源：

- `responseType: "json"`：搜索源返回 JSON API。
- `responseType: "html"`：搜索源返回 HTML，插件用正则提取结果。

当前实现只支持 `GET` 请求。

完整示范插件见 [example.json](example.json)。该文件用于说明协议，不会被当前应用自动加载。JSON 不能使用 `//` 或 `/* */` 注释，示范文件使用 `_comment` 字段写中文说明；当前解析器会忽略未知字段。

## 插件放置

当前版本加载随应用打包的内置插件：

```text
assets/plugins/*.json
```

现阶段注册表里仍是硬编码加载内置插件。后续会做本地导入、校验、启停和持久化管理。

## 顶层结构

```json
{
  "schemaVersion": 1,
  "id": "example",
  "name": "Example Source",
  "enabled": true,
  "baseUrl": "https://example.com",
  "headers": {
    "User-Agent": "Mozilla/5.0"
  },
  "search": {},
  "detail": {},
  "fields": {},
  "fileFields": {},
  "defaults": {}
}
```

字段说明：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `schemaVersion` | 否 | 协议版本，默认 `1`。 |
| `id` | 是 | 插件唯一 ID，建议小写英文、数字、短横线。 |
| `name` | 是 | UI 显示名称。 |
| `enabled` | 否 | 是否启用，默认 `true`。 |
| `baseUrl` | 是 | 相对 URL 的根地址。 |
| `headers` | 否 | 全局请求头，会和 endpoint 内的 `headers` 合并。 |
| `search` | 是 | 搜索 endpoint。 |
| `detail` | 否 | 详情 endpoint，用于获取文件列表或补全信息。 |
| `fields` | 是 | 资源字段映射。 |
| `fileFields` | 否 | 文件字段映射。 |
| `defaults` | 否 | 字段缺失时的模板默认值。 |

## 模板变量

`search.url` 支持：

| 变量 | 说明 |
| --- | --- |
| `{query}` | 搜索关键词。 |
| `{queryBase64}` | 搜索关键词的 UTF-8 URL-safe Base64，去掉末尾 `=`。用于磁力狗这类站点。 |
| `{page}` | 从 `1` 开始的页码。 |
| `{page0}` | 从 `0` 开始的页码。 |

`detail.url` 和 `defaults` 支持：

| 变量 | 说明 |
| --- | --- |
| `{sourceItemId}` | 搜索结果中的源站条目 ID。 |
| `{infoHash}` | 大写 info hash。 |
| `{infoHashLower}` | 小写 info hash。 |
| `{infoHashUpper}` | 大写 info hash。 |

变量会经过 `Uri.encodeComponent` 编码。

## Endpoint

`search` 和 `detail` 使用同一类结构。

```json
{
  "method": "GET",
  "url": "/api/search?q={query}&page={page}",
  "responseType": "json",
  "headers": {},
  "itemsPath": "data",
  "totalPath": "meta.total",
  "currentPagePath": "meta.current_page",
  "lastPagePath": "meta.last_page",
  "rootPath": "data",
  "filesPath": "files",
  "pageSize": 20
}
```

通用字段：

| 字段 | 说明 |
| --- | --- |
| `method` | 当前只支持 `GET`。 |
| `url` | 请求 URL。可写绝对 URL，也可写相对 `baseUrl` 的路径。 |
| `responseType` | `json` 或 `html`，默认 `json`。 |
| `headers` | 当前 endpoint 专用请求头。 |

JSON endpoint 字段：

| 字段 | 用于 | 说明 |
| --- | --- | --- |
| `itemsPath` | search | 搜索结果数组路径。 |
| `totalPath` | search | 总结果数路径。 |
| `currentPagePath` | search | 当前页路径。缺失时使用请求页码。 |
| `lastPagePath` | search | 最后一页路径。缺失时用 `total / pageSize` 推算。 |
| `pageSize` | search | 每页数量，默认 `20`。 |
| `rootPath` | detail | 详情对象路径。为空时使用响应根对象。 |
| `filesPath` | detail | 文件列表数组路径。 |

路径使用点号访问对象，例如 `meta.total`、`data.items`。数组可用数字下标，例如 `data.0.name`。

HTML endpoint 字段：

| 字段 | 用于 | 说明 |
| --- | --- | --- |
| `rootPattern` | search/detail | 可选。先用正则截取一个局部 HTML 范围；优先使用第 1 个捕获组。 |
| `itemPattern` | search/detail | 必填。匹配一个资源条目。 |
| `filePattern` | detail | 可选。匹配文件列表中的一个文件。 |
| `totalPattern` | search | 可选。匹配总结果数，使用第 1 个捕获组。 |
| `lastPagePattern` | search | 可选。匹配最后一页页码，使用第 1 个捕获组。 |

HTML 正则默认参数：

- `caseSensitive: false`
- `dotAll: true`
- `multiLine: true`

正则提取支持两种方式：

1. 命名捕获组：捕获组名使用字段路径最后一段，例如 `(?<infoHash>[A-Fa-f0-9]{40})`。
2. 顺序捕获组：如果没有命名捕获组，会按 `fields` 或 `fileFields` 中字段出现顺序依次取第 1、2、3... 个捕获组。

HTML 捕获值会做基础清理：

- 去掉 HTML 标签。
- 解码 `&amp;`、`&quot;`、`&#39;`、`&lt;`、`&gt;`。
- 合并空白字符。

## 资源字段 fields

`fields` 把应用内部字段映射到响应数据路径。

```json
{
  "sourceItemId": "id",
  "title": "name",
  "infoHash": "info_hash",
  "magnet": "magnet",
  "size": "size",
  "humanSize": "human_size",
  "seeders": "seeders",
  "leechers": "leechers",
  "score": "score",
  "health": "health",
  "verified": "verified",
  "largestFile": "largest_file",
  "webUrl": "url",
  "createdAt": "created_at",
  "lastSeen": "last_seen"
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `sourceItemId` | string | 源站详情 ID。缺失时使用 `infoHash`。 |
| `title` | string | 资源标题。 |
| `infoHash` | string | 建议提供。搜索列表可以先缺失，但详情页应补全它，才能复制 magnet。 |
| `magnet` | string | 磁力链接。可用 `defaults.magnet` 生成。 |
| `size` | int | 字节数。 |
| `humanSize` | string | 源站提供的人类可读大小，例如 `1.23 GB`。 |
| `seeders` | int | 做种/活跃指标。不同站点含义可能不同。 |
| `leechers` | int | 下载/请求指标。不同站点含义可能不同。 |
| `score` | double | 排序或热度分。 |
| `health` | double | 健康度。 |
| `verified` | bool | 是否验证。 |
| `largestFile` | string | 最大文件名。 |
| `webUrl` | string | 源站详情页。相对地址会基于 `baseUrl` 补全。 |
| `createdAt` | ISO date string | 创建时间。 |
| `lastSeen` | ISO date string | 最近发现时间。 |

## 文件字段 fileFields

详情页可返回文件列表。

```json
{
  "path": "path",
  "size": "size",
  "humanSize": "human_size"
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `path` | string | 文件路径或文件名。 |
| `size` | int | 字节数。 |
| `humanSize` | string | 人类可读大小。 |

## defaults

`defaults` 用于字段缺失时生成值。

```json
{
  "magnet": "magnet:?xt=urn:btih:{infoHashUpper}",
  "webUrl": "/torrent.html?hash={infoHashLower}"
}
```

常见用途：

- API 只返回 `infoHash`，用 `defaults.magnet` 生成 magnet。
- API 只返回 `infoHash`，用 `defaults.webUrl` 生成详情页链接。

## JSON API 示例

```json
{
  "schemaVersion": 1,
  "id": "example-api",
  "name": "Example API",
  "enabled": true,
  "baseUrl": "https://example.com",
  "search": {
    "method": "GET",
    "url": "/api/search?q={query}&page={page}",
    "responseType": "json",
    "itemsPath": "data.items",
    "totalPath": "data.total",
    "currentPagePath": "data.page",
    "lastPagePath": "data.lastPage"
  },
  "detail": {
    "method": "GET",
    "url": "/api/torrent/{infoHashLower}",
    "responseType": "json",
    "rootPath": "data",
    "filesPath": "files"
  },
  "fields": {
    "sourceItemId": "id",
    "title": "title",
    "infoHash": "hash",
    "size": "bytes",
    "seeders": "seeders",
    "leechers": "leechers",
    "createdAt": "createdAt"
  },
  "fileFields": {
    "path": "name",
    "size": "bytes"
  },
  "defaults": {
    "magnet": "magnet:?xt=urn:btih:{infoHashUpper}",
    "webUrl": "/torrent/{infoHashLower}"
  }
}
```

## HTML 正则示例

假设搜索结果 HTML 类似：

```html
<div class="item">
  <a href="/detail/abcdef">Example Title</a>
  <span class="hash">0123456789abcdef0123456789abcdef01234567</span>
  <span class="size">1.2 GB</span>
</div>
```

插件可写成：

```json
{
  "schemaVersion": 1,
  "id": "example-html",
  "name": "Example HTML",
  "enabled": true,
  "baseUrl": "https://example.com",
  "headers": {
    "User-Agent": "Mozilla/5.0"
  },
  "search": {
    "method": "GET",
    "url": "/search/{query}/{page}",
    "responseType": "html",
    "itemPattern": "<div class=\"item\">\\s*<a href=\"(?<sourceItemId>[^\"]+)\">(?<title>.*?)</a>\\s*<span class=\"hash\">(?<infoHash>[A-Fa-f0-9]{40})</span>\\s*<span class=\"size\">(?<humanSize>.*?)</span>\\s*</div>"
  },
  "detail": {
    "method": "GET",
    "url": "{sourceItemId}",
    "responseType": "html",
    "itemPattern": "<h1>(?<title>.*?)</h1>",
    "filePattern": "<li class=\"file\">(?<path>.*?)<span>(?<humanSize>.*?)</span></li>"
  },
  "fields": {
    "sourceItemId": "sourceItemId",
    "title": "title",
    "infoHash": "infoHash",
    "humanSize": "humanSize"
  },
  "fileFields": {
    "path": "path",
    "humanSize": "humanSize"
  },
  "defaults": {
    "magnet": "magnet:?xt=urn:btih:{infoHashUpper}",
    "webUrl": "{sourceItemId}"
  }
}
```

注意 JSON 字符串里的反斜杠要转义，例如正则 `\s` 要写成 `\\s`。

## 调试建议

1. 先用浏览器或 curl 确认搜索 URL 能访问。
2. JSON API 插件先填 `search` 和最少字段：`title`、`infoHash`。
3. HTML 插件先只写 `itemPattern`，确认能匹配列表，再补 `detail` 和 `filePattern`。
4. 如果站点只返回相对详情地址，放到 `sourceItemId`，再用 `detail.url: "{sourceItemId}"`。
5. 如果没有 magnet 字段，只要有 `infoHash`，就用 `defaults.magnet` 生成。

## 当前限制

- 只支持 `GET`。
- 没有 Cookie 登录流程。
- 没有 JavaScript 渲染能力，只处理 HTTP 返回的原始 JSON/HTML。
- HTML 解析目前基于正则，适合结构稳定、重复项明显的站点。
- 分页字段对 HTML 来源暂不自动识别，HTML 搜索结果默认 `currentPage = page`、`lastPage = page`。
- 当前应用只加载内置 assets 插件，本地导入还未实现。
