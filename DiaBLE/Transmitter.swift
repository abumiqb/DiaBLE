import Foundation
import CoreBluetooth

enum TransmitterType: String, CaseIterable, Hashable, Identifiable {
    case none, bubble, droplet, limitter, miaomiao
    var id: String { rawValue }
}


class Transmitter {

    static let deviceInfoServiceUUID = "180A"
    static let modelCharacteristicUUID    = "2A24"
    static let serialCharacteristicUUID   = "2A25"
    static let firmwareCharacteristicUUID = "2A26"
    static let hardwareCharacteristicUUID = "2A27"
    static let softwareCharacteristicUUID = "2A28"
    static let manufacturerCharacteristicUUID = "2A29"

    static let batteryInfoServiceUUID = "180F"
    static let batteryVoltageCharacteristicUUID = "2A19"

    class var dataServiceUUID: String { "" }
    class var dataReadCharacteristicUUID: String { "" }
    class var dataWriteCharacteristicUUID: String { "" }

    func readCommand(interval: Int = 5) -> [UInt8] { [] }

    var type: TransmitterType { TransmitterType.none }
    var name: String { "Unknown" }

    var peripheral: CBPeripheral?

    /// Main app delegate to use its log()
    var main: MainDelegate!

    /// Updated when notified by the Bluetooth manager
    var state: CBPeripheralState = .disconnected

    var readCharacteristic: CBCharacteristic?
    var writeCharacteristic: CBCharacteristic?

    var battery: Int = -1
    var firmware = ""
    var hardware = ""
    var buffer = Data()

    var sensor: Sensor?

    init(peripheral: CBPeripheral, main: MainDelegate) {
        self.peripheral = peripheral
        self.main = main
    }

    init() {
    }

    func write(_ bytes: [UInt8]) {
        peripheral?.writeValue(Data(bytes), for: writeCharacteristic!, type: .withoutResponse)
    }

    func read(_ data: Data) {
    }
}


class Bubble: Transmitter {
    override var type: TransmitterType { TransmitterType.bubble }
    override var name: String { "Bubble" }
    override class var dataServiceUUID: String { "6E400001-B5A3-F393-E0A9-E50E24DCCA9E" }
    override class var dataReadCharacteristicUUID: String { "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" }
    override class var dataWriteCharacteristicUUID: String { "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" }

    enum ResponseType: UInt8, CustomStringConvertible {
        case dataInfo =     0x80
        case dataPacket =   0x82
        case noSensor =     0xBF
        case serialNumber = 0xC0
        case patchInfo =    0xC1

        var description: String {
            switch self {
            case .dataInfo:
                return "data info received"
            case .dataPacket:
                return "data packet received"
            case .noSensor:
                return "no sensor detected"
            case .serialNumber:
                return "serial number received"
            case .patchInfo:
                return "patch info received"
            }
        }
    }

    override func readCommand(interval: Int = 5) -> [UInt8] {
        return [0x00, 0x00, UInt8(interval)]
    }

