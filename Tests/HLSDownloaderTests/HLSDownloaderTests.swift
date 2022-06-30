import XCTest
import Combine
@testable import HLSDownloader

final class HLSDownloaderTests: XCTestCase {
    
    private var disposeBag = Set<AnyCancellable>()
    
    override class func setUp() {
        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let indexPath = docPath + "/HLSDonwloader/"
        let tempPath = docPath + "/HLSDonwloader_bk/"
        try? FileManager.default.moveItem(atPath: indexPath, toPath: tempPath)
    }
    
    override class func tearDown() {
        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let indexPath = docPath + "/HLSDonwloader/"
        let tempPath = docPath + "/HLSDonwloader_bk/"
        if FileManager.default.fileExists(atPath: tempPath) {
            try? FileManager.default.removeItem(atPath: indexPath)
            try? FileManager.default.moveItem(atPath: tempPath, toPath: indexPath)
        }
    }
    
    func testSingle() throws {
        let object1 = HLSDownloader.shared
        let object2 = HLSDownloader.shared
        XCTAssertEqual(object1, object2)
    }
    
    func testSandboxDir() throws {
        let dirPath = HLSDownloader.shared.indexPath
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirPath))
    }
    
    func testDownloadInvalidUrlString() throws {
        XCTAssertThrowsError(try HLSDownloader.shared.download(title: "title", urlStr: "http  ")) { error in
            XCTAssertEqual(error as! HDError, HDError.invalidUrlString)
        }
    }
    
    func testSomeTryCatch() throws {
        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let indexPath = docPath + "/HLSDonwloader/"
        let tempPath = docPath + "/HLSDonwloader_bk/"
        try? FileManager.default.moveItem(atPath: indexPath, toPath: tempPath)
        let item = HLSLocalData(title: "title", url: "http://xx.m3u8")
        HLSDownloader.shared.addItem(item)
        HLSDownloader.shared.removeItem(byTitle: "title")
        try? FileManager.default.removeItem(atPath: indexPath)
        try? FileManager.default.moveItem(atPath: tempPath, toPath: indexPath)
    }
    
}
