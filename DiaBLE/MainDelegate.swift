import SwiftUI
import CoreBluetooth

class App: ObservableObject {

    // Replace the final .none with .bubble | .droplet | .limitter | .miaomiao
    @Published var preferredTransmitter = TransmitterType.none
    @Published var currentTransmitter: Transmitter!

    var main: MainDelegate!

    @Published var batteryLevel: Int = 0
    @Published var currentGlucose: Int = 0
    @Published var glucoseAlarm: String = ""
    @Published var glucoseTrend: String = ""
    @Published var sensorSerial: String = ""
    @Published var sensorStart: Int = 0
    @Published var sensorState: String = "Scanning..."
    @Published var transmitterState: String = ""
    @Published var transmitterFirmware: String = ""
    @Published var transmitterHardware: String = "Scanning..."
    @Published var nextReading: Int = 300
}

class Log: ObservableObject {
    @Published var text: String = "Log - \(Date ())\n"
}

class Info: ObservableObject {
    @Published var text: String = "Info"
}

class History: ObservableObject {
    @Published var values: [Int] = []
}

class Settings: ObservableObject {
    @Published var readingInterval: Int  = 5
    @Published var reversedLog: Bool = true
    @Published var oopServerSite: String = "http://www.glucose.space/"
    @Published var oopServerToken: String = "bubble-201907"
}


extension Data {
    var hex: String {
        self.reduce("", { $0 + String(format: "%02x", $1)})
    }
}

extension String {
    var base64: String? { self.data(using: .utf8)?.base64EncodedString() }
    var base64Data: Data? { Data(base64Encoded: self) }
}


