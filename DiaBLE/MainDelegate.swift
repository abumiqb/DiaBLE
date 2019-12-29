import SwiftUI
import CoreBluetooth
import AVFoundation

class App: ObservableObject {

    @Published var preferredTransmitter = TransmitterType.none
    @Published var transmitter: Transmitter!
    @Published var sensor: Sensor!

    var main: MainDelegate!

    // TODO: use directly app.transmitter and app.sensor in ContentView
    @Published var battery: Int = 0
    @Published var currentGlucose: Int = 0
    @Published var oopAlarm: String = ""
    @Published var oopTrend: String = ""
    @Published var sensorSerial: String = ""
    @Published var sensorAge: Int = 0
    @Published var sensorState: String = "Scanning..."
    @Published var transmitterState: String = ""
    @Published var transmitterFirmware: String = ""
    @Published var transmitterHardware: String = "Scanning..."

    @Published var readingTimer: Int = -1
    @Published var params: CalibrationParameters = CalibrationParameters(slopeSlope: 0.0, slopeOffset: 0.0, offsetOffset: 0.0, offsetSlope: 0.0)
}

class Log: ObservableObject {
    @Published var text: String = "Log \(Date ())\n"
}

class Info: ObservableObject {
    @Published var text: String = "Info"
}

class History: ObservableObject {
    @Published var values: [Int] = []
    @Published var rawValues: [Int] = []
    @Published var rawTrend: [Int] = []
}

class Settings: ObservableObject {
    @Published var readingInterval: Int = 5

    // TODO: a GlucoseRange struct
    @Published var glucoseLow: Double = 70.0
    @Published var glucoseHigh: Double = 180.0
    @Published var alarmLow: Double = 70.0
    @Published var alarmHigh: Double = 220.0


    @Published var logging: Bool = true
    @Published var reversedLog: Bool = true

    @Published var numberFormatter = NumberFormatter()
    
    @Published var oopServerSite: String = "https://www.glucose.space/"
    @Published var oopServerToken: String = "bubble-201907"
}

