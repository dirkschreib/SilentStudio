//
//  SilentStudioMenuApp.swift
//  SilentStudioMenu
//
//  Copyright (c) by Dirk on 13.01.23.
//

import SwiftUI

var sensorlist = ["TT0D", "TT1D", "Tp02"]
var fanlist = ["F0Ac", "F1Ac"]

func setFan(_ rpm: String) {
    do {
        let task = Process()
        task.arguments = ["-c", "\(Bundle.main.executableURL!.deletingLastPathComponent().path)/SilentStudio -f \(rpm)"]
        task.launchPath = "/bin/zsh"
        task.standardInput = nil
        try task.run()
        task.waitUntilExit()
    } catch {
        print("coudn't run helper task")
    }
}

extension Dictionary: RawRepresentable where Key == Float, Value == String {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),  // convert from String to Data
            let result = try? JSONDecoder().decode([Float:String].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),   // data is  Data type
              let result = String(data: data, encoding: .utf8) // coerce NSData to String
        else {
            return "{}"  // empty Dictionary resprenseted as String
        }
        return result
    }
}

class HWStatus: ObservableObject {
    static let connection = try! IOServiceConnection("AppleSMC")
    var timer: Timer?
    @Published var checkIntervall: Double = 5.0
    @Published var currentTemp: Float = 0.0
    @Published var currentRpm: Float = 0.0
    @AppStorage("targetrpm") var targetrpm: [Float:String] = [0.0:"0", 50.0:"0", 60.0:"AUTO"] {
        willSet { DispatchQueue.main.async { self.objectWillChange.send() }}
    }
    @AppStorage("automatic") var automatic = true {
        willSet { DispatchQueue.main.async { self.objectWillChange.send() }}
    }
    var lasttemp: Float = 0.0
    
    init() {
        let _ = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue:nil, using: self.didWake(_:))
        let _ = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue:nil, using: self.willSleep(_:))
        timer = Timer.scheduledTimer(withTimeInterval: checkIntervall, repeats: true, block: updateTempRpm(_:))
        setStartTemp()
    }
    
    func setStartTemp() {
        do {
            self.currentTemp = try sensorlist.reduce(0.0,{ result, sensor in max(result, try HWStatus.connection.read(sensor))})
            if automatic {
                let x = self.targetrpm.sorted(by: <).last(where: {$0.key <= self.currentTemp})
                
                if let x {
                    setFan(x.value)
                    self.lasttemp = x.key
                }
            }
        } catch {
            print("error")
        }
    }
    
    func updateTempRpm(_ tim: Timer) {
        do {
            print("time update", automatic)
            self.currentTemp = try sensorlist.reduce(0.0,{ result, sensor in max(result, try HWStatus.connection.read(sensor))})
            self.currentRpm = try fanlist.reduce(10000.0, {result, fan in min(result, try HWStatus.connection.read(fan))})
            print(self.currentTemp, self.currentRpm, self.lasttemp)

            if automatic {
                // only change rpm if temperature crosses a "border"
                for (temp, rpm) in self.targetrpm {
                    if (self.lasttemp < temp && temp <= self.currentTemp) ||
                        (self.currentTemp <= temp && temp < self.lasttemp) {
                        // temp now higher or lower
                        setFan(rpm)
                        self.lasttemp = temp
                    }
                }
            }
        } catch {
            print("error")
        }
    }

    func willSleep(_ notification: Notification) {
        print("will sleep")
        // I disabled the following line because it seems that the fans stay on during sleep otherwise
        //setFan("AUTO")
    }

    func didWake(_ notification: Notification) {
        print("did wake")
        setStartTemp()
    }
}

@main
struct SilentMenuApp: App {
    @ObservedObject var state = HWStatus()

    var body: some Scene {
        MenuBarExtra("\(String(format: "%.1f", state.currentTemp)) / \(String(format: "%.0f", state.currentRpm))") {
            Toggle(isOn: $state.automatic) {
                Text("Fan automatic")
            }.keyboardShortcut("a")
            Divider()
            Button("Fan off") {
                setFan("0")
                print("off")
            }
            .keyboardShortcut("0")
            Button("Fan on") {
                setFan("AUTO")
                print("on")
            }
            .keyboardShortcut("1")
            Divider()
            Button("Quit") {
                setFan("AUTO")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
