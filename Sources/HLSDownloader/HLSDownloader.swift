import Combine
import AVFoundation
import os.log
import UIKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HLSDownloader")

/// .m3u8 格式视频下载工具
/// - 未支持所有的格式，仅支持了作者自己需要处理的格式
/// - 不支持模拟器下载
/// - 发生错误和暂停的 `AVAssetDownloadTask` 无法被重新启动，所以会从头开始下载，但之前下载的错误文件还存在，这些文件会在删除命令时一起删除
/// - 可以在 手机设置 - 通用 - iPhone 存储空间 - 检查已下载的视频 里查看、删除已经下载的视频，所以播放前需要检查 `isPlayableOffline`
/// - `AVAssetDownloadTask` 不会将 key 文件下载下来，所以播放时需要先从网络获取 key 文件
/// - 虽然限定了同时下载的个数，但是只要应用进过一次后台，所有正在等待的任务将会同时开始，具体并发数量看设备
/// - `@available(iOS 10.15, *)` 限定仅仅是因为想用 `Combine`
/// - ----
/// - **另一种方案**是把所有切片下载下来并本地启动 HTTP 服务，由于本人水平有限使用下来会遇到：
/// - 1.由于每个切片都是一个单独的下载任务，而正常的视频都是成百上千的切片数量，基本上无法实现后台下载；
/// - 2.HTTP 服务稳定性，偶尔会中断；
/// - 3.无法**投屏到电视上播放**。
@available(iOS 10.15, *) public class HLSDownloader: NSObject {
    // MARK: - 属性 -
    // MARK: - 公开属性
    /// 单例
    public static let shared = HLSDownloader()
    /// 后台下载所需
    public var completionHandler: (() -> Void)?
    /// 可被订阅的所有下载数据集合
    ///  - **如果有更新 UI 的操作，请在主线程处理**
    public private(set) var localDatasSubject: CurrentValueSubject<[HLSLocalData], Never>!
    /// 可被订阅的进度
    ///  - **如果有更新 UI 的操作，请在主线程处理**
    public var progressesSubject = CurrentValueSubject<[String: ProgressStruct], Never>([String: ProgressStruct]())
    /// 数据存储根目录
    public let indexPath: String = {
        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let indexPath = docPath + "/HLSDownloader/"
        return indexPath
    }()
    /// 本地数据
    private var localDatas: [HLSLocalData]! {
        didSet {
            guard let localDatasSubject = localDatasSubject else { return }
            localDatasSubject.send(localDatas)
        }
    }
    /// 下载进度
    private var progresses = [String: ProgressStruct]() {
        didSet {
            progressesSubject.send(progresses)
        }
    }
    /// 下载 session
    public var downloadSession: AVAssetDownloadURLSession!
    public private(set) var isDownloading = false
    public private(set) var downloadingItem: HLSLocalData?
    
