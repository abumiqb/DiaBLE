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

    /// Main app delegate to use its log()
    var main: MainDelegate!

    var peripheral: CBPeripheral?

    /// Updated when notified by the Bluetooth manager
    var state: CBPeripheralState = .disconnected

    var readCharacteristic: CBCharacteristic?
    var writeCharacteristic: CBCharacteristic?

    var battery: Int = 0
    var firmware = ""
    var hardware = ""
    var buffer = Data()

    var sensor: Sensor?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    init() {
    }

    func write(_ bytes: [UInt8]) {
        peripheral?.writeValue(Data(bytes), for: writeCharacteristic!, type: .withoutResponse)
    }

    func read(data: Data) {
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
}


class Limitter: Droplet {
    override var type: TransmitterType { TransmitterType.limitter }
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


    override func read(data: Data) {
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
            sensor = Sensor(transmitter: self)
            buffer.append(data)
            main.log("\(name): partial buffer count: \(buffer.count)")
            if buffer.count >= 363 {
                main.log("\(name) buffer data count: \(buffer.count)")
                main.log("\(name): \(Int(buffer[1]) << 8 + Int(buffer[2]))")
                sensor!.age = Int(buffer[3]) << 8 + Int(buffer[4])
                main.log("\(name): sensor age: \(sensor!.age), days: \(String(format: "%.1f", Double(sensor!.age)/60/24))")
                // TODO: app.sensorAge = sensor.age

                sensor!.uid = Data(buffer[5...12])
                main.log("\(name): patch uid: \(sensor!.uid.hex)")
                main.log("\(name): sensor serial number: \(sensor!.serial)")
                // TODO: app.sensorSerial = sensor.serial

                battery = Int(buffer[13])
                main.log("\(name): battery: \(battery)")
                // TODO: app.battery = battery

                firmware = buffer[14...15].hex
                hardware = buffer[16...17].hex
                main.log("\(name): firmware: \(firmware), hardware: \(hardware)")
                // TODO: app.transmitterFirmware = firmware
                // TODO: app.transmitterHardware = hardware

                if buffer.count > 363 {
                    sensor!.patchInfo = Data(buffer[363...368])
                    main.log("\(name): patch info: \(sensor!.patchInfo.hex)")
                } else {
                    // https://github.com/dabear/LibreOOPAlgorithm/blob/master/app/src/main/java/com/hg4/oopalgorithm/oopalgorithm/AlgorithmRunner.java
                    sensor!.patchInfo = Data([0xDF, 0x00, 0x00, 0x01, 0x01, 0x02])
                }

                sensor!.fram = Data(buffer[18 ..< 362])
                // TODO parseSensorData(sensor)
                main.info("\n\n\(name)  +  \(sensor!.type)")
                buffer = Data()
            }
        }
    }
}
