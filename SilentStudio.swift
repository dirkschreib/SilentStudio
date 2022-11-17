#!/usr/bin/swift
//
//  SilentStudio.swift
//
//  (c) by Dirk Schreib on 07.11.22.
//
//  If you use it inside Xcode you have to rename it to main.swift

import Foundation
import IOKit

// TODO: Use Commandline arguments
// TODO: fix startup behaviour (select correct rpm)
// TODO: read more sensors e.g. cpu/gpu
let checkinterval = 30.0
var targetrpm: [Float: String] = [:]
targetrpm[1.0]="0"
targetrpm[50.0]="0"
targetrpm[60.0]="AUTO"
//targetrpm[55.0]="560.5"
//targetrpm[60.0]="1121"
//targetrpm[65.0]="2200"

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

var now: String {
    dateFormatter.string(from: Date())
 }

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

struct AppleSMC4Chars {  // 4 bytes
    var chars: (UInt8, UInt8, UInt8, UInt8) = (0,0,0,0)
    init() {
    }
    init(chars: (UInt8, UInt8, UInt8, UInt8)) {
        self.chars = chars
    }
    init(_ string: String) {
        // This looks silly but I don't know a better solution
        assert(string.lengthOfBytes(using: .utf8) == 4)
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

extension kern_return_t: Error {}

class IOServiceConnection {
    var con: io_connect_t = 0
    init(_ servicename: String) throws {
        var mainport: mach_port_t = 0
        var result = IOMainPort(kIOMainPortDefault, &mainport)
        guard result == kIOReturnSuccess else { throw result }
        let serviceDir = IOServiceMatching(servicename)
        let service = IOServiceGetMatchingService(mainport, serviceDir)
        result = IOServiceOpen(service, mach_task_self_ , 0, &con)
        guard result == kIOReturnSuccess else { throw result }
        result = IOObjectRelease(service)
        guard result == kIOReturnSuccess else { throw result }
    }
    
    deinit {
        IOServiceClose(con)
    }

    let KERNEL_INDEX_SMC: UInt32 = 2
    func callStructMethod(_ input: inout AppleSMCKey, _ output: inout AppleSMCKey) throws {
        var outsize = MemoryLayout<AppleSMCKey>.size
        let result = IOConnectCallStructMethod(con, KERNEL_INDEX_SMC, &input, MemoryLayout<AppleSMCKey>.size, &output, &outsize)
        guard result == kIOReturnSuccess else { throw result }
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
        input.key = AppleSMC4Chars(key)
        input.info.size = 4
        input.info.type = AppleSMC4Chars("flt ")
        try readKey(&input)
        var ret: Float = 0.0
        memmove(&ret, &input.bytes, 4)
        //print( now, "read \(key): \(ret)")
        return ret
    }

    let SMC_CMD_WRITE_BYTES: UInt8 = 6
    func writeKey(_ input: inout AppleSMCKey) throws {
        var output = AppleSMCKey()
        
        var read = input
        try readKey(&read)
        guard read.info.size == input.info.size else { throw kIOReturnError }
        
        input.data8 = SMC_CMD_WRITE_BYTES
        try callStructMethod(&input, &output)
    }
    
    func write(_ key: String, fromFloat value: Float) throws {
        var new = value;
        print( now, "set  \(key): \(value)")
        var input = AppleSMCKey()
        input.key = AppleSMC4Chars(key)
        input.info.size = 4
        input.info.type = AppleSMC4Chars("flt ")
        memmove(&input.bytes, &new,4)
        try writeKey(&input)
    }
    
    func write(_ key: String, fromByte value: UInt8) throws {
        print( now, "set  \(key): \(value)")
        var input = AppleSMCKey()
        input.key = AppleSMC4Chars(key)
        input.info.size = 1
        input.info.type = AppleSMC4Chars("ui8 ")
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

var shouldterminate = false
let signalCallback: sig_t = { signal in
    print(now, "Got signal: \(signal)")
    shouldterminate = true
}

signal(SIGINT, signalCallback)
signal(SIGTERM, signalCallback)
signal(SIGINFO, signalCallback)

do {
    let connection = try! IOServiceConnection("AppleSMC")
    var lasttemp: Float = 0.0

    while true {
        let currenttemp = try connection.read("TT0D")
        let rpm_left = try connection.read("F0Ac")
        let rpm_right = try connection.read("F1Ac")
        print(now, "current: \(String(format: "%.2f", currenttemp)), last: \(lasttemp), rpm: \(rpm_left),\(rpm_right)" )
        
        // only change rpm if temperature crosses a "border"
        for (temp, rpm) in targetrpm {
            if (lasttemp < temp && temp <= currenttemp) ||
                (currenttemp <= temp && temp < lasttemp) {
                // temp now higher or lower
                try connection.setFan(rpm)
                lasttemp = currenttemp
            }
        }
        var check = checkinterval
        while !shouldterminate && check > 0 {
            Thread.sleep(forTimeInterval: 1.0)
            check -= 1
        }
        if shouldterminate {
            try connection.setFan("AUTO")
            exit(0)
        }
    }
} catch let result {
    print(now, "catched error: \(result). started with sudo?")
}