    // MARK: - 初始化方法
    /// 初始化方法，私有
    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: (Bundle.main.bundleIdentifier ?? "") + "_HLSDownloader")
        downloadSession = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: nil)
        checkDir()
        do {
            try readLocalDatas()
        } catch {
            logger.error("初始化失败：\(error.localizedDescription)")
            localDatas = [HLSLocalData]()
            try? syncToDisk()
        }
        localDatasSubject = CurrentValueSubject<[HLSLocalData], Never>(localDatas)
        logger.info("初始化成功 \(#file)-\(#line)：\n\(self.localDatas.description)")
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let localDatasSubject = self?.localDatasSubject else { return }
            guard let localDatas = self?.localDatas else { return }
            localDatasSubject.send(localDatas)
            guard let progresses = self?.progresses else { return }
            self?.progressesSubject.send(progresses)
        }
    }
    
    // MARK: - 公开方法
    /// 新增下载
    /// - Parameters:
    ///   - title: 名称
    ///   - urlStr: urlStr
    public func download(title: String, urlStr: String) throws {
        guard title.count > 0 else {
            logger.error("title 不能是空字符串")
            throw HDError.invalidUrlString
        }
        guard (URL(string: urlStr) != nil) else {
            logger.error("url 错误：\(urlStr)")
            throw HDError.invalidUrlString
        }
        if let item = filterItem(byUrlStr: urlStr), item.title != title {
            throw HDError.URLExistsButTitleNotSame
        }
        if let item = filterItem(byUrlStr: title), item.url != urlStr {
            throw HDError.titleExistsButUrlNotSame
        }
        if isExsit(urlStr: urlStr) == false {
            let model = HLSLocalData(title: title, url: urlStr)
            addItem(model)
        } else {
            if let item = filterItem(byTitle: title), item.status == .done {
                throw HDError.taskHaveDone
            } else {
                updateItem(byTitle: title, status: .waiting)
            }
        }
        if isDownloading == false {
            beginDownload()
        }
    }
    
    /// 暂停下载
    /// - discussion 由于 AVAssetDownloadTask 会出现暂停后无法重新开启，所以暂停后基本相当于取消
    /// - Parameter title: title
    public func suspend(byTitle title: String) {
        updateItem(byTitle: title, status: .suspended)
        if let item = filterItem(byTitle: title), let taskId = item.taskIdentifier {
            downloadSession.getAllTasks { tasks in
                if let task = tasks.first(where: { $0.taskIdentifier == taskId }) {
                    task.suspend()
                }
            }
        }
        if downloadingItem?.title == title {
            downloadingItem = nil
            beginDownload()
        }
    }
    
    /// 继续下载
    /// - discussion 由于 AVAssetDownloadTask 会出现暂停后无法重新开启，所以暂停后只能重新开始
    /// - Parameter title: title
    public func restore(byTitle title: String) {
        if let _ = filterItem(byTitle: title) {
            updateItem(byTitle: title, status: .waiting)
            if isDownloading == false {
                beginDownload()
            }
        }
    }
    
    /// 根据 title 进行删除
    /// - Parameter title: 需要删除的 title
    public func removeItem(byTitle title: String) {
        guard let index = localDatas.firstIndex(where: { $0.title == title }) else {
            return
        }
        removeItem(byIndex: index)
        if downloadingItem?.title == title {
            downloadingItem = nil
            beginDownload()
        }
    }
    
    /// 根据 title 进行筛选
    /// - Parameter title: title
    /// - Returns: 匹配入参 title 的第一个 item
    public func filterItem(byTitle title: String) -> HLSLocalData? {
        return localDatas.first(where: { $0.title == title })
    }
    
    /// 判断 urlStr 是否存在
    /// - Parameter urlStr: urlStr
    /// - Returns: 是否存在
    public func isExsit(urlStr: String) -> Bool {
        return filterItem(byUrlStr: urlStr) != nil
    }
    
    /// 判断 title 是否存在
    /// - Parameter title: title
    /// - Returns: 是否存在
    public func isExsit(title: String) -> Bool {
        return filterItem(byTitle: title) != nil
    }
    
    /// 根据 title 获取本地缓存路径
    /// - Parameter title: title
    /// - Returns: 如果存在，返回沙盒地址，不存在返回 nil
    public func fileLocalPath(for title: String) -> String? {
        guard let item = filterItem(byTitle: title) else {
            return nil
        }
        guard let localPath = item.localPath else {
            return nil
        }
        return NSHomeDirectory() + "/" + localPath
    }
}

extension HLSDownloader {
    // MARK: - 非公开的方法
    
    /// 根据 url 进行筛选
    /// - Parameter urlStr: url
    /// - Returns: 匹配入参 urlStr 的第一个 item
    private func filterItem(byUrlStr urlStr: String) -> HLSLocalData? {
        return localDatas.first(where: { $0.url == urlStr })
    }
    
