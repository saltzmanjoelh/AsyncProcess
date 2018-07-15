
import Foundation
import Dispatch

enum ProcessRunnerError: Error, CustomStringConvertible {
    case InvalidExecutable(path: String?)
    
    var description: String {
        switch self {
        case .InvalidExecutable(let path):
            return "File is not executable at path: \(String(describing: path))"
        }
    }
}
public typealias ProcessResult = (output:String?, error:String?, exitCode:Int32)

/**
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
 */
public protocol ProcessRunnable {
    init(launchPath: String, arguments: [String]?, environment: [String:String]?, stdOut: ((_ stdOutRead: FileHandle) -> Void)?, stdErr: ((_ stdErrRead: FileHandle) -> Void)?) throws
    
    @discardableResult
    static func synchronousRun(_ launchPath: String, arguments: [String]?, printOutput: Bool, outputPrefix: String?, environment: [String:String]?) -> ProcessResult
}

public class ProcessRunner: ProcessRunnable {

    
    public let executingProcess: Process
    public let stdOutPipe: Pipe
    public let stdErrPipe: Pipe
    public let stdInPipe: Pipe
    
    //Async process
    public required init(launchPath: String,
                arguments: [String]? = nil,
                environment: [String:String]? = nil,
                stdOut: ((_ stdOutRead: FileHandle) -> Void)? = nil,
                stdErr: ((_ stdErrRead: FileHandle) -> Void)? = nil) throws {
        //Launch path
        executingProcess = Process()
        executingProcess.launchPath = NSString(string: launchPath).standardizingPath
        guard let path = executingProcess.launchPath,
            FileManager.default.isExecutableFile(atPath: path) else {
                throw ProcessRunnerError.InvalidExecutable(path: executingProcess.launchPath)
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
        #if !os(Linux)
        stdOutPipe.fileHandleForReading.readabilityHandler = stdOut
        #endif
        executingProcess.standardOutput = stdOutPipe
        
        stdErrPipe = Pipe()
        #if !os(Linux)
        stdErrPipe.fileHandleForReading.readabilityHandler = stdErr
        #endif
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
    #if !os(Linux)
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
    #endif
    
    func write(_ data: Data) {
        stdInPipe.fileHandleForWriting.write(data)
    }
    
    @discardableResult
    public static func synchronousRun(_ launchPath: String, arguments: [String]? = nil, printOutput: Bool = false, outputPrefix: String? = nil, environment: [String:String]? = nil) -> ProcessResult {
        do {
            var output = ""
            var error = ""
            let prefix = outputPrefix != nil ? "\(outputPrefix!): " : ""
            let process = try ProcessRunner(launchPath: launchPath, arguments: arguments)
            var isWriting = false
            let serialQueue = DispatchQueue(label: "LockingQueue")
            #if !os(Linux)
            process.stdOut { (handle: FileHandle) in
                serialQueue.sync { isWriting = true }
                handleOutputData(handle.availableData as Data,
                                 output: &output,
                                 printOutput: printOutput,
                                 prefix: prefix)
                serialQueue.sync { isWriting = false }
            }
            process.stdErr { (handle: FileHandle) in
                serialQueue.sync { isWriting = true }
                handleErrorData(handle.availableData as Data,
                                error: &error,
                                printOutput: printOutput,
                                prefix: prefix)
                serialQueue.sync { isWriting = false }
            }
            #endif
            process.launch()
            #if os(Linux)
                serialQueue.sync {
                    handleOutputData(process.stdOutPipe.fileHandleForReading.readDataToEndOfFile(),
                                     output: &output,
                                     printOutput: printOutput,
                                     prefix: prefix)
                    handleErrorData(process.stdErrPipe.fileHandleForReading.readDataToEndOfFile(),
                                    error: &error,
                                    printOutput: printOutput,
                                    prefix: prefix)
                }
            #endif
            while process.executingProcess.isRunning {
                RunLoop.current.run(until: Date.init(timeIntervalSinceNow: TimeInterval(0.10)))
            }
            //give it a second to wrap up writing
            let isWritingCheck: () -> Bool = {
                var ans = false
                serialQueue.sync { ans = isWriting == true }
                return ans
            }
            while isWritingCheck() {
                RunLoop.current.run(until: Date.init(timeIntervalSinceNow: TimeInterval(0.10)))
            }
            return (output, error.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count == 0 ? nil : error, process.executingProcess.terminationStatus)
            
        } catch let e {
            return (nil, String(describing: e), -1)
        }
    }
    static func handleOutputData(_ data: Data, output: inout String, printOutput: Bool, prefix: String) {
        if let str = String.init(data: data, encoding: .utf8),
            str.count > 0 {
            let line =  "\(prefix)\(str)"
            output.append(line)
            if printOutput {
                print(line)
            }
        }
    }
    static func handleErrorData(_ data: Data, error: inout String, printOutput: Bool, prefix: String) {
        if let str = String.init(data: data, encoding: .utf8),
            str.count > 0 {
            //                    print("stdErr: \(str)")
            error.append(str)
        }
    }
}
