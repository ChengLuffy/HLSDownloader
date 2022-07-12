//
//  ViewController.swift
//  Example
//
//  Created by 成殿 on 2022/5/26.
//

import UIKit
import AVKit
import Combine
import HLSDownloader

class ViewController: UIViewController {
    
    enum Section {
        case main
    }
    
    private var disposeBag = Set<AnyCancellable>()
    /// 请在这里填写自己想要下载的 hls 媒体，下载失败有可能是 `AVAssetDownloadTask` 不支持，也有可能是我没有实现 `func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask, didCompleteFor mediaSelection: AVMediaSelection)` 导致的不支持
    let urls: [(title: String, url: String)] = [
        ("xx_403_第01集", "https://xx.m3u8"),
        ("xx_403_第02集", "https://xx.m3u8"),
        ("xx_403_第03集", "https://xx.m3u8"),
        ("xx_403_第04集", "https://xx.m3u8"),
    ]
    lazy var collectionView: UICollectionView = {
        let config = UICollectionLayoutListConfiguration(appearance: UICollectionLayoutListConfiguration.Appearance.insetGrouped)
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        return collectionView
    }()
    var dataSource: UICollectionViewDiffableDataSource<Section, String>! = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        HLSDownloader.shared.progressesSubject.sink { [unowned self] values in
            for item in urls {
                if let value = values[item.title] {
                    debugPrint("\(item.title)   \(value)")
                    DispatchQueue.main.async {
                    }
                }
            }
        }.store(in: &self.disposeBag)
        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "download all"
        let button = UIButton.init(configuration: buttonConfig, primaryAction: UIAction(handler: { [unowned self] _ in
            print("download all")
            self.urls.forEach { item in
                try? HLSDownloader.shared.download(title: item.title, urlStr: item.url)
            }
        }))
        view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        configureDataSource()
    }
    
    func configureDataSource() {
        let cellConfig = UICollectionView.CellRegistration<ListCell, String> { cell, indexPath, itemIdentifier in
            var content = cell.defaultContentConfiguration()
            content.text = "\(itemIdentifier)"
            content.secondaryText = "0.00"
            cell.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) {
            (collectionView: UICollectionView, indexPath: IndexPath, identifier: String) -> UICollectionViewCell? in
            return collectionView.dequeueConfiguredReusableCell(using: cellConfig, for: indexPath, item: identifier)
        }

        // initial data
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(urls.map({ $0.title }))
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
}

extension ViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let titleAndUrl = urls[indexPath.item]
        let title = titleAndUrl.title
        guard let localPath = HLSDownloader.shared.fileLocalPath(for: title) else {
            guard let item = HLSDownloader.shared.filterItem(byTitle: title) else {
                return
            }
            if item.status != .done {
                print(item.status)
                try? HLSDownloader.shared.download(title: title, urlStr: titleAndUrl.url)
            }
            return
        }
        let fileUrl = URL(fileURLWithPath: localPath)
        let asset = AVURLAsset(url: fileUrl)
        if let cache = asset.assetCache, cache.isPlayableOffline {
            let playerItem = AVPlayerItem(asset: asset)
            let playerController = AVPlayerViewController()
            playerController.delegate = self
            let player = AVPlayer(playerItem: playerItem)
            playerController.player = player
            present(playerController, animated: true)
        }
    }
}

extension ViewController: AVPlayerViewControllerDelegate {
    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
        return true
    }
    
    func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        present(playerViewController, animated: false) {
            completionHandler(true)
        }
    }
}

class ListCell: UICollectionViewListCell {
    
    private var disposeBag = Set<AnyCancellable>()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        HLSDownloader.shared.progressesSubject.receive(on: DispatchQueue.main).sink { [unowned self] values in
            guard var config = self.contentConfiguration as? UIListContentConfiguration,
                  let text = config.text,
                  let progress = values[text]
            else {
                return
            }
            config.secondaryText = String(format: "%.2f", progress.progress)
            self.contentConfiguration = config
        }.store(in: &disposeBag)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