    /// 根据 url 进行筛选
    /// - Parameter urlStr: url
    /// - Returns: 匹配入参 urlStr 的第一个 item
//    private func filterItem(byIdentifier identifier: Int) -> HLSLocalData? {
//        guard localDatas != nil else {
//            return nil
//        }
//        return localDatas.last(where: { $0.taskIdentifier == identifier })
//    }
    
    /// 筛选下一个要下载的
    /// - Returns: 下一个要下载的 item
    private func filterNextItem() -> HLSLocalData? {
        return localDatas.filter({ $0.status == .waiting }).sorted(by: { $0.addDate.timeIntervalSince1970 < $1.addDate.timeIntervalSince1970 }).first
    }
    
    /// 开始下载任务
    private func beginDownload() {
        if let item = filterNextItem() {
            if downloadingItem != item {
                createTask(item)
            }
        } else {
            downloadingItem = nil
            isDownloading = false
        }
    }
    
    /// 构建下载任务
    /// - Parameter item: item
    private func createTask(_ item: HLSLocalData) {
        guard let url = URL(string: item.url) else { return }
        let asset = AVURLAsset(url: url)
        var tempTaskId: Int?
        downloadingItem = item
        if let taskId = item.taskIdentifier {
            downloadSession.getAllTasks { [weak self] tasks in
                if let task = tasks.first(where: { $0.taskIdentifier == taskId }) {
                    task.resume()
                    tempTaskId = taskId
                    self?.isDownloading = true
                    self?.updateItem(byTitle: item.title, status: .downloading, taskIdentifier: tempTaskId)
                    logger.info("开始下载 \(item.title)")
                } else {
                    self?.updateItem(byTitle: item.title, status: .downloading, taskIdentifier: nil)
                    var item = item
                    item.taskIdentifier = nil
                    self?.createTask(item)
                }
            }
        } else {
            guard let task = downloadSession.makeAssetDownloadTask(asset: asset, assetTitle: item.title, assetArtworkData: nil) else { return }
            tempTaskId = task.taskIdentifier
            task.resume()
        }
        if tempTaskId != nil {
            isDownloading = true
            updateItem(byTitle: item.title, status: .downloading, taskIdentifier: tempTaskId)
            logger.info("开始下载 \(item.title)")
        }
    }
    
    /// 根据下标删除
    /// - Parameter index: index
    private func removeItem(byIndex index: Int) {
        let item = localDatas[index]
        localDatas.remove(at: index)
        do {
            try syncToDisk()
            logger.info("删除数据：url string: \(item.description)")
        } catch {
            logger.error("数据同步到磁盘失败 \(#file)-\(#line)：\(error.localizedDescription)")
        }
        removeCache(byTitle: item.title)
        guard let taskId = item.taskIdentifier else {
            return
        }
        downloadSession.getAllTasks(completionHandler: { tasks in
            if let task = tasks.first(where: { $0.taskIdentifier == taskId }) {
                task.cancel()
            }
        })
    }
    
    /// 删除本地缓存
    /// - Parameter byTitle: title
    private func removeCache(byTitle: String) {
        guard let title = byTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        DispatchQueue.global().async {
            let libraryDirPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
            if let subPaths = FileManager.default.subpaths(atPath: libraryDirPath) {
                let items = subPaths.filter({ $0.contains(title) && $0.hasSuffix(".movpkg") })
                logger.info("libraryDirectory \(libraryDirPath): \(items.description)")
                items.forEach { item in
                    try? FileManager.default.removeItem(atPath: libraryDirPath + "/" + item)
                }
            }
        }
    }
    
    /// 添加数据
    /// - Parameter item: item
    func addItem(_ item: HLSLocalData) {
        if let _ = localDatas.firstIndex(of: item) {
            logger.info("数据已经存在：\(item.description)")
        } else {
            localDatas.append(item)
            logger.info("新增数据：\(item.description)")
        }
        do {
            try syncToDisk()
        } catch {
            logger.error("数据同步到磁盘失败 \(#file)-\(#line)：\(error.localizedDescription)")
        }
    }
    
