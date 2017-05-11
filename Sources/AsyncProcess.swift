
import Foundation

enum AsyncProcessError: Error, CustomStringConvertible {
    case InvalidExecutable(path: String?)
    
    var description: String {
        switch self {
        case .InvalidExecutable(let path):
            return "File is not executable at path: \(String(describing: path))"
        }
    }
}

/**
 ```
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
 }
 process!.launch()
 ```
 */
public class AsyncProcess {
    
    public let executingProcess: Process
    public let stdOutPipe: Pipe
    public let stdErrPipe: Pipe
    public let stdInPipe: Pipe
    
    public init(launchPath: String,
                arguments: [String]? = nil,
                environment: [String:String]? = nil,
                stdOut: ((_ stdOutRead: FileHandle) -> Void)? = nil,
                stdErr: ((_ stdErrRead: FileHandle) -> Void)? = nil) throws {
        //Launch path
        executingProcess = Process()
        executingProcess.launchPath = (launchPath as NSString).standardizingPath
        guard let path = executingProcess.launchPath,
            FileManager.default.isExecutableFile(atPath: path) else {
                throw AsyncProcessError.InvalidExecutable(path: executingProcess.launchPath)
        }
        
        //Arguments
        if let args = arguments {
            executingProcess.arguments = args.map({ "\($0)" })
        }
        
        //Environment
        if let env = environment {
            executingProcess.environment = env
        }
        
        //Current directory
        executingProcess.currentDirectoryPath = FileManager.default.currentDirectoryPath
        
        //Pipes
        stdOutPipe = Pipe()
        stdOutPipe.fileHandleForReading.readabilityHandler = stdOut
        executingProcess.standardOutput = stdOutPipe
        
        stdErrPipe = Pipe()
        stdErrPipe.fileHandleForReading.readabilityHandler = stdErr
        executingProcess.standardError = stdErrPipe
        
        stdInPipe = Pipe()
        executingProcess.standardInput = stdInPipe
    }
    public func launch() {
        executingProcess.launch()
    }
    /**
    ```
    process!.stdOut { (handle: FileHandle) in
        let str = String.init(data: handle.availableData as Data, encoding: .utf8)!
        print("stdOut: \(str)")
        if str == "OpenSSL> " && !didWrite {
            didWrite = true
            process?.write("foobar\n".data(using: .utf8)!)
        }
    }
    ```
     */
    @discardableResult
    public func stdOut(_ reader: ((FileHandle) -> Void)?) -> Self {
        stdOutPipe.fileHandleForReading.readabilityHandler = reader
        return self
    }
    /**
     ```
     process!.stdErr { (handle: FileHandle) in
         let str = String.init(data: handle.availableData as Data, encoding: .utf8)!
         print("stdErr: \(str)")
     }
     ```
     */
    @discardableResult
    public func stdErr(_ reader: ((FileHandle) -> Void)?) -> Self {
        stdErrPipe.fileHandleForReading.readabilityHandler = reader
        return self
    }
    
    func write(_ data: Data) {
        stdInPipe.fileHandleForWriting.write(data)
    }
}
