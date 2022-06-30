//
//  HLSLocalDataTests.swift
//  
//
//  Created by 成殿 on 2022/5/25.
//

import XCTest
@testable import HLSDownloader

class HLSLocalDataTests: XCTestCase {

    func testEncoderAndDecoder() throws {
        let string = #"""
                     {}
                     """#
        let data = string.data(using: .utf8)
        let item = try JSONDecoder().decode(HLSLocalData.self, from: data!)
        XCTAssertEqual(item.title, "")
        XCTAssertEqual(item.url, "")
        XCTAssertEqual(item.status, .unknown)
        XCTAssertNotNil(item.addDate)
        XCTAssertNotNil(item.lastChangeDate)
        let string1 = #"""
                      {"status":"status"}
                      """#
        let data1 = string1.data(using: .utf8)
        let item1 = try JSONDecoder().decode(HLSLocalData.self, from: data1!)
        XCTAssertEqual(item1.status, .unknown)
        let string2 = #"""
                      {"localPath":"./localPth"}
                      """#
        let data2 = string2.data(using: .utf8)
        let item2 = try JSONDecoder().decode(HLSLocalData.self, from: data2!)
        XCTAssertEqual(item2.localPath, "./localPth")
    }

}
