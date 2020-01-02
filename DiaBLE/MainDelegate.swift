import SwiftUI
import CoreBluetooth
import AVFoundation


public class MainDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, UNUserNotificationCenterDelegate {

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
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        nfcReader = NFCReader()

        super.init()

        centralManager.delegate = self
        nfcReader.main = self

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _,_ in } // TODO
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, options: [.duckOthers])
        try! AVAudioSession.sharedInstance().setActive(true)

        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 6
        settings.numberFormatter = numberFormatter

    }


    public func log(_ text: String) {
        if settings.logging || text.hasPrefix("Log") {
            if settings.reversedLog {
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
        if !settings.mutedAudio {
            audioPlayer.currentTime = 25.0
            audioPlayer.play()
        }
        for s in 0...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(s)) {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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
        case .resetting:    log("Bluetooth: Resetting")
        case .unauthorized: log("Bluetooth: Unauthorized")
        case .unknown:      log("Bluetooth: Unknown")
        case .unsupported:  log("Bluetooth: Unsupported")
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
                if settings.preferredTransmitter != .none && transmitterType != settings.preferredTransmitter {
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
            let readCommand = app.transmitter.readCommand(interval: settings.readingInterval)
            app.transmitter.write(readCommand)
            log("Bubble: writing start reading command 0x\(Data(readCommand).hex)")
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
            // T05 = 5 minutes, T00 = quiet mode
            app.transmitter.write([0x53, 0x00, 0x00]); log("Droplet: writing sensor identification command S00")
            app.transmitter.write([0x43, 0x00, 0x01]); log("Droplet: writing FRAM reading command C01")
            // app.transmitter.write([0x43, 0x00, 0x02]); log("Droplet: writing FRAM reading command C02")
            // app.transmitter.write([0x42, 0x00, 0x01]); log("Droplet: writing RAM reading command B01")
            // app.transmitter.write([0x42, 0x00, 0x02]); log("Droplet: writing RAM reading command B02")
            // "A0xyz...z” sensor activation where: x=1 for Libre 1, 2 for Libre 2 and US 14-day, 3 for Libre Pro/H; y = length of activation bytes, z...z = activation bytes
        }

        if app.transmitter.type == .limitter && service.uuid.uuidString == Limitter.dataServiceUUID {
            let readCommand = app.transmitter.readCommand(interval: settings.readingInterval)
            app.transmitter.write(readCommand)
            log("Droplet (LimiTTer): writing start reading command 0x\(Data(readCommand).hex)")
            app.transmitter.peripheral?.readValue(for: app.transmitter.readCharacteristic!)
            log("Droplet (LimiTTer): reading data")
        }

        if app.transmitter.type == .miaomiao && service.uuid.uuidString == MiaoMiao.dataServiceUUID {
            //app.transmitter.write([0xF0])
            let readCommand = app.transmitter.readCommand(interval: settings.readingInterval)
            app.transmitter.write(readCommand)
            log("MiaoMiao: writing start reading command 0x\(Data(readCommand).hex)")
            // app.transmitter.write([0xD3, 0x01]); log("MiaoMiao writing start new sensor command D301")
        }
    }

    public func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        app.transmitter.state = peripheral.state
        log("\(peripheral.name!) has disconnected.")
        if error != nil {
            let errorCode = CBError.Code(rawValue: (error! as NSError).code)! // 6 = timed out when out of range
            log("Bluetooth error type \(errorCode.rawValue): \(error!.localizedDescription)")
            if app.transmitter != nil && (settings.preferredTransmitter == .none || settings.preferredTransmitter == app.transmitter.type) {
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
            app.transmitter.hardware += "\n\(model)"
            app.transmitterHardware = app.transmitter.hardware


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
            app.transmitter.hardware += "\nV\(hardware)"
            app.transmitterHardware = app.transmitter.hardware

        case Transmitter.softwareCharacteristicUUID:
            let software = String(decoding: data, as: UTF8.self)
            log("Software version: \(software)")

        case Transmitter.manufacturerCharacteristicUUID:
            let manufacturer = String(decoding: data, as: UTF8.self)
            log("Manufacturer: \(manufacturer)")
            app.transmitter.hardware = manufacturer
            app.transmitterHardware = app.transmitter.hardware

        default:
            log("(string: \"" + String(decoding: data, as: UTF8.self) + "\", hex: " + data.hex + ")")
            app.readingTimer = settings.readingInterval * 60

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
                if app.transmitter.sensor!.state != .unknown {
                    app.sensorState = app.transmitter.sensor!.state.description
                }
                didParseSensor(app.transmitter.sensor!)
            }
        }
    }


    func parseSensorData(_ sensor: Sensor) {

        log(sensor.crcReport)
        log("Sensor state: \(sensor.state)")
        app.sensorState = sensor.state.description
        log("Sensor age \(sensor.age), days: \(String(format: "%.2f", Double(sensor.age)/60/24))")
        app.sensorAge = sensor.age

        history.rawTrend = sensor.trend.map{ $0.glucose }
        log("Raw trend: \(sensor.trend.map{ $0.rawGlucose })")
        history.rawValues = sensor.history.map{ $0.glucose }
        log("Raw history: \(sensor.history.map{ $0.rawGlucose })")

        sensor.currentGlucose = -history.rawTrend[0]

        log("Sending FRAM to \(settings.oopServerSite) for calibration...")
        postToLibreOOP(site: settings.oopServerSite, token: settings.oopServerToken, bytes: sensor.fram) { data, errorDescription in
            if let data = data {
                let json = String(decoding: data, as: UTF8.self)
                self.log("LibreOOP Server calibration response: \(json))")
                let decoder = JSONDecoder.init()
                if let oopCalibration = try? decoder.decode(OOPCalibrationResponse.self, from: data) {
                    let params = oopCalibration.parameters
                    for measurement in sensor.history {
                        measurement.calibrationParameters = params
                    }
                    for measurement in sensor.trend {
                        measurement.calibrationParameters = params
                    }
                    self.app.params = params
                    // TODO: store new app.history.calibratedValues and display a third curve
                }

            } else {
                self.log("LibreOOP calibration failed")
                self.info("\nLibreOOP calibration failed")
            }
            if sensor.patchInfo.count == 0 {
                self.didParseSensor(sensor)
            }
            return
        }

        if sensor.patchInfo.count > 0 {
            log("Sending FRAM to \(settings.oopServerSite) for measurements...")

            postToLibreOOP(site: settings.oopServerSite, token: settings.oopServerToken, bytes: sensor.fram, patchUid: sensor.uid, patchInfo: sensor.patchInfo) { data, errorDescription in
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
                            if realTimeGlucose > 0 {
                                sensor.currentGlucose = realTimeGlucose
                            }
                            // PROJECTED_HIGH_GLUCOSE | HIGH_GLUCOSE | GLUCOSE_OK | LOW_GLUCOSE | PROJECTED_LOW_GLUCOSE | NOT_DETERMINED
                            self.app.oopAlarm = oopData.alarm
                            // FALLING_QUICKLY | FALLING | STABLE | RISING | RISING_QUICKLY | NOT_DETERMINED
                            self.app.oopTrend = oopData.trendArrow
                            var oopHistory = oopData.glucoseData(date: Date()).map { $0.glucose }
                            let oopHistoryCount = oopHistory.count
                            if oopHistoryCount > 0 {
                                if oopHistoryCount < 32 { // new sensor
                                    oopHistory.append(contentsOf: Array(repeating: -1, count: 32 - oopHistoryCount))
                                }
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
                self.didParseSensor(sensor)
                return
            }
        }
    }


    /// sensor.currentGlucose is negative if set to the last raw trend value
    func didParseSensor(_ sensor: Sensor) {

        var currentGlucose = sensor.currentGlucose

        // Display a negative value in parenthesis
        app.currentGlucose = currentGlucose

        currentGlucose = abs(currentGlucose)

        if currentGlucose > 0 && (currentGlucose > Int(settings.alarmHigh) || currentGlucose < Int(settings.alarmLow)) {
            log("ALARM: current glucose: \(currentGlucose), high: \(Int(settings.alarmHigh)), low: \(Int(settings.alarmLow))")
            playAlarm()
        }

        UIApplication.shared.applicationIconBadgeNumber = currentGlucose
    }
}