public class MainDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    var app: App
    var log: Log
    var info: Info
    var history: History
    var settings: Settings

    var centralManager: CBCentralManager
    var nfcReader: NFCReader
    var audioPlayer = try! AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "alarm_high", ofType: "mp3")!), fileTypeHint: "mp3")

    override init() {
        app = App()
        log = Log()
        info = Info()
        history = History()
        settings = Settings()

        // TODO: option CBCentralManagerOptionRestoreIdentifierKey
        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        self.nfcReader = NFCReader()

        super.init()

        self.centralManager.delegate = self
        self.nfcReader.main = self

        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 6
        self.settings.numberFormatter = numberFormatter

    }


    public func log(_ text: String) {
        if self.settings.logging || text.hasPrefix("Log") {
            if self.settings.reversedLog {
                log.text = "\(text)\n\(log.text)"
            } else {
                log.text.append("\(text)\n")
            }
        }
        print("\(text)")
    }

    public func info(_ text: String) {
        if text.prefix(2) == "\n\n" {
            info.text = String(text.dropFirst(2))
        } else if !info.text.contains(text) {
            info.text.append(" \(text)")
        }
    }

    public func playAlarm() {
        audioPlayer.currentTime = 25.0
        audioPlayer.play()
    }

    func parseSensorData(_ sensor: Sensor) {

        let fram = sensor.fram

        log("Sensor: header CRC16: \(fram[0...1].hex), computed: \(String(format: "%04x", crc16(fram[2...23])))")
        log("Sensor: body CRC16: \(fram[24...25].hex), computed: \(String(format: "%04x", crc16(fram[26...319])))")
        log("Sensor: footer CRC16: \(fram[320...321].hex), computed: \(String(format: "%04x", crc16(fram[322...343])))")

        log("Sensor state: \(sensor.state)")
        app.sensorState = sensor.state.description
        log("Sensor age \(sensor.age), days: \(String(format: "%.2f", Double(sensor.age)/60/24))")
        app.sensorAge = sensor.age

        var trend = [GlucoseMeasurement]()
        var history = [GlucoseMeasurement]()
        let trendIndex = Int(fram[26])
        let historyIndex = Int(fram[27])

        for i in 0 ... 15 {
            var j = trendIndex - 1 - i
            if j < 0 { j += 16 }
            let rawGlucose = (Int(fram[29+j*6]) & 0x1F) << 8 + Int(fram[28+j*6])
            let rawTemperature = (Int(fram[32+j*6]) & 0x3F) << 8 + Int(fram[31+j*6])
            trend.append(GlucoseMeasurement(rawGlucose: rawGlucose, rawTemperature: rawTemperature))
        }
        log("Raw trend: \(trend.map{ $0.rawGlucose })")

        for i in 0 ... 31 {
            var j = historyIndex - 1 - i
            if j < 0 { j += 32 }
            let rawGlucose = (Int(fram[125+j*6]) & 0x1F) << 8 + Int(fram[124+j*6])
            let rawTemperature = (Int(fram[128+j*6]) & 0x3F) << 8 + Int(fram[127+j*6])
            history.append(GlucoseMeasurement(rawGlucose: rawGlucose, rawTemperature: rawTemperature))
        }
        log("Raw history: \(history.map{ $0.rawGlucose })")

        self.history.rawValues = history.map{ $0.glucose }
        self.history.rawTrend  = trend.map{ $0.glucose }


        log("Sending FRAM to \(settings.oopServerSite) for calibration...")
        postToLibreOOP(site: settings.oopServerSite, token: settings.oopServerToken, bytes: fram) { data, errorDescription in
            if let data = data {
                let json = String(decoding: data, as: UTF8.self)
                self.log("LibreOOP Server calibration response: \(json))")
                let decoder = JSONDecoder.init()
                if let oopCalibration = try? decoder.decode(OOPCalibrationResponse.self, from: data) {
                    let params = oopCalibration.parameters
                    for measurement in history {
                        measurement.calibrationParameters = params
                    }
                    for measurement in trend {
                        measurement.calibrationParameters = params
                    }
                    self.app.params = params
                    // TODO: store new app.history.calibratedValues and display a blue curve
                }

            } else {
                self.log("LibreOOP calibration failed")
                self.info("\nLibreOOP calibration failed")
            }
            return
        }

        if sensor.patchInfo.count > 0 {
            log("Sending FRAM to \(settings.oopServerSite) for measurements...")

            postToLibreOOP(site: settings.oopServerSite, token: settings.oopServerToken, bytes: fram, patchUid: sensor.uid, patchInfo: sensor.patchInfo) { data, errorDescription in
                if let data = data {
                    let json = String(decoding: data, as: UTF8.self)
                    self.log("LibreOOP Server measurements response: \(json)")
                    if json.contains("errcode") {
                        self.info("\n\(json)")
                        self.log("LibreOOP measurements failed")
                        self.info("\nLibreOOP measurements failed")
                        self.history.values = []
                    } else {
                        let decoder = JSONDecoder.init()
                        if let oopData = try? decoder.decode(OOPHistoryData.self, from: data) {
                            let realTimeGlucose = oopData.realTimeGlucose.value
                            self.app.currentGlucose = realTimeGlucose
                            UIApplication.shared.applicationIconBadgeNumber = realTimeGlucose
                            // PROJECTED_HIGH_GLUCOSE | HIGH_GLUCOSE | GLUCOSE_OK | LOW_GLUCOSE | PROJECTED_LOW_GLUCOSE | NOT_DETERMINED
                            self.app.oopAlarm = oopData.alarm
                            if self.app.currentGlucose > 0 && (self.app.currentGlucose > Int(self.settings.alarmHigh) || self.app.currentGlucose < Int(self.settings.alarmLow)) {
                                self.log("Alarm: current: \(self.app.currentGlucose), high: \(Int(self.settings.alarmHigh)), low: \(Int(self.settings.alarmLow))")
                                self.playAlarm()
                            }
                            // FALLING_QUICKLY | FALLING | STABLE | RISING | RISING_QUICKLY | NOT_DETERMINED
                            self.app.oopTrend = oopData.trendArrow
                            let (_, history) = oopData.glucoseData(date: Date())
                            let oopHistory = history.map { $0.glucose }
                            if oopHistory.count > 0 {
                                self.history.values = oopHistory
                            } else {
                                self.history.values = []
                            }
                            self.log("OOP history: \(oopHistory)")
                        } else {
                            self.log("Missing LibreOOP Data")
                            self.info("\nMissing LibreOOP data")
                        }
                    }
                } else {
                    self.history.values = []
                    self.log("LibreOOP connection failed")
                    self.info("\nLibreOOP connection failed")
                }
                return
            }
        }
    }


    public func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOff:
            log("Bluetooth: Powered off")
            if app.transmitter != nil {
                centralManager.cancelPeripheralConnection(app.transmitter.peripheral!)
                app.transmitter.state = .disconnected
            }
            app.transmitterState = "Disconnected"
            app.readingTimer = -1
        case .poweredOn:
            log("Bluetooth: Powered on")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        case .resetting: log("Bluetooth: Resetting")
        case .unauthorized: log("Bluetooth: Unauthorized")
        case .unknown: log("Bluetooth: Unknown")
        case .unsupported: log("Bluetooth: Unsupported")
        @unknown default:
            log("Bluetooth: Unknown state")
        }
    }

    public func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData advertisement: [String : Any], rssi: NSNumber) {
        let name = peripheral.name ?? "Unnamed peripheral"
        var found = false
        for transmitterType in TransmitterType.allCases {
            if name.lowercased().contains(transmitterType.rawValue) {
                found = true
                if app.preferredTransmitter != .none && transmitterType != app.preferredTransmitter {
                    found = false
                }
            }
        }
        if !found {
            log("Skipping \"\(name)\" service")
            return
        }

        log("Found \"\(name)\" peripheral (RSSI: \(rssi))")
        log("Advertisement data: \(advertisement)")
        log("Attempting to connect to \(name)")
        centralManager.stopScan()
        if peripheral.name == "Bubble" {
            app.transmitter = Bubble(peripheral: peripheral, main: self)
        } else if peripheral.name == "Droplet" {
            app.transmitter = Droplet(peripheral: peripheral, main: self)
        } else if peripheral.name!.hasPrefix("LimiTTer") {
            app.transmitter = Limitter(peripheral: peripheral, main: self)
        } else if peripheral.name!.contains("miaomiao") {
            app.transmitter = MiaoMiao(peripheral: peripheral, main: self)
        }
        info("\n\n\(app.transmitter.name)")
        app.transmitter.peripheral?.delegate = self
        if let manifacturerData = advertisement["kCBAdvDataManufacturerData"] as? Data {
            var firmware = ""
            var hardware = ""
            if app.transmitter.type == .bubble {
                let macAddress = Data(manifacturerData[2...7]).reduce("", { $0 + String(format: "%02X", $1) + ":"}).dropLast(1)
                let transmitterData = Data(manifacturerData.suffix(4))
                firmware = "\(Int(transmitterData[0])).\(Int(transmitterData[1]))"
                hardware = "\(Int(transmitterData[2])).\(Int(transmitterData[3]))"
                hardware = "V \(hardware)\n\(macAddress)"
            }
            app.transmitter.firmware = firmware
            app.transmitter.hardware = hardware
            app.transmitterFirmware = firmware
            app.transmitterHardware = hardware
        }
        centralManager.connect(app.transmitter.peripheral!, options: nil)
    }

    public func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("\(peripheral.name!) has connected.")
        if app.transmitter.state == .disconnected {
            app.transmitter.state = peripheral.state
            app.transmitterState = "Connected"
            log("Bluetooth: requesting service discovery")
            peripheral.discoverServices(nil)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        app.transmitter.state = peripheral.state
        if let services = peripheral.services {
            for service in services {
                log("Discovered \(peripheral.name!)'s service \(service.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics
            else { log("Unable to retrieve service characteristics"); return }

        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString
            var msg = "Discovered \(app.transmitter.name)'s caracteristic \(uuid)"

            if uuid == Droplet.dataReadCharacteristicUUID || uuid == MiaoMiao.dataReadCharacteristicUUID || uuid == Bubble.dataReadCharacteristicUUID {
                app.transmitter.readCharacteristic = characteristic
                app.transmitter.peripheral?.setNotifyValue(true, for: app.transmitter.readCharacteristic!)
                msg += " (data read)"
            }

            if uuid == Droplet.dataWriteCharacteristicUUID || uuid == MiaoMiao.dataWriteCharacteristicUUID || uuid == Bubble.dataWriteCharacteristicUUID {
                msg += " (data write)"
                app.transmitter.writeCharacteristic = characteristic
            }

            if uuid ==  Transmitter.batteryVoltageCharacteristicUUID {
                msg += " (battery voltage): reading it"
                app.transmitter.peripheral?.readValue(for: characteristic)
            }
            if uuid == Transmitter.modelCharacteristicUUID {
                msg += " (model number): reading it"
                app.transmitter.peripheral?.readValue(for: characteristic)
            }
            if uuid == Transmitter.serialCharacteristicUUID {
                msg += " (serial number): reading it"
                app.transmitter.peripheral?.readValue(for: characteristic)
            }
            if uuid == Transmitter.firmwareCharacteristicUUID {
                msg += " (firmware version): reading it"
                app.transmitter.peripheral?.readValue(for: characteristic)
            }
            if uuid == Transmitter.hardwareCharacteristicUUID {
                msg += " (hardware version): reading it"
                app.transmitter.peripheral?.readValue(for: characteristic)
            }
            if uuid == Transmitter.softwareCharacteristicUUID {
                msg += " (software version): reading it"
                app.transmitter.peripheral?.readValue(for: characteristic)
            }
            if uuid == Transmitter.manufacturerCharacteristicUUID {
                msg += " (manufacturer): reading it"
                app.transmitter.peripheral?.readValue(for: characteristic)
            }
            log(msg)
        }

        if app.transmitter.type == .bubble && service.uuid.uuidString == Bubble.dataServiceUUID {
            app.transmitter.write(app.transmitter.readCommand(interval: self.settings.readingInterval))
            log("Bubble: writing start reading command 0x0000\(self.settings.readingInterval)")
            // bubble!.write([0x00, 0x01, 0x05])
            // log("Bubble: writing reset and send data every 5 minutes command 0x000105")
        }

        if app.transmitter.type == .droplet && service.uuid.uuidString == Droplet.dataServiceUUID {

            // https://github.com/MarekM60/eDroplet/blob/master/eDroplet/eDroplet/ViewModels/CgmPageViewModel.cs
            // Droplet - New Protocol.pdf: https://www.facebook.com/download/preview/961042740919138

            // app.transmitter.write([0x31, 0x32, 0x33]); log("Droplet: writing old ping command")
            // app.transmitter.write([0x34, 0x35, 0x36]); log("Droplet: writing old read command")
            // app.transmitter.write([0x50, 0x00, 0x00]); log("Droplet: writing ping command P00")
            // app.transmitter.write([0x54, 0x00, 0x01]); log("Droplet: writing timer command T01")
            // TODO: T05 = 5 minutes, T00 = quiet mode
            app.transmitter.write([0x53, 0x00, 0x00]); log("Droplet: writing sensor identification command S00")
            app.transmitter.write([0x43, 0x00, 0x01]); log("Droplet: writing FRAM reading command C01")
            // app.transmitter.write([0x43, 0x00, 0x02]); log("Droplet: writing FRAM reading command C02")
            // app.transmitter.write([0x42, 0x00, 0x01]); log("Droplet: writing RAM reading command B01")
            // app.transmitter.write([0x42, 0x00, 0x02]); log("Droplet: writing RAM reading command B02")
            // TODO: "A0xyz...z” sensor activation where: x=1 for Libre 1, 2 for Libre 2 and US 14-day, 3 for Libre Pro/H; y = length of activation bytes, z...z = activation bytes
        }

        if app.transmitter.type == .limitter && service.uuid.uuidString == Limitter.dataServiceUUID {
            // app.transmitter.write([0x31, 0x32, 0x33]); log("Limitter: writing old ping command")
            // app.transmitter.write([0x34, 0x35, 0x36]); log("Limitter: writing old read command")
            app.transmitter.write([0x21]); log("LimiTTer: writing old timer (1 minute) command")
            // TODO: varying frequency: 0x2X
            app.transmitter.peripheral?.readValue(for: app.transmitter.readCharacteristic!)
            log("LimiTTer: reading data")
        }

        if app.transmitter.type == .miaomiao && service.uuid.uuidString == MiaoMiao.dataServiceUUID {
            app.transmitter.write([0xF0])
            log("MiaoMiao: writing start reading command F0")
            // app.transmitter.write([0xD3, 0x01]); log("MiaoMiao writing start new sensor command D301")
            // TODO: normalFrequency: [0xD1, 0x03], shortFrequency: [0xD1, 0x01], startupFrequency: [0xD1, 0x05]
        }
    }

    public func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        app.transmitter.state = peripheral.state
        log("\(peripheral.name!) has disconnected.")
        if error != nil {
            let errorCode = CBError.Code(rawValue: (error! as NSError).code)! // 6 = timed out when out of range
            log("Bluetooth error type \(errorCode.rawValue): \(error!.localizedDescription)")
            if app.transmitter != nil && (app.preferredTransmitter == .none || app.preferredTransmitter == app.transmitter.type) {
                centralManager.connect(peripheral, options: nil)
            }
        }
        app.transmitterState = "Disconnected"
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            log("Error while writing \(peripheral.name!) characteristic \(characteristic.uuid.uuidString) value: \(error!.localizedDescription)")
        } else {
            log("\(peripheral.name!) did write characteristic value for \(characteristic.uuid.uuidString)")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        var characteristicString = characteristic.uuid.uuidString
        if [Bubble.dataReadCharacteristicUUID, Droplet.dataReadCharacteristicUUID, MiaoMiao.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }
        log("\(peripheral.name!) did update notification state for \(characteristicString) characteristic")
    }


    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        var characteristicString = characteristic.uuid.uuidString
        if [Bubble.dataReadCharacteristicUUID, Droplet.dataReadCharacteristicUUID, MiaoMiao.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }
        log("\(peripheral.name!) did update value for \(characteristicString) characteristic")

        guard let data = characteristic.value
            else { log("Missing updated value"); return }

        log("\(data.count) bytes received")

        switch characteristic.uuid.uuidString {

        case Transmitter.batteryVoltageCharacteristicUUID:
            let result = Int(data[0])
            log("Battery level: \(result)")
            app.transmitter.battery = result
            app.battery = result

        case Transmitter.modelCharacteristicUUID:
            let model = String(decoding: data, as: UTF8.self)
            log("Model Number: \(model)")
            app.transmitterHardware += "\n\(model)"

        case Transmitter.serialCharacteristicUUID:
            let serial = String(decoding: data, as: UTF8.self)
            log("Serial Number: \(serial)")

        case Transmitter.firmwareCharacteristicUUID:
            let firmware = String(decoding: data, as: UTF8.self)
            log("Firmware version: \(firmware)")
            if peripheral.name! == "Droplet" { app.transmitter.firmware = firmware }
            if peripheral.name!.contains("LimiTTer") { app.transmitter.firmware = firmware }
            app.transmitterFirmware = firmware

        case Transmitter.hardwareCharacteristicUUID:
            let hardware = String(decoding: data, as: UTF8.self)
            log("Hardware version: \(hardware)")
            app.transmitterHardware += "\nV\(hardware)"

        case Transmitter.softwareCharacteristicUUID:
            let software = String(decoding: data, as: UTF8.self)
            log("Software version: \(software)")

        case Transmitter.manufacturerCharacteristicUUID:
            let manufacturer = String(decoding: data, as: UTF8.self)
            log("Manufacturer: \(manufacturer)")
            app.transmitterHardware = manufacturer

        default:
            log("(string: \"" + String(decoding: data, as: UTF8.self) + "\", hex: " + data.hex + ")")
            self.app.readingTimer = self.settings.readingInterval * 60 - 4

            app.transmitter.read(data)

            // TODO: use directly transmitter and sensor in ContentView
            app.battery = app.transmitter.battery
            if let sensor = app.transmitter.sensor {
                app.sensorSerial = sensor.serial
                app.sensorAge = sensor.age
            }
            app.transmitterFirmware = app.transmitter.firmware
            app.transmitterHardware = app.transmitter.hardware

            if app.transmitter.type == .bubble || app.transmitter.type == .miaomiao {
                if let sensor = app.transmitter.sensor, sensor.fram.count > 0, app.transmitter.buffer.count >=  sensor.fram.count  {
                    parseSensorData(sensor)
                    app.transmitter.buffer = Data()
                }
            } else if app.transmitter.type == .limitter && app.transmitter.sensor != nil {
                app.currentGlucose = app.transmitter.sensor!.currentGlucose
            }
        }
    }
}
