# HLSDownloader

`.m3u8` 格式视频下载工具
- 未支持所有的格式，仅支持了作者自己需要处理的格式；
- 不支持模拟器下载；
- 发生错误和暂停的 `AVAssetDownloadTask` 无法被重新启动，所以会从头开始下载，但之前下载的错误文件还存在，这些文件会在删除命令时一起删除；
- 可以在 手机设置 - 通用 - iPhone 存储空间 - 检查已下载的视频 里查看、删除已经下载的视频，所以播放前需要检查 `isPlayableOffline`；
- `AVAssetDownloadTask` 不会将 key 文件下载下来，所以播放时需要先从网络获取 key 文件；
- 虽然限定了同时下载的个数，但是只要应用进过一次后台，所有正在等待的任务将会同时开始，具体并发数量看设备；
- `@available(iOS 10.15, *)` 限定仅仅是因为想用 `Combine`；
---
**另一种方案**是把所有切片下载下来并本地启动 HTTP 服务，由于本人水平有限使用下来会遇到：
- 1.由于每个切片都是一个单独的下载任务，而正常的视频都是成百上千的切片数量，基本上无法实现后台下载；
- 2.HTTP 服务稳定性，偶尔会中断；
- 3.无法**投屏到电视上播放**。