    /// 根据标题更新数据
    /// - Parameters:
    ///   - title: 要更新的标题
    ///   - status: 更新后的状态值
    ///   - localPath: 更新后的本地地址值
    ///   - taskIdentifier: 更新后的任务标识
    func updateItem(byTitle title: String, status: HLSLocalDataStatus? = nil, localPath: String? = nil, taskIdentifier: Int? = nil) {
        if var item = filterItem(byTitle: title), let index = localDatas.firstIndex(of: item) {
            if let status = status {
                item.status = status
            }
            if let localPath = localPath {
                item.localPath = localPath
            }
            if let taskIdentifier = taskIdentifier {
                item.taskIdentifier = taskIdentifier
            }
            item.lastChangeDate = Date()
            localDatas.replaceSubrange(index...index, with: [item])
            logger.info("更新数据：\(item.description)")
        }
        do {
            try syncToDisk()
        } catch {
            logger.error("数据同步到磁盘失败 \(#file)-\(#line)：\(error.localizedDescription)")
        }
    }
    
    /// 检查本地文件夹
    private func checkDir() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: indexPath) == false {
            try? fileManager.createDirectory(atPath: indexPath, withIntermediateDirectories: true, attributes: nil)
            var url = URL(fileURLWithPath: indexPath)
            var resourceValue = URLResourceValues()
            resourceValue.isExcludedFromBackup = false
            try? url.setResourceValues(resourceValue)
        }
    }
    
    /// 读取本地数据
    private func readLocalDatas() throws {
        let pathUrl = URL(fileURLWithPath: indexPath + "data.json")
        let data = try Data(contentsOf: pathUrl)
        localDatas = try JSONDecoder().decode([HLSLocalData].self, from: data)
        localDatas?.filter({ $0.status == .waiting || $0.status == .downloading }).forEach { item in
            updateItem(byTitle: item.title, status: .suspended)
        }
    }
    
    /// 同步到磁盘
    private func syncToDisk() throws {
        let pathUrl = URL(fileURLWithPath: indexPath + "data.json")
        let data = try JSONEncoder().encode(localDatas)
        try data.write(to: pathUrl)
    }
}

extension HLSDownloader: AVAssetDownloadDelegate, URLSessionDataDelegate {
    // MARK: - AVAssetDownloadDelegate
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        var percentComplete = 0.0
        // 1.遍历
        for value in loadedTimeRanges {
            // 2.获取下载的时间
            let loadedTimeRange = value.timeRangeValue
            // 3.累计
            percentComplete += loadedTimeRange.duration.seconds / timeRangeExpectedToLoad.duration.seconds
        }
        percentComplete *= 100
        if let item = downloadingItem {
            let progressStruct = ProgressStruct(progress: percentComplete, status: .downloading)
            progresses[item.title] = progressStruct
        }
    }
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let item = downloadingItem else {
            return
        }
        logger.info("\(item.title)下载完成：\(location.relativePath)")
        updateItem(byTitle: item.title, localPath: location.relativePath)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let item = downloadingItem else {
            return
        }
        guard error == nil else {
            if let error = error as? NSError, error.code == 2 || error.code == -999 {
                logger.info("error code 2")
                updateItem(byTitle: item.title, status: .waiting)
                createTask(item)
                return
            } else {
                logger.error("下载失败：\(error?.localizedDescription ?? "unknown")")
                updateItem(byTitle: item.title, status: .error)
                let progressStruct = ProgressStruct(progress: 0, status: .error, desc: error?.localizedDescription)
                progresses[item.title] = progressStruct
                beginDownload()
                return
            }
        }
        beginDownload()
        updateItem(byTitle: item.title, status: .done)
        let progressStruct = ProgressStruct(progress: 100.0, status: .done)
        progresses[item.title] = progressStruct
    }
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.completionHandler?()
            self.completionHandler = nil
        }
    }
}