    override func read(_ data: Data) {

        // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/Models/Bubble.java

        let response = ResponseType(rawValue: data[0])
        main.log("\(name) response: \(response!) (0x\(data[0...0].hex))")

        if response == .noSensor {
            // TODO: confirm receipt the first time
            // bubble!.write([0x02, 0x01, 0x00, 0x00, 0x00, 0x2B])
            main.info("\n\n\(name): no sensor")

        } else if response == .dataInfo {
            // keep the manufacturer data advertised via Bluetooth (MAC address in the second line)
            // firmware and advertised hardware versions are different: V 2.0 and 1.0
            let firmwareHardware = "\(data[2]).0"
            let hardwareLines = hardware.split(separator: "\n")
            if hardwareLines.count == 2 {
                if !(hardwareLines[0].hasSuffix(")")) {
                    hardware = "\(hardwareLines[0]) (\(firmwareHardware))\n\(hardwareLines[1])"
                }
            } else {
                hardware = firmwareHardware
            }
            main.log("\(name): hardware version (in firmware): \(firmwareHardware)")
            battery = Int(data[4])
            main.log("\(name): battery level: \(battery)")
            firmware = "\(data[2]).\(data[3])"
            main.log("\(name): firmware: \(firmware)")
            // confirm receipt
            write([0x02, 0x01, 0x00, 0x00, 0x00, 0x2B])

        } else {
            if sensor == nil {
                sensor = Sensor(transmitter: self)
                main.app.sensor = sensor
            }
            if response == .serialNumber {
                sensor!.uid = Data(data[2...9])
                main.log("\(name): patch uid: \(sensor!.uid.hex)")
                main.log("\(name): sensor serial number: \(sensor!.serial)")

            } else if response == .patchInfo {
                sensor!.patchInfo = Data(Double(firmware)! < 1.35 ? data[3...8] : data[5...10])
                main.log("\(name): patch info: \(sensor!.patchInfo.hex)")

            } else if response == .dataPacket {
                buffer.append(data.suffix(from: 4))
                main.log("\(name): partial buffer count: \(buffer.count)")
                if buffer.count == 352 {
                    let fram = buffer[..<344]
                    // let footer = buffer.suffix(8)
                    sensor!.fram = Data(fram)
                    main.info("\n\n \(sensor!.type)  +  \(name)")
                }
            }
        }
    }
}


class Droplet: Transmitter {
    override var type: TransmitterType { TransmitterType.droplet }
    override var name: String { "Droplet" }
    override class var dataServiceUUID: String { "C97433F0-BE8F-4DC8-B6F0-5343E6100EB4" }
    override class var dataReadCharacteristicUUID: String { "C97433F1-BE8F-4DC8-B6F0-5343E6100EB4" }
    override class var dataWriteCharacteristicUUID: String { "C97433F2-BE8F-4DC8-B6F0-5343E6100EB4" }

    enum LibreType: String, CustomStringConvertible {
        case L1   = "10"
        case L2   = "20"
        case US14 = "30"
        case Lpro = "40"

        var description: String {
            switch self {
            case .L1:
                return "Libre 1"
            case .L2:
                return "Libre 2"
            case .US14:
                return "Libre US 14d"
            case .Lpro:
                return "Libre Pro"
            }
        }
    }

    override func read(_ data: Data) {
        if sensor == nil {
            sensor = Sensor(transmitter: self)
            main.app.sensor = sensor
        }
        if data.count == 8 {
            sensor!.uid = Data(data)
            main.log("\(name): sensor serial number: \(sensor!.serial))")
        } else {
            main.log("\(name) response: 0x\(data[0...0].hex)")
            main.log("\(name) response data length: \(Int(data[1]))")
        }
        // TODO:  9999 = error    }
    }
}


class Limitter: Droplet {
    override var type: TransmitterType { TransmitterType.limitter }

    override func read(_ data: Data) {

        // https://github.com/JohanDegraeve/xdripswift/tree/master/xdrip/BluetoothTransmitter/CGM/Libre/Droplet
        // https://github.com/SpikeApp/Spike/blob/master/src/services/bluetooth/CGMBluetoothService.as

        if sensor == nil {
            sensor = Sensor(transmitter: self)
        }

        let fields = String(decoding: data, as: UTF8.self).split(separator: " ")
        guard fields.count == 4 else { return }

        battery = Int(fields[2])!
        main.log("\(name): battery: \(battery)")

        let firstField = fields[0]
        guard !firstField.hasPrefix("000") else {
            main.log("\(name): no sensor data")
            main.info("\n\\(name): no sensor data")
            if firstField.hasSuffix("999") {
                let err = fields[1]
                main.log("\(name): error \(err)\n(0001 = low battery, 0002 = badly positioned)")
            }
            return
        }

        let rawValue = Int(firstField.dropLast(2))!
        main.log("\(name): Glucose raw value: \(rawValue)")
        main.info("\n\nDroplet raw glucose: \(rawValue)")
        sensor!.currentGlucose = rawValue / 10

        let sensorType = LibreType(rawValue: String(firstField.suffix(2)))!.description
        main.log("\name): sensor type = \(sensorType)")

        sensor!.age = Int(fields[3])! * 10
        main.log("\(name): sensor age: \(Int(sensor!.age)) (\(String(format: "%.1f", Double(sensor!.age)/60/24)) days)")
    }
}