public class MainDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    var app: App
    var log: Log
    var info: Info
    var history: History
    var settings: Settings

    var bubble: Bubble?
    var droplet: Droplet?
    var limitter: Limitter?
    var miaomiao: MiaoMiao?

    var centralManager: CBCentralManager
    var nfcReader: NFCReader

    override init() {
        app = App()
        log = Log()
        info = Info()
        history = History()
        settings = Settings()

        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        self.nfcReader = NFCReader()

        super.init()

        self.centralManager.delegate = self
        self.nfcReader.main = self

    }


    public func log(_ text: String) {
        if self.settings.reversedLog {
            log.text = "\(text)\n\(log.text)"
        } else {
            log.text.append("\(text)\n")
        }
        print("\(text)")
    }

    public func info(_ text: String) {
        if text.prefix(2) == "\n\n" {
            info.text = String(text.dropFirst(2))
        } else {
            info.text.append(" \(text)")
        }
    }


    func parseSensorData(transmitter: Transmitter) {
        let fram = transmitter.fram

        log("Sensor data: header CRC16: \(fram[0...1].hex), computed CRC16: \(String(format: "%04x", crc16(fram[2...23])))")
        log("Sensor data: body CRC16: \(fram[24...25].hex), computed CRC16: \(String(format: "%04x", crc16(fram[26...319])))")
        log("Sensor data: footer CRC16: \(fram[320...321].hex), computed CRC16: \(String(format: "%04x", crc16(fram[322...343])))")

        let sensorState = SensorState(rawValue: fram[4])!.description
        log("Sensor state: \(sensorState)")
        app.sensorState = sensorState
        let minutesSinceStart = Int(fram[317]) << 8 + Int(fram[316])
        let daysSinceStart = Double(minutesSinceStart)/60/24
        log("Sensor data: minutes since start: \(minutesSinceStart), days: \(daysSinceStart)")
        app.sensorStart = minutesSinceStart

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

        var historyValues = history.map{ $0.glucose }

        info("\n\nRaw history: [\(historyValues.map{ String($0) }.joined(separator: " "))]")
        log("Sending FRAM to \(settings.oopServerSite) for calibration...")

        postToLibreOOP(site: settings.oopServerSite, token: settings.oopServerToken , bytes: fram) { data, errorDescription in
            if let data = data {
                let json = String(decoding: data, as: UTF8.self)
                self.log("LibreOOP Server calibration response: \(json))")
                let decoder = JSONDecoder.init()
                if let oopCalibration = try? decoder.decode(OOPCalibrationResponse.self, from: data) {
                    let params = oopCalibration.parameters
                    self.log("OOP \(params)")

                    for measurement in history {
                        measurement.calibrationParameters = params
                    }
                    self.log("OOP calibrated history: \(history.map{ $0.glucose })")
                    self.info("\nOOP calibrated history: [\(history.map{ String($0.glucose) }.joined(separator: " "))]")

                    for measurement in trend {
                        measurement.calibrationParameters = params
                    }
                    self.log("OOP calibrated trend: \(trend.map{ $0.glucose })")
                    self.info("\nOOP calibrated trend: [\(trend.map{ String($0.glucose) }.joined(separator: " "))]")
                }
            } else {
                self.info("\nRaw trend: [\(trend.map{ String($0.glucose) }.joined(separator: " "))]")
                self.log("LibreOOP calibration failed")
                self.info("\nLibreOOP calibration failed")
                self.history.values = historyValues
            }
            return
        }

        if transmitter.patchInfo.count > 0 {
            log("Sending FRAM to \(settings.oopServerSite) for measurements...")

            postToLibreOOP(site: settings.oopServerSite, token: settings.oopServerToken, bytes: fram, patchUid: transmitter.patchUid, patchInfo: transmitter.patchInfo) { data, errorDescription in
                if let data = data {
                    let json = String(decoding: data, as: UTF8.self)
                    self.log("LibreOOP Server measurements response: \(json)")
                    if json.contains("errcode") {
                        self.info("\n\(json)")
                        self.log("LibreOOP measurements failed")
                        self.info("\nLibreOOP measurements failed")
                    } else {
                        let decoder = JSONDecoder.init()
                        if let oopData = try? decoder.decode(OOPHistoryData.self, from: data) {
                            let realTimeGlucose = oopData.realTimeGlucose.value
                            self.app.currentGlucose = realTimeGlucose
                            // PROJECTED_HIGH_GLUCOSE | HIGH_GLUCOSE | GLUCOSE_OK | LOW_GLUCOSE | PROJECTED_LOW_GLUCOSE | NOT_DETERMINED
                            self.app.glucoseAlarm = oopData.alarm
                            // FALLING_QUICKLY | FALLING | STABLE | RISING | RISING_QUICKLY | NOT_DETERMINED
                            self.app.glucoseTrend = oopData.trendArrow
                            let (_, history) = oopData.glucoseData(date: Date())
                            let oopHistory = history.map { $0.glucose }
                            if oopHistory.count > 0 {
                                historyValues = oopHistory
                            }
                            self.log("OOP history: \(oopHistory)")
                            self.info("\nOOP history: [\(oopHistory.map{ String($0) }.joined(separator: " "))]")
                        } else {
                            self.log("Missing LibreOOP Data")
                            self.info("\nMissing LibreOOP data")
                        }
                    }
                } else {
                    self.log("LibreOOP connection failed")
                    self.info("\nLibreOOP connection failed")
                }
                self.history.values = historyValues
                return
            }
        }
    }


    public func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOff:
            log("Bluetooth: Powered off")
            centralManager.stopScan()
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
        var transmitter: Transmitter!
        if peripheral.name == "Bubble" {
            bubble = Bubble(peripheral: peripheral)
            transmitter = bubble!
        } else if peripheral.name == "Droplet" {
            droplet = Droplet(peripheral: peripheral)
            transmitter = droplet!
        } else if peripheral.name!.hasPrefix("LimiTTer") {
            limitter = Limitter(peripheral: peripheral)
            transmitter = limitter!
        } else if peripheral.name!.contains("miaomiao") {
            miaomiao = MiaoMiao(peripheral: peripheral)
            transmitter = miaomiao!
        }
        info("\n\n\(transmitter.name)")
        app.currentTransmitter = transmitter
        transmitter.peripheral?.delegate = self
        if let manifacturerData = advertisement["kCBAdvDataManufacturerData"] as? Data {
            var firmware = ""
            var hardware = ""
            if transmitter.name == "Bubble" {
                let macAddress = Data(manifacturerData[2...7]).reduce("", { $0 + String(format: "%02X", $1) + ":"}).dropLast(1)
                let transmitterData = Data(manifacturerData.suffix(4))
                firmware = "\(Int(transmitterData[0])).\(Int(transmitterData[1]))"
                hardware = "\(Int(transmitterData[2])).\(Int(transmitterData[3]))"
                hardware = "V \(hardware)\n\(macAddress)"
            }
            app.transmitterFirmware = firmware
            app.transmitterHardware = hardware
        }
        centralManager.connect(transmitter.peripheral!, options: nil)
    }

    public func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let name = peripheral.name {
            log("\"\(name)\" has connected.")
            app.transmitterState = "Connected"
            log("Requesting service discovery.")
            peripheral.discoverServices(nil)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                log("Discovered service \(service.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics
            else { log("Unable to retrieve service characteristics"); return }
        var peripheralName = peripheral.name!
        var transmitter: Transmitter!

        if peripheralName == "Bubble" {
            transmitter = bubble
        }
        if peripheralName == "Droplet" {
            transmitter = droplet
        }
        if peripheralName.contains("LimiTTer") {
            peripheralName = "Limitter"
            transmitter = limitter
        }
        if peripheralName.contains("miaomiao") {
            peripheralName = "MiaoMiao"
            transmitter = miaomiao
        }

        for characteristic in characteristics {
            let name = characteristic.uuid.uuidString
            log("Discovered caracteristic uuid: \(name)")

            if name == Droplet.dataReadCharacteristicUUID || name == MiaoMiao.dataReadCharacteristicUUID || name == Bubble.dataReadCharacteristicUUID {
                transmitter.readCharacteristic = characteristic
                transmitter.peripheral?.setNotifyValue(true, for: transmitter.readCharacteristic!)
                log("Discovered \(peripheralName) dataReadCharacteristic")
            }

            if name == Droplet.dataWriteCharacteristicUUID || name == MiaoMiao.dataWriteCharacteristicUUID || name == Bubble.dataWriteCharacteristicUUID {
                log("Discovered \(peripheralName) dataWriteCharacteristic")
                transmitter.writeCharacteristic = characteristic
            }

            if name ==  Transmitter.batteryVoltageCharacteristicUUID {
                log("Discovered \(peripheralName) Battery Voltage characteristic")
                transmitter.peripheral?.readValue(for: characteristic)
                log("Reading battery level")
            }
            if name == Transmitter.modelCharacteristicUUID {
                log("Discovered \(peripheralName) Model Number Characteristic")
                transmitter.peripheral?.readValue(for: characteristic)
                log("Reading model number")
            }
            if name == Transmitter.serialCharacteristicUUID {
                log("Discovered \(peripheralName) Serial Number Characteristic")
                transmitter.peripheral?.readValue(for: characteristic)
                log("Reading serial number")
            }
            if name == Transmitter.firmwareCharacteristicUUID {
                log("Discovered \(peripheralName) Firmware Version Characteristic")
                transmitter.peripheral?.readValue(for: characteristic)
                log("Reading firmware version")
            }
            if name == Transmitter.hardwareCharacteristicUUID {
                log("Discovered \(peripheralName) Hardware Version Characteristic")
                transmitter.peripheral?.readValue(for: characteristic)
                log("Reading hardware version")
            }
            if name == Transmitter.softwareCharacteristicUUID {
                log("Discovered \(peripheralName) Software Version Characteristic")
                transmitter.peripheral?.readValue(for: characteristic)
                log("Reading software version")
            }
            if name == Transmitter.manufacturerCharacteristicUUID {
                log("Discovered \(peripheralName) Manufacturer Characteristic")
                transmitter.peripheral?.readValue(for: characteristic)
                log("Reading manifacturer name")
            }
        }

        if peripheralName == "Bubble" && service.uuid.uuidString == Bubble.dataServiceUUID {
            bubble!.write(bubble!.readCommand(interval: self.settings.readingInterval))
            log("Bubble: writing start reading command 0x0000\(self.settings.readingInterval)")
            // bubble!.write([0x00, 0x01, 0x05])
            // log("Bubble: writing reset and send data every 5 minutes command 0x000105")
        }

        if peripheralName == "Droplet" && service.uuid.uuidString == Droplet.dataServiceUUID {

            // https://github.com/MarekM60/eDroplet/blob/master/eDroplet/eDroplet/ViewModels/CgmPageViewModel.cs
            // Droplet - New Protocol.pdf: https://www.facebook.com/download/preview/961042740919138

            // droplet!.write([0x31, 0x32, 0x33]); log("Droplet: writing old ping command")
            // droplet!.write([0x34, 0x35, 0x36]); log("Droplet: writing old read command")
            // droplet!.write([0x50, 0x00, 0x00]); log("Droplet: writing ping command P00")
            // droplet!.write([0x54, 0x00, 0x01]); log("Droplet: writing timer command T01")
            // TODO: T05 = 5 minutes, T00 = quiet mode
            droplet!.write([0x53, 0x00, 0x00]); log("Droplet: writing sensor identification command S00")
            droplet!.write([0x43, 0x00, 0x01]); log("Droplet: writing FRAM reading command C01")
            // droplet!.write([0x43, 0x00, 0x02]); log("Droplet: writing FRAM reading command C02")
            // droplet!.write([0x42, 0x00, 0x01]); log("Droplet: writing RAM reading command B01")
            // droplet!.write([0x42, 0x00, 0x02]); log("Droplet: writing RAM reading command B02")
            // TODO: "A0xyz...z” sensor activation where: x=1 for Libre 1, 2 for Libre 2 and US 14-day, 3 for Libre Pro/H; y = length of activation bytes, z...z = activation bytes
        }

        if peripheralName == "Limitter" && service.uuid.uuidString == Limitter.dataServiceUUID {
            // limitter!.write([0x31, 0x32, 0x33]); log("Limitter: writing old ping command")
            // limitter!.write([0x34, 0x35, 0x36]); log("Limitter: writing old read command")
            limitter!.write([0x21]); log("LimiTTer: writing old timer command")
            limitter!.peripheral?.readValue(for: limitter!.readCharacteristic!)
            log("LimiTTer: reading data")
        }

        if peripheralName == "MiaoMiao" && service.uuid.uuidString == MiaoMiao.dataServiceUUID {
            miaomiao!.write([0xF0])
            log("MiaoMiao: writing start reading command F0")
            // miaomiao!.write([0xD3, 0x01]); log("MiaoMiao writing start new sensor command D301")
            // TODO: normalFrequency: [0xD1, 0x03], shortFrequency: [0xD1, 0x01], startupFrequency: [0xD1, 0x05]
        }
    }

    public func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let name = peripheral.name {
            log("\"\(name)\" has disconnected.")
            app.transmitterState = "Disconnected"
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        log("\(peripheral.name!) did write characteristic value for " + characteristic.uuid.uuidString)
        if error != nil {
            log("Did write error")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        log("\(peripheral.name!) did update notification state for " + characteristic.uuid.uuidString)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        var characteristicString = characteristic.uuid.uuidString
        if [Bubble.dataReadCharacteristicUUID, Droplet.dataReadCharacteristicUUID, MiaoMiao.dataReadCharacteristicUUID].contains(characteristicString) {
            characteristicString = "data read"
        }
        log("\(peripheral.name!) did update value for \( characteristicString) characteristic")

        guard let data = characteristic.value
            else { log("missing updated value"); return }

        log("\(data.count) bytes received")

        switch characteristic.uuid.uuidString {

        case Transmitter.batteryVoltageCharacteristicUUID:
            let result = Int(data[0])
            log("Battery level: \(result)")
            app.batteryLevel = result

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
            if peripheral.name! == "Droplet" { droplet!.firmware = firmware }
            if peripheral.name!.contains("LimiTTer") { limitter!.firmware = firmware }
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


            // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/Models/Bubble.java

            if peripheral.name! == "Bubble" {
                let response = Bubble.ResponseType(rawValue: data[0])
                log("Bubble: response: \(response!) (0x\(data[0...0].hex))")

                if response == .noSensor {
                    // TODO: confirm receipt the first time
                    // bubble!.write([0x02, 0x01, 0x00, 0x00, 0x00, 0x2B])
                    info("\n\nBubble: No sensor")

                } else if response == .dataInfo {
                    let hardware =  "\(data[2]).0"
                    log("Bubble: hardware: \(hardware)")
                    let batteryLevel = Int(data[4])
                    log("Bubble: battery level: \(batteryLevel)")
                    app.batteryLevel = batteryLevel
                    let firmware = "\(data[2]).\(data[3])"
                    bubble!.firmware = firmware
                    log("Bubble: firmware: \(firmware)")
                    // confirm receipt
                    bubble!.write([0x02, 0x01, 0x00, 0x00, 0x00, 0x2B])

                } else if response == .serialNumber {
                    let uid = data[2...9]
                    bubble!.patchUid = Data(uid)
                    log("Bubble: Patch UID: \(uid.hex)")
                    let serial = sensorSerialNumber(uid: uid)
                    log("Bubble: Sensor SN: \(serial)")
                    app.sensorSerial = serial

                } else if response == .patchInfo {
                    let info = Double(bubble!.firmware)! < 1.35 ? data[3...8] : data[5...10]
                    bubble!.patchInfo = Data(info)
                    log("Bubble: Patch info: \(info.hex)")

                } else if response == .dataPacket {
                    var buffer = bubble!.buffer
                    buffer.append(data.suffix(from: 4))
                    bubble!.buffer = buffer
                    log("Bubble: partial buffer count: \(buffer.count)")
                    if buffer.count == 352 {
                        let fram = buffer[..<344]
                        // TODO: let footer = buffer.suffix(8)
                        bubble!.fram = Data(fram)
                        parseSensorData(transmitter: bubble!)
                        bubble!.buffer = Data()
                    }
                }

            } else if peripheral.name! == "Droplet" {
                if data.count == 8 {
                    let serial = sensorSerialNumber(uid: data)
                    log("Droplet: Sensor SN: \(serial))")
                    app.sensorSerial = serial
                } else {
                    log("Droplet response: 0x\(data[0...0].hex)")
                    log("Droplet response data length: \(Int(data[1]))")
                }
                // TODO:  9999 = error

            } else if peripheral.name!.contains("LimiTTer") {
                // https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/Transmitter/CGMBluetoothTransmitter/Libre/Droplet/CGMDroplet1Transmitter.swift
                // https://github.com/SpikeApp/Spike/blob/master/src/services/bluetooth/CGMBluetoothService.as

                let fields = String(decoding: data, as: UTF8.self).split(separator: " ")
                guard fields.count == 4 else { return }

                let batteryLevel = Int(fields[2])!
                log("LimiTTer: battery level: \(batteryLevel)")
                app.batteryLevel = batteryLevel

                let firstField = fields[0]
                guard !firstField.hasPrefix("000") else {
                    log("LimiTTer: no sensor data")
                    info("\n\nLimitter: No sensor data")
                    if firstField.hasSuffix("999") {
                        let err = fields[1]
                        log("LimiTTer: error \(err)\n(0001 = low battery, 0002 = badly positioned)")
                    }
                    return
                }

                let rawValue = Int(firstField.dropLast(2))!
                log("LimiTTer: Glucose raw value: \(rawValue)")
                info("\n\nDroplet raw glucose: \(rawValue)")
                app.currentGlucose = rawValue / 10

                let sensorType = Droplet.LibreType(rawValue: String(firstField.suffix(2)))!.description
                log("LimiTTer: sensor type = \(sensorType)")
                app.sensorSerial = sensorType

                let sensorTimeInMinutes = Int(fields[3])! * 10
                log("LimiTTer: sensor time in minutes: \(Int(sensorTimeInMinutes)) (\(String(format: "%.1f", Double(sensorTimeInMinutes)/60/24)) days)")
                app.sensorStart = sensorTimeInMinutes


            } else if peripheral.name!.contains("miaomiao") {
                // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/Models/Tomato.java
                // https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Bluetooth/MiaoMiaoManager.swift
                // https://github.com/gshaviv/ninety-two/blob/master/WoofWoof/MiaoMiao.swift

                let response = MiaoMiao.ResponseType(rawValue: data[0])
                if miaomiao!.buffer.count == 0 {
                    log("MiaoMiao: response: \(response!) (0x\(data[0...0].hex))")
                }
                if data.count == 1 {
                    if response == .noSensor {
                        log("MiaoMiao: No sensor")
                        info("\n\nMiaoMiao: No sensor")
                    }
                    if response == .newSensor {
                        log("MiaoMiao: New sensor detected")
                        info("\n\nMiaoMiao: New sensor detected")
                    }
                } else if data.count == 2 {
                    if response == .frequencyChange {
                        if data[1] == 0x01 {
                            log("MiaoMiao: Success changing frequency")
                        } else {
                            log("MiaoMiao: Failed to change frequency")
                        }
                    }
                } else {
                    var buffer = miaomiao!.buffer
                    buffer.append(data)
                    miaomiao!.buffer = buffer
                    log("MiaoMiao: partial buffer count: \(buffer.count)")
                    if buffer.count >= 363 {
                        log("MiaoMiao buffer data count: \(buffer.count)")
                        log("MiaoMiao: data length: \(Int(buffer[1]) << 8 + Int(buffer[2]))")
                        let minutesSinceStart = Int(buffer[3]) << 8 + Int(buffer[4])
                        log("MiaoMiao: minutes since start: \(minutesSinceStart), days: \(String(format: "%.1f", Double(minutesSinceStart)/60/24))")
                        app.sensorStart = minutesSinceStart
                        let uid = buffer[5...12]
                        miaomiao!.patchUid = Data(uid)
                        log("MiaoMiao: Patch UID: \(uid.hex)")
                        let serial = sensorSerialNumber(uid: uid)
                        log("Miaomiao: Sensor SN: \(serial)")
                        app.sensorSerial = serial
                        let batteryLevel = Int(buffer[13])
                        log("MiaoMiao: battery level: \(batteryLevel)")
                        app.batteryLevel = batteryLevel

                        let firmware = buffer[14...15].hex
                        let hardware = buffer[16...17].hex
                        log("MiaoMiao: firmware: \(firmware), hardware: \(hardware)")
                        app.transmitterFirmware = firmware
                        app.transmitterHardware = hardware

                        if buffer.count > 363 {
                            let patchInfo = buffer[363...368]
                            miaomiao!.patchInfo = Data(patchInfo)
                            log("MiaoMiao: Patch info: \(patchInfo.hex)")
                        } else {
                            // https://github.com/dabear/LibreOOPAlgorithm/blob/master/app/src/main/java/com/hg4/oopalgorithm/oopalgorithm/AlgorithmRunner.java
                            miaomiao!.patchInfo = Data([0xDF, 0x00, 0x00, 0x01, 0x01, 0x02])
                        }

                        miaomiao!.fram = Data(buffer[18 ..< 362])
                        parseSensorData(transmitter: miaomiao!)
                        miaomiao!.buffer = Data()
                    }
                }
            }
        }
    }
}

