# ProcessRunner
[![Build Status][image-1]][1] [![Swift Version][image-2]][2]

Run Foundation Process asynchronously and perform easy reads and writes in closures.

```
var didWrite = false
var result = ""
let process = try? ProcessRunner(launchPath: "/usr/bin/openssl")
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
}
process!.launch()
```

[1]:	https://travis-ci.org/saltzmanjoelh/ProcessRuner
[2]:	https://swift.org "Swift"

[image-1]:	https://travis-ci.org/saltzmanjoelh/ProcessRuner.svg
[image-2]:	https://img.shields.io/badge/swift-version%204-blue.svg