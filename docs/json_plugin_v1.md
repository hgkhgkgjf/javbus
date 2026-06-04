# JSON 插件协议 v1

JAVBUS 的磁力搜索源只接受 JSON 插件。插件不执行脚本，只描述一个站点的请求地址、响应格式、字段映射和少量能力标记。

当前 v1 支持：

- `responseType: "json"`：搜索源返回 JSON API。
- `responseType: "html"`：搜索源返回 HTML，插件用正则提取结果。
- 只支持 `GET` 请求。
- 支持搜索页和详情页。
- 支持 Cloudflare 等人机验证站点的 WebView 手动验证流程。

完整示例见 [example.json](example.json)。JSON 不能写 `//` 或 `/* */` 注释，示例使用 `_comment` 字段说明；解析器会忽略未知顶层字段。不要把注释字段放进 `headers`，否则会被当作真实 HTTP Header 发送。

## 安装与管理

当前应用不内置任何插件，插件需要用户自行安装。入口：

```text
设置 -> 插件目录
```

支持三种安装方式：

- 粘贴 JSON：直接粘贴插件文本。
- 选择 JSON 文件：本地选择 `.json` 文件。
- 从 URL 安装：输入以 `.json` 结尾的 URL，应用下载后安装。

插件会保存到应用用户数据目录下的 `plugins` 子目录。文件名由 `id` 清理后生成，例如 `my-source.json`。如果编辑插件时修改了 `id`，旧文件会被删除并写入新文件。

## 顶层结构

```json
{
  "schemaVersion": 1,
  "id": "example-html",
  "name": "Example HTML Source",
  "enabled": true,
  "baseUrl": "https://example.com",
  "capabilities": {
    "requiresHumanVerification": false
  },
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

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `schemaVersion` | 否 | 协议版本，默认 `1`。 |
| `id` | 是 | 插件唯一 ID。建议小写英文、数字、短横线或下划线。 |
| `name` | 是 | UI 显示名称。 |
| `enabled` | 否 | 是否启用，默认 `true`。 |
| `baseUrl` | 是 | 根地址。相对 URL 会基于它补全。必须是完整 URL。 |
| `capabilities` | 否 | 插件能力标记。当前支持 `requiresHumanVerification`。 |
| `headers` | 否 | 全局请求头，会和 endpoint 内的 `headers` 合并。 |
| `search` | 是 | 搜索 endpoint。 |
| `detail` | 否 | 详情 endpoint，用于补全 magnet、infoHash、文件列表等。 |
| `fields` | 是 | 资源字段映射。 |
| `fileFields` | 否 | 文件列表字段映射。 |
| `defaults` | 否 | 字段缺失时的默认模板。 |

## capabilities

```json
{
  "requiresHumanVerification": true
}
```

| 字段 | 说明 |
| --- | --- |
| `requiresHumanVerification` | 如果站点可能触发 Cloudflare 等人机验证，设为 `true`。应用遇到疑似挑战页时会弹出 WebView，让用户手动验证，并保存同 host 的 Cookie 供后续请求使用。 |

如果站点不需要验证，保持 `false` 或省略 `capabilities`。

## 模板变量

`search.url` 支持：

| 变量 | 说明 |
| --- | --- |
| `{query}` | 搜索关键词。 |
| `{queryBase64}` | 搜索关键词的 UTF-8 URL-safe Base64，去掉末尾 `=`。 |
| `{page}` | 从 `1` 开始的页码。 |
| `{page0}` | 从 `0` 开始的页码。 |

`detail.url` 和 `defaults` 支持：

| 变量 | 说明 |
| --- | --- |
| `{sourceItemId}` | 搜索结果中的源站条目 ID。常用于详情页路径。 |
| `{infoHash}` | info hash，通常为大写。 |
| `{infoHashLower}` | 小写 info hash。 |
| `{infoHashUpper}` | 大写 info hash。 |

模板替换时变量值会经过 `Uri.encodeComponent` 编码。

## Endpoint

`search` 和 `detail` 使用同一类结构。

```json
{
  "method": "GET",
  "url": "/search/{query}/{page}",
  "responseType": "html",
  "headers": {},
  "itemsPath": "data.items",
  "totalPath": "data.total",
  "currentPagePath": "data.page",
  "lastPagePath": "data.lastPage",
  "rootPath": "data",
  "filesPath": "files",
  "rootPattern": "",
  "itemPattern": "",
  "fileRootPattern": "",
  "filePattern": "",
  "totalPattern": "",
  "lastPagePattern": "",
  "pageSize": 20
}
```

通用字段：

| 字段 | 说明 |
| --- | --- |
| `method` | 当前只支持 `GET`。 |
| `url` | 请求 URL。可写绝对 URL，也可写相对 `baseUrl` 的路径。 |
| `responseType` | `json` 或 `html`，默认 `json`。 |
| `headers` | 当前 endpoint 专用请求头，会覆盖同名全局 header。 |
| `pageSize` | 每页数量，默认 `20`。用于根据 `total` 推算最后一页。 |

JSON endpoint 字段：

| 字段 | 用于 | 说明 |
| --- | --- | --- |
| `itemsPath` | search | 搜索结果数组路径。 |
| `totalPath` | search | 总结果数路径。 |
| `currentPagePath` | search | 当前页路径。缺失时使用请求页码。 |
| `lastPagePath` | search | 最后一页路径。缺失时用 `total / pageSize` 推算。 |
| `rootPath` | detail | 详情对象路径。为空时使用响应根对象。 |
| `filesPath` | detail | 文件列表数组路径。 |

路径使用点号访问对象，例如 `data.items`、`meta.total`。数组可用数字下标，例如 `data.0.name`。

HTML endpoint 字段：

| 字段 | 用于 | 说明 |
| --- | --- | --- |
| `rootPattern` | search/detail | 可选。先用正则截取局部 HTML 范围；优先使用第 1 个捕获组。 |
| `itemPattern` | search/detail | 必填。匹配一个资源条目或详情页主体信息。 |
| `fileRootPattern` | detail | 可选。先截取文件列表区域；优先使用第 1 个捕获组。 |
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
- 解码 `&nbsp;`、`&#160;`、`&#xA0;`、`&amp;`、`&quot;`、`&#39;`、`&lt;`、`&gt;`。
- 合并空白字符。

