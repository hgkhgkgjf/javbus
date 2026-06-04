# Javbus

一个基于 JSON 插件的磁力资源搜索器，同时拥有局域网互传、网盘搜索功能。


- 搜索：通过 JSON 插件接入磁力搜索源，通过子部署的[Pansou](https://github.com/fish2018/pansou) api服务。实现磁力链搜索、网盘资源搜索
- 配置：查看和管理搜索源插件，填写pansou服务地址和密钥管理使用网盘搜索服务。
- 收藏：简易的网盘链接、磁力链接收藏业务
- 实用的局域网内跨设备文件互传服务（开发中）


## 插件协议

插件文档见 [docs/json_plugin_v1.md](docs/json_plugin_v1.md)。

当前 v1 支持：

- JSON API 搜索源。
- HTML + 正则提取搜索源、cf挑战弹窗。
- 只支持 `GET` 请求。


## 开发验证

```powershell
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --debug --no-pub
flutter build apk --debug --no-pub
```
