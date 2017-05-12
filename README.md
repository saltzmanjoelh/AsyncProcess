# ProcessRunner
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