注意 JSON 字符串里的反斜杠要转义，例如正则 `\s` 要写成 `\\s`。

## 资源字段 fields

`fields` 把应用内部字段映射到响应数据路径，或映射到 HTML 正则捕获组。

```json
{
  "sourceItemId": "sourceItemId",
  "title": "title",
  "infoHash": "infoHash",
  "magnet": "magnet",
  "size": "size",
  "humanSize": "humanSize",
  "seeders": "seeders",
  "leechers": "leechers",
  "score": "score",
  "health": "health",
  "verified": "verified",
  "largestFile": "largestFile",
  "webUrl": "webUrl",
  "createdAt": "createdAt",
  "lastSeen": "lastSeen"
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `sourceItemId` | string | 源站详情 ID。缺失时使用 `infoHash`。搜索结果必须最终能得到该字段，否则列表项会被丢弃。 |
| `title` | string | 资源标题。 |
| `infoHash` | string | 建议提供。搜索列表可先缺失，但详情页应补全，才能生成 magnet。 |
| `magnet` | string | 磁力链接。可由 `defaults.magnet` 生成。 |
| `size` | int | 字节数。 |
| `humanSize` | string | 人类可读大小，例如 `1.23 GB`。 |
| `seeders` | int | 做种、热度或访问指标。不同站点含义可能不同。 |
| `leechers` | int | 下载、请求或热度指标。不同站点含义可能不同。 |
| `score` | double | 排序或评分。 |
| `health` | double | 健康度、文件数或其它站点指标。 |
| `verified` | bool | 是否验证。 |
| `largestFile` | string | 最大文件名或文件格式摘要。 |
| `webUrl` | string | 源站详情页。相对地址会基于 `baseUrl` 补全。 |
| `createdAt` | ISO date string | 创建时间。 |
| `lastSeen` | ISO date string | 最近发现时间。 |

## 文件字段 fileFields

详情页可返回文件列表。

```json
{
  "path": "path",
  "size": "size",
  "humanSize": "humanSize"
}
```

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
  "webUrl": "/torrent/{infoHashLower}"
}
```

常见用途：

- API 或列表页只返回 `infoHash`，用 `defaults.magnet` 生成 magnet。
- API 或列表页只返回 `infoHash`，用 `defaults.webUrl` 生成详情页链接。
- HTML 列表页返回详情相对地址，先放到 `sourceItemId`，再用 `defaults.webUrl` 显示源站链接。

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
    "lastPagePath": "data.lastPage",
    "pageSize": 20
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
  <a href="/detail/abc123">Example Title</a>
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
    "pageSize": 20,
    "rootPattern": "<div class=\"result-list\">([\\s\\S]*?)<nav",
    "itemPattern": "<div class=\"item\">\\s*<a href=\"(?<sourceItemId>[^\"]+)\">(?<title>.*?)</a>\\s*<span class=\"hash\">(?<infoHash>[A-Fa-f0-9]{40})</span>\\s*<span class=\"size\">(?<humanSize>.*?)</span>\\s*</div>",
    "totalPattern": "(\\d+)\\s+results",
    "lastPagePattern": "page=(\\d+)\">Last"
  },
  "detail": {
    "method": "GET",
    "url": "{sourceItemId}",
    "responseType": "html",
    "itemPattern": "<h1[^>]*>(?<title>.*?)</h1>[\\s\\S]*?<a href=\"(?<magnet>magnet:\\?xt=urn:btih:(?<infoHash>[A-Fa-f0-9]{40})[^\"]*)\"",
    "fileRootPattern": "<ul class=\"files\">([\\s\\S]*?)</ul>",
    "filePattern": "<li>\\s*<span class=\"path\">(?<path>.*?)</span>\\s*<span class=\"size\">(?<humanSize>.*?)</span>\\s*</li>"
  },
  "fields": {
    "sourceItemId": "sourceItemId",
    "title": "title",
    "infoHash": "infoHash",
    "magnet": "magnet",
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

## 调试建议

1. 先用浏览器或 curl 确认搜索 URL 能访问。
2. JSON API 插件先填 `search` 和最少字段：`sourceItemId`、`title`、`infoHash`。
3. HTML 插件先写 `rootPattern` 和 `itemPattern`，确认列表能匹配，再补详情页。
4. 如果站点只返回相对详情地址，映射到 `sourceItemId`，再用 `detail.url: "{sourceItemId}"`。
5. 如果没有 magnet 字段，只要能拿到 `infoHash`，就用 `defaults.magnet` 生成。
6. 如果站点触发 Cloudflare，把 `capabilities.requiresHumanVerification` 设为 `true`。
7. URL 安装要求地址以 `.json` 结尾。

## 当前限制

- 只支持 `GET`。
- 没有登录表单流程。
- 没有 JavaScript 渲染爬取能力；人机验证只用于获取页面 HTML 或 Cookie。
- HTML 解析基于正则，适合结构稳定、重复项明显的站点。
- Cookie 只保存在当前应用运行期内，按 `baseUrl.host` 复用。
- URL 安装只接受 `.json` 结尾地址。