class MiaoMiao: Transmitter {
    override var type: TransmitterType { TransmitterType.miaomiao }

    override var name: String {
        var name = "MiaoMiao"
        if let peripheral = peripheral, peripheral.name!.contains("miaomiao2") {
            name += " 2"
        }
        return name
    }
    
    override class var dataServiceUUID: String { "6E400001-B5A3-F393-E0A9-E50E24DCCA9E" }
    override class var dataReadCharacteristicUUID: String  { "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" }
    override class var dataWriteCharacteristicUUID: String { "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" }

    enum ResponseType: UInt8, CustomStringConvertible {
        case dataPacket = 0x28
        case newSensor  = 0x32
        case noSensor   = 0x34
        case frequencyChange = 0xD1

        var description: String {
            switch self {
            case .dataPacket:
                return "data packet received"
            case .newSensor:
                return "new sensor detected"
            case .noSensor:
                return "no sensor detected"
            case .frequencyChange:
                return "reading frequency change"
            }
        }
    }

    // TODO: test
    override func readCommand(interval: Int = 5) -> [UInt8] {
        var command = [UInt8(0xF0)]
        if [1, 3, 5].contains(interval) {
            command.insert(contentsOf: [0xD3, UInt8(interval)], at: 0)
        }
        return command
    }

    override func read(_ data: Data) {
        
        // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/Models/Tomato.java
        // https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Bluetooth/MiaoMiaoManager.swift
        // https://github.com/gshaviv/ninety-two/blob/master/WoofWoof/MiaoMiao.swift

        let response = ResponseType(rawValue: data[0])
        if buffer.count == 0 {
            main.log("\(name) response: \(response!) (0x\(data[0...0].hex))")
        }
        if data.count == 1 {
            if response == .noSensor {
                main.info("\n\n\(name): no sensor")
            }
            if response == .newSensor {
                main.info("\n\n\(name): new sensor detected")
            }
        } else if data.count == 2 {
            if response == .frequencyChange {
                if data[1] == 0x01 {
                    main.log("\(name): success changing frequency")
                } else {
                    main.log("\(name): failed to change frequency")
                }
            }
        } else {
            if sensor == nil {
                sensor = Sensor(transmitter: self)
                main.app.sensor = sensor
            }
            buffer.append(data)
            main.log("\(name): partial buffer count: \(buffer.count)")
            if buffer.count >= 363 {
                main.log("\(name) data count: \(Int(buffer[1]) << 8 + Int(buffer[2]))")
                sensor!.age = Int(buffer[3]) << 8 + Int(buffer[4])
                main.log("\(name): sensor age: \(sensor!.age), days: \(String(format: "%.1f", Double(sensor!.age)/60/24))")

                sensor!.uid = Data(buffer[5...12])
                main.log("\(name): patch uid: \(sensor!.uid.hex)")
                main.log("\(name): sensor serial number: \(sensor!.serial)")

                battery = Int(buffer[13])
                main.log("\(name): battery: \(battery)")

                firmware = buffer[14...15].hex
                hardware = buffer[16...17].hex
                main.log("\(name): firmware: \(firmware), hardware: \(hardware)")

                if buffer.count > 363 {
                    sensor!.patchInfo = Data(buffer[363...368])
                    main.log("\(name): patch info: \(sensor!.patchInfo.hex)")
                } else {
                    // https://github.com/dabear/LibreOOPAlgorithm/blob/master/app/src/main/java/com/hg4/oopalgorithm/oopalgorithm/AlgorithmRunner.java
                    sensor!.patchInfo = Data([0xDF, 0x00, 0x00, 0x01, 0x01, 0x02])
                }

                sensor!.fram = Data(buffer[18 ..< 362])
                main.info("\n\n \(sensor!.type)  +  \(name)")
            }
        }
    }
}
