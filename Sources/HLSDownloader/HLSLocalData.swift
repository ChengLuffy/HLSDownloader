//
//  HLSLocalData.swift
//  
//
//  Created by 成殿 on 2022/5/20.
//

import Foundation

/// 本地存储数据模型
public struct HLSLocalData: Codable {
    /// 标题，唯一
    public let title: String
    /// 下载地址
    public let url: String
    /// 下载完成后的文件地址
    public var localPath: String?
    /// 下载状态
    public var status: HLSLocalDataStatus = .waiting
    /// 下载任务的标识
    public var taskIdentifier: Int?
    /// 添加时间
    public let addDate: Date
    /// 上次更改时间
    public var lastChangeDate: Date
    
    enum CodingKeys: CodingKey {
        case title, url, status, localPath, taskIdentifier, addDate, lastChangeDate
    }
    
    /// 初始化方法
    /// - Parameters:
    ///   - title: 标题
    ///   - url: 下载链接
    ///   - status: 状态，默认为 .waiting
    public init(title: String, url: String, status: HLSLocalDataStatus = .waiting) {
        self.title = title
        self.url = url
        self.status = status
        self.addDate = Date()
        self.lastChangeDate = Date()
    }
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        if let statusRaw = try values.decodeIfPresent(String.self, forKey: .status) {
            status = HLSLocalDataStatus(rawValue: statusRaw) ?? .unknown
        } else {
            status = .unknown
        }
        if let path = try values.decodeIfPresent(String.self, forKey: .localPath) {
            localPath = path
        }
        if let identifier = try values.decodeIfPresent(Int.self, forKey: .taskIdentifier) {
            taskIdentifier = identifier
        }
        if let addDatetimeInterval = try values.decodeIfPresent(Double.self, forKey: .addDate) {
            addDate = Date(timeIntervalSince1970: addDatetimeInterval)
        } else {
            addDate = Date()
        }
        if let lastChangeDatetimeInterval = try values.decodeIfPresent(Double.self, forKey: .lastChangeDate) {
            lastChangeDate = Date(timeIntervalSince1970: lastChangeDatetimeInterval)
        } else {
            lastChangeDate = Date()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(localPath, forKey: .localPath)
        try container.encode(taskIdentifier, forKey: .taskIdentifier)
        try container.encode(addDate.timeIntervalSince1970, forKey: .addDate)
        try container.encode(lastChangeDate.timeIntervalSince1970, forKey: .lastChangeDate)
    }
    
}

extension HLSLocalData: CustomStringConvertible {
    public var description: String {
        return #"""
               {
               "title":"\#(title)",
               "url":"\#(url)",
               "status":"\#(status.rawValue)",
               "localPath":"\#(localPath ?? "")",
               "taskIdentifier":"\#(taskIdentifier ?? -1)",
               "addDate":"\#(addDate.description)",
               "lastChangeDate":"\#(lastChangeDate.description)"
               }
               """#
    }
}

extension HLSLocalData: Equatable {
    public static func == (lhs: HLSLocalData, rhs: HLSLocalData) -> Bool {
        return lhs.title == rhs.title || lhs.url == rhs.url
    }
}

public enum HLSLocalDataStatus: String, CaseIterable {
    case unknown /// 未知
    case error /// 出现错误
    case waiting /// 等待下载
    case suspended /// 暂停
    case downloading /// 正在下载
    case done /// 下载完成
}
