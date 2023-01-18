//
//  IOServiceConnection.swift
//  SilentMenu
//
//  Copyright (c) by Dirk on 15.01.23.
//

import Foundation

struct AppleSMCVers { // 6 bytes
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct AppleSMCLimit { // 16 bytes
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpu: UInt32 = 0
    var gpu: UInt32 = 0
    var mem: UInt32 = 0
}

struct AppleSMCInfo { // 9+3=12 bytes
    var size: UInt32 = 0
    var type = AppleSMC4Chars()
    var attribute: UInt8 = 0
    var unused1: UInt8 = 0
    var unused2: UInt8 = 0
    var unused3: UInt8 = 0
}

struct AppleSMCBytes { // 32 bytes
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
               (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
enum MyError: Error {
    case iokit(kern_return_t)
    case string(String)
}

struct AppleSMC4Chars {  // 4 bytes
    var chars: (UInt8, UInt8, UInt8, UInt8) = (0,0,0,0)
    init() {
    }
    init(chars: (UInt8, UInt8, UInt8, UInt8)) {
        self.chars = chars
    }
    init(_ string: String) throws {
        // This looks silly but I don't know a better solution
        guard string.lengthOfBytes(using: .utf8) == 4 else { throw MyError.string("Sensor name \(string) must be 4 characters long")}
        chars.0 = string.utf8.reversed()[0]
        chars.1 = string.utf8.reversed()[1]
        chars.2 = string.utf8.reversed()[2]
        chars.3 = string.utf8.reversed()[3]
    }
}

struct AppleSMCKey { // 4 + 6(+2) + 16 + 12 + 1 + 1 + 1(+1) + 4 + 32 = 80
    var key = AppleSMC4Chars()
    var vers = AppleSMCVers()
    var limit = AppleSMCLimit()
    var info = AppleSMCInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = AppleSMCBytes()
}

class IOServiceConnection {
    var con: io_connect_t = 0
    var debug = false
    init(_ servicename: String, _ debug: Bool = false) throws {
        self.debug = debug
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var mainport: mach_port_t = 0
        var result = IOMainPort(kIOMainPortDefault, &mainport)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
        let serviceDir = IOServiceMatching(servicename)
        let service = IOServiceGetMatchingService(mainport, serviceDir)
        // will not work in sandbox
        result = IOServiceOpen(service, mach_task_self_ , 0, &con)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
        result = IOObjectRelease(service)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
    }
    
    deinit {
        IOServiceClose(con)
    }

    let dateFormatter = DateFormatter()
    var now: String {
        dateFormatter.string(from: Date())
     }

    let KERNEL_INDEX_SMC: UInt32 = 2
    func callStructMethod(_ input: inout AppleSMCKey, _ output: inout AppleSMCKey) throws {
        var outsize = MemoryLayout<AppleSMCKey>.size
        let result = IOConnectCallStructMethod(con, KERNEL_INDEX_SMC, &input, MemoryLayout<AppleSMCKey>.size, &output, &outsize)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
    }
    
    let SMC_CMD_READ_BYTES: UInt8 = 5
    let SMC_CMD_READ_KEYINFO: UInt8 = 9
    func readKey(_ input: inout AppleSMCKey) throws {
        var output = AppleSMCKey()
        
        input.data8 = SMC_CMD_READ_KEYINFO
        try callStructMethod(&input, &output)
        
        input.info.size = output.info.size
        input.info.type = output.info.type
        input.data8 = SMC_CMD_READ_BYTES
        
        try callStructMethod(&input, &output)
        
        input.bytes = output.bytes
    }
    
    func read(_ key: String) throws -> Float {
        var input = AppleSMCKey()
        input.key = try AppleSMC4Chars(key)
        input.info.size = 4
        input.info.type = try AppleSMC4Chars("flt ")
        try readKey(&input)
        var ret: Float = 0.0
        memmove(&ret, &input.bytes, 4)
        if debug { print( now, "read \(key): \(ret)") }
        return ret
    }

    let SMC_CMD_WRITE_BYTES: UInt8 = 6
    func writeKey(_ input: inout AppleSMCKey) throws {
        var output = AppleSMCKey()
        
        var read = input
        try readKey(&read)
        guard read.info.size == input.info.size else { throw MyError.string("type size does not match. Is it a temperature sensor?") }
        
        input.data8 = SMC_CMD_WRITE_BYTES
        try callStructMethod(&input, &output)
    }
    
    func write(_ key: String, fromFloat value: Float) throws {
        var new = value;
        if debug { print( now, "set  \(key): \(value)") }
        var input = AppleSMCKey()
        input.key = try AppleSMC4Chars(key)
        input.info.size = 4
        input.info.type = try AppleSMC4Chars("flt ")
        memmove(&input.bytes, &new,4)
        try writeKey(&input)
    }
    
    func write(_ key: String, fromByte value: UInt8) throws {
        if debug { print( now, "set  \(key): \(value)") }
        var input = AppleSMCKey()
        input.key = try AppleSMC4Chars(key)
        input.info.size = 1
        input.info.type = try AppleSMC4Chars("ui8 ")
        input.bytes.bytes.0 = value
        
        try writeKey(&input)
    }
    
    func setFan(_ rpm: String) throws {
        print( now, "change: Set fans to \(rpm) rpm")
        if rpm == "AUTO" {
            try write( "F0Md", fromByte: 0)
            try write( "F1Md", fromByte: 0)
        } else {
            try write( "F0Md", fromByte: 1)
            try write( "F1Md", fromByte: 1)
            try write( "F0Tg", fromFloat: Float(rpm) ?? 0.0)
            try write( "F1Tg", fromFloat: Float(rpm) ?? 0.0)
        }
    }
}
