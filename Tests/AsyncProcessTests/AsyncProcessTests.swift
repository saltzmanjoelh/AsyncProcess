import XCTest
@testable import AsyncProcess

class AsyncProcessTests: XCTestCase {
    func testWaitingForInput() {
        var didWrite = false
        var result = ""
        let process = try? AsyncProcess(launchPath: "/usr/bin/openssl")
        process!.stdOut { (handle: FileHandle) in
            let str = String.init(data: handle.availableData as Data, encoding: .utf8)!
            print("stdOut: \(str)")
            if str == "OpenSSL> " && !didWrite {
                didWrite = true
                process?.write("foobar\n".data(using: .utf8)!)
            }
        }
        process!.stdErr { (handle: FileHandle) in
            let str = String.init(data: handle.availableData as Data, encoding: .utf8)!
            print("stdErr: \(str)")
            result = str
            process!.stdErr(nil)
        }
        process!.launch()
        RunLoop.current.run(until: Date.init(timeIntervalSinceNow: 1))
        

        XCTAssertTrue(result.contains("'foobar' is an invalid command"))
    }


    static var allTests = [
        ("testWaitingForInput", testWaitingForInput),
    ]
}
