#!/usr/bin/swift
//
//  SilentStudio.swift
//
//  (c) by Dirk Schreib on 07.11.22.
//
//  If you use this inside Xcode you have to rename it to main.swift

import Foundation
import IOKit

var debug = false
var checkinterval = 30.0
var targetrpm: [Float: String] = [:]
targetrpm[0.0]="0"
targetrpm[50.0]="0"
targetrpm[60.0]="AUTO"
var sensorlist = ["TT0D", "TT1D", "Tp02"]

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
    init(_ servicename: String) throws {
        var mainport: mach_port_t = 0
        var result = IOMainPort(kIOMainPortDefault, &mainport)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
        let serviceDir = IOServiceMatching(servicename)
        let service = IOServiceGetMatchingService(mainport, serviceDir)
        result = IOServiceOpen(service, mach_task_self_ , 0, &con)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
        result = IOObjectRelease(service)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
    }
    
    deinit {
        IOServiceClose(con)
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

var shouldterminate = false
let signalCallback: sig_t = { signal in
    print(now, "Got signal: \(signal)")
    shouldterminate = true
}

signal(SIGINT, signalCallback)
signal(SIGTERM, signalCallback)
signal(SIGINFO, signalCallback)

var which = "targetrpm"
var targetlist = [String]()
var sensorlist2 = [String]()
var n = 1
while n < CommandLine.argc {
    let arg = CommandLine.arguments[n]
    switch arg {
    case "-s": which = "sensors"
    case "--": which = "targetrpm"
    case "-h": which = "help"; break
    case "-i": which = "interval"
    case "-d": debug = true
    default:
        switch which {
        case "targetrpm":
            targetlist.append(arg)
        case "interval":
            checkinterval = Double(arg) ?? checkinterval
        default:
            sensorlist2.append(arg)
        }
    }
    n += 1
}

if which == "help" {
    print("""
          usage: SilentStudio [--] [<temp> <rpm>]* [-d] [-h] [-i <sec>] [-s <sensor>*]

            options
            <temp> <rpm>     Pair(s) of temperature and rpm. "AUTO" for automatic setting. Default: \(targetrpm.sorted(by: <))
            -d               Debug mode. List every value read and written
            -h               This help text
            -i <sec>         Checks every <sec> seconds. Default: \(checkinterval)
            -s <sensor>*     List of sensors to read. Default: \(sensorlist)
          
            Program will run in an endless loop. Use ctrl-c to stop. Fans will be resetted to AUTO mode.
          """)
    exit(0)
}

if sensorlist2.count > 0 {
    sensorlist = sensorlist2
}

if targetlist.count > 0 && targetlist.count.isMultiple(of: 2) {
    var n = 0
    targetrpm = [:]
    while n < targetlist.count {
        print(now, "Set targetrpm")
        targetrpm[Float(targetlist[n]) ?? 0.0] = targetlist[n+1]
        n += 2
    }
}

do {
    if debug {
        print(now, "CheckInterval: \(checkinterval)")
        print(now, "targetrpm: \(targetrpm.sorted(by: <))")
        print(now, "sensorlist: \(sensorlist)")
    }
    let connection = try! IOServiceConnection("AppleSMC")
    // select startup temperature and set initial rpm
    var lasttemp: Float = 0.0
    let currenttemp = try sensorlist.reduce(0.0,{ result, sensor in max(result, try connection.read(sensor))})
    let x = targetrpm.sorted(by: <).last(where: {$0.key <= currenttemp})
    
    if let x {
        try connection.setFan(x.value)
        lasttemp = x.key
    }

    while true {
        let currenttemp = try sensorlist.reduce(0.0,{ result, sensor in max(result, try connection.read(sensor))})
        let rpm_left = try connection.read("F0Ac")
        let rpm_right = try connection.read("F1Ac")
        print(now, "current: \(String(format: "%.2f", currenttemp)), last: \(lasttemp), rpm: \(rpm_left),\(rpm_right)" )
        
        // only change rpm if temperature crosses a "border"
        for (temp, rpm) in targetrpm {
            if (lasttemp < temp && temp <= currenttemp) ||
                (currenttemp <= temp && temp < lasttemp) {
                // temp now higher or lower
                try connection.setFan(rpm)
                lasttemp = temp
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
} catch MyError.iokit(let error) {
    print(now, "catched error: \(error). started with sudo?")
} catch MyError.string(let error) {
    print(now, "catched error: \(error).")
}
