//
//  SilentStudioMenuApp.swift
//  SilentStudioMenu
//
//  Copyright (c) by Dirk on 13.01.23.
//

import SwiftUI
import Charts

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
        print("error, coudn't run helper task")
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

struct Measurement {
    let time: Date
    let temperatures: [String:Float]
    let rpm: Float
}

struct MeasurementHistory {
    var measurements: [Measurement] = []
    
    mutating func add(_ measurement: Measurement) {
        if measurements.count == 720 {
            measurements.remove(at: 0)
        }
        measurements.append(measurement)
    }
}
class HWStatus: ObservableObject {
    static let connection = try! IOServiceConnection("AppleSMC")
    var timer: Timer?
    @Published var measurementHistory = MeasurementHistory()
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
    var chartRpm: [Float:Int] = [:]
    let dateFormatter = DateFormatter()
    var now: String {
        dateFormatter.string(from: Date())
    }
    
    init() {
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        chartRpm = Dictionary(uniqueKeysWithValues: targetrpm.map() { key, value in if value == "AUTO" { return (key,1330) } else { return (key,Int(value) ?? 0) }} )
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
            print(now, "error")
        }
    }
    
    func updateTempRpm(_ tim: Timer) {
        do {
            let allTemps = try sensorlist.reduce(into: [:]) {$0[$1] = try HWStatus.connection.read($1) }
            currentTemp = allTemps.reduce(0.0,{ result, sensor in max(result, sensor.value)})
            currentRpm = try fanlist.reduce(10000.0, {result, fan in min(result, try HWStatus.connection.read(fan))})
            measurementHistory.add(Measurement(time: Date(), temperatures: allTemps, rpm: currentRpm))
            //print(now, "current", self.currentTemp, self.currentRpm, self.lasttemp)

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
            print(now, "error updateTempRpm")
        }
    }

    func willSleep(_ notification: Notification) {
        print(now, "will sleep")
        // I disabled the following line because it seems that the fans stay on during sleep otherwise
        //setFan("AUTO")
    }

    func didWake(_ notification: Notification) {
        print(now, "did wake")
        setStartTemp()
    }
}

struct MenuView: View {
    @ObservedObject var state: HWStatus
    @State var temp: Float = 0.0
    @State var rpm: String = "AUTO"

    var body: some View {
        Text("Temperature in °C").padding([.top], 8)
        Chart() {
            ForEach(state.measurementHistory.measurements.indices, id:\.self) { idx in
                ForEach(state.measurementHistory.measurements[idx].temperatures.sorted(by:<), id:\.key) { sensor, temp in
                    LineMark(x: .value("Time", state.measurementHistory.measurements[idx].time), y: .value("Temp", temp))
                        .foregroundStyle(by: .value("type", sensor))
                }
            }
        }
        .chartYScale(domain: 30...70)
        .frame(minWidth:300, minHeight:150).padding(16)
        
        Text("Fan speed in rpm")
        Chart() {
            ForEach(state.measurementHistory.measurements.indices, id:\.self) { idx in
                LineMark(x: .value("Time", state.measurementHistory.measurements[idx].time), y: .value("Rpm", state.measurementHistory.measurements[idx].rpm))
                        //.foregroundStyle(by: .value("type", "Rpm"))
            }
        }
        .foregroundColor(.blue)
        .chartYScale(domain: 0...2000)
        .frame(minWidth:300, minHeight:100).padding(16)

        Text("Temperature/rpm points")
        List() {
            ForEach(state.targetrpm.sorted(by: <), id:\.key) { key, value in
                HStack {
                    Text(String(key))
                    Spacer()
                    Text(value)
                }
            }
            .onDelete { indexSet in print("delete", indexSet.first ?? 0,  state.targetrpm.sorted(by: <)[indexSet.first ?? 0]); state.targetrpm.removeValue(forKey: state.targetrpm.sorted(by: <)[indexSet.first ?? 0].key) }
        }
        HStack {
            TextField("temperature", value: $temp, formatter: NumberFormatter())
            Spacer()
            TextField("rpm", text: $rpm)
            Button("Add") { print ("add", temp, rpm); state.targetrpm[temp] = rpm }
        }.padding(16)
        Chart() {
            ForEach(state.chartRpm.sorted(by: <), id: \.key) { key, value in
                LineMark(x: .value("Temp", key), y: .value("Rpm", value)).interpolationMethod(.stepEnd).lineStyle(StrokeStyle(lineWidth:3,lineCap: .round, lineJoin: .round))
            }.foregroundStyle(by: .value("way", "up"))
            ForEach(state.chartRpm.sorted(by: <), id: \.key) { key, value in
                LineMark(x: .value("Temp", key), y: .value("Rpm", value)).interpolationMethod(.stepStart).lineStyle(StrokeStyle(lineWidth:3,lineCap: .round, lineJoin: .round))
            }.foregroundStyle(by: .value("way", "down"))
            PointMark(x: .value("Temp", state.currentTemp), y: .value("Rpm", state.currentRpm)).foregroundStyle(by: .value("way", "current"))
                .annotation() {
                    VStack {
                        HStack {
                            Image(systemName: "thermometer.medium")
                            Text(String(format: "%.1f", state.currentTemp))
                        }
                        HStack {
                            Image(systemName: "fanblades")
                            Text(String(format: "%.0f", state.currentRpm))
                        }
                    }
                }
        }.frame(minWidth:300, minHeight:100).padding(16)
            .chartXScale(domain: 30...70)
            .chartYScale(domain: 0...2000)
    }
}

@main
struct SilentMenuApp: App {
    @ObservedObject var state = HWStatus()

    var body: some Scene {
        MenuBarExtra {
            Toggle(isOn: $state.automatic) {
                Text("Fan automatic")
            }.keyboardShortcut("a")
            Divider()
            Button("Fan off") {
                setFan("0")
                state.lasttemp = 0.0
            }
            .keyboardShortcut("0")
            Button("Fan on") {
                setFan("AUTO")
                state.lasttemp = 200.0
            }
            .keyboardShortcut("1")
            Divider()
            Button("Quit") {
                setFan("AUTO")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "fanblades")
            Text(String(format: "%.0f", state.currentRpm))
        }
        MenuBarExtra {
            MenuView(state: state).frame(minHeight: 750)
        } label: {
            Image(systemName: "thermometer.medium")
            Text(String(format: "%.1f", state.currentTemp))
        }.menuBarExtraStyle(.window)
    }
}
