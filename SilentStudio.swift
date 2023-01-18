//#!/usr/bin/swiftc IOServiceConnection.swift
//
//  SilentStudio.swift
//
//  (c) by Dirk Schreib on 07.11.22.
//
//  If you use this inside Xcode you have to rename it to main.swift

import Foundation
import IOKit

@main
struct SilentStudio {
    static let dateFormatter = DateFormatter()
    static var now: String {
        dateFormatter.string(from: Date())
    }
    static var shouldterminate = false
    static let signalCallback: sig_t = { signal in
        print(now, "Got signal: \(signal)")
        SilentStudio.shouldterminate = true
    }

    static func main() {
        var debug = false
        var checkinterval = 30.0
        var targetrpm: [Float: String] = [:]
        targetrpm[0.0]="0"
        targetrpm[50.0]="0"
        targetrpm[60.0]="AUTO"
        var sensorlist = ["TT0D", "TT1D", "Tp02"]
        
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var which = "targetrpm"
        var targetlist = [String]()
        var sensorlist2 = [String]()
        var setFanRpm = ""
        var n = 1
        while n < CommandLine.argc {
            let arg = CommandLine.arguments[n]
            switch arg {
            case "-s": which = "sensors"
            case "--": which = "targetrpm"
            case "-f": which = "setFan"
            case "-h": which = "help"; break
            case "-i": which = "interval"
            case "-d": debug = true
            default:
                switch which {
                case "targetrpm":
                    targetlist.append(arg)
                case "setFan":
                    setFanRpm = arg
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
            -f <rpm>         Set fans to rpm and exit
            -h               This help text
            -i <sec>         Checks every <sec> seconds. Default: \(checkinterval)
            -s <sensor>*     List of sensors to read. Default: \(sensorlist)
          
            Program will run in an endless loop. Use ctrl-c to stop. Fans will be resetted to AUTO mode.
          """)
            exit(0)
        }
        
        if which == "setFan" {
            do {
                let connection = try! IOServiceConnection("AppleSMC")
                try connection.setFan(setFanRpm)
                exit(0)
            } catch MyError.iokit(let error) {
                print(now, "catched error: \(error). started with sudo?")
                exit(1)
            } catch {
                print(now, "unknown error")
                exit(1)
            }
        }
        
        if sensorlist2.count > 0 {
            sensorlist = sensorlist2
        }
        
        if targetlist.count > 0 && targetlist.count.isMultiple(of: 2) {
            var n = 0
            targetrpm = [:]
            while n < targetlist.count {
                targetrpm[Float(targetlist[n]) ?? 0.0] = targetlist[n+1]
                n += 2
            }
        }
        
        signal(SIGINT, signalCallback)
        signal(SIGTERM, signalCallback)
        signal(SIGINFO, signalCallback)
        
        do {
            if debug {
                print(now, "CheckInterval: \(checkinterval)")
                print(now, "targetrpm: \(targetrpm.sorted(by: <))")
                print(now, "sensorlist: \(sensorlist)")
            }
            let connection = try! IOServiceConnection("AppleSMC", debug)
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
            exit(1)
        } catch MyError.string(let error) {
            print(now, "catched error: \(error).")
            exit(1)
        } catch {
            print(now, "unknown error")
            exit(1)
        }
    }
}
