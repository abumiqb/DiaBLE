import Foundation

class App: ObservableObject {

    @Published var transmitter: Transmitter!
    @Published var sensor: Sensor!

    var main: MainDelegate!

    @Published var selectedTab: Tab = .monitor

    // TODO: use directly app.transmitter and app.sensor in ContentView
    @Published var currentGlucose: Int
    @Published var oopAlarm: String
    @Published var oopTrend: String
    @Published var transmitterState: String
    @Published var readingTimer: Int

    @Published var sensorState: String
    @Published var sensorSerial: String
    @Published var sensorAge: Int

    @Published var battery: Int
    @Published var transmitterFirmware: String
    @Published var transmitterHardware: String

    @Published var params: CalibrationParameters

    init(
        transmitter: Transmitter! = nil,
        sensor: Sensor! = nil,

        selectedTab: Tab = .monitor,

        currentGlucose: Int = 0,
        oopAlarm: String = "",
        oopTrend: String = "",
        transmitterState: String = "",
        readingTimer: Int = -1,

        sensorState: String = "Scanning...",
        sensorSerial: String = "",
        sensorAge: Int = 0,

        battery: Int = -1,
        transmitterFirmware: String = "",
        transmitterHardware: String = "Scanning...",

        params: CalibrationParameters = CalibrationParameters(slopeSlope: 0.0, slopeOffset: 0.0, offsetOffset: 0.0, offsetSlope: 0.0)) {

        self.transmitter = transmitter
        self.sensor = sensor
        
        self.selectedTab = selectedTab

        self.currentGlucose = currentGlucose
        self.oopAlarm = oopAlarm
        self.oopTrend = oopTrend
        self.transmitterState = transmitterState
        self.readingTimer = readingTimer

        self.sensorState = sensorState
        self.sensorSerial = sensorSerial
        self.sensorAge = sensorAge

        self.battery = battery
        self.transmitterFirmware = transmitterFirmware
        self.transmitterHardware = transmitterHardware

        self.params = params
    }
}


class Log: ObservableObject {
    @Published var text: String
    init(_ text: String = "Log \(Date())\n") {
        self.text = text
    }
}


class Info: ObservableObject {
    @Published var text: String
    init(_ text: String = "Info") {
        self.text = text
    }
}


class History: ObservableObject {
    @Published var values:    [Int]
    @Published var rawValues: [Int]
    @Published var rawTrend:  [Int]

    init(values:    [Int] = [],
         rawValues: [Int] = [],
         rawTrend:  [Int] = []) {
        self.values    = values
        self.rawValues = rawValues
        self.rawTrend  = rawTrend
    }
}


class Settings: ObservableObject {

    @Published var preferredTransmitter: TransmitterType {

        willSet(type) {
            if type == .miaomiao && readingInterval > 5 {
                readingInterval = 5
            }
        }
    }
    
    @Published var readingInterval: Int

    // TODO: a GlucoseRange struct
    @Published var targetLow: Double
    @Published var targetHigh: Double
    @Published var alarmLow: Double
    @Published var alarmHigh: Double
    @Published var mutedAudio: Bool

    @Published var logging: Bool
    @Published var reversedLog: Bool

    @Published var numberFormatter: NumberFormatter

    @Published var oopServerSite: String
    @Published var oopServerToken: String

    init(
        preferredTransmitter: TransmitterType = TransmitterType.none,
        readingInterval: Int = 5,

        targetLow: Double = 70.0,
        targetHigh: Double = 180.0,
        alarmLow: Double = 70.0,
        alarmHigh: Double = 220.0,
        mutedAudio: Bool = false,

        logging: Bool = true,
        reversedLog: Bool = true,

        numberFormatter: NumberFormatter = NumberFormatter(),

        oopServerSite: String = "https://www.glucose.space/",
        oopServerToken: String = "bubble-201907") {

        self.preferredTransmitter = preferredTransmitter
        self.readingInterval = readingInterval

        self.targetLow = targetLow
        self.targetHigh = targetHigh
        self.alarmLow = alarmLow
        self.alarmHigh = alarmHigh
        self.mutedAudio = mutedAudio

        self.logging = logging
        self.reversedLog = reversedLog

        self.numberFormatter = numberFormatter
        numberFormatter.minimumFractionDigits = 6

        self.oopServerSite = oopServerSite
        self.oopServerToken = oopServerToken
    }
}
