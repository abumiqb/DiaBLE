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

    var peripheral: CBPeripheral?
    var name: String { "Unnamed peripheral" }
    class var dataServiceUUID: String { "" }
    class var dataReadCharacteristicUUID: String { "" }
    class var dataWriteCharacteristicUUID: String { "" }

    var readCharacteristic: CBCharacteristic?
    var writeCharacteristic: CBCharacteristic?

    var firmware = ""
    var buffer = Data()
    var fram = Data()
    var patchUid = Data()
    var patchInfo = Data()

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    func write(_ bytes: Array<UInt8>) {
        peripheral?.writeValue(Data(bytes), for: writeCharacteristic!, type: .withoutResponse)
    }
}

class Bubble: Transmitter {
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
                return "Data info received"
            case .dataPacket:
                return "Data packet received"
            case .noSensor:
                return "No sensor detected"
            case .serialNumber:
                return "Serial number received"
            case .patchInfo:
                return "Patch info received"
            }
        }
    }
}

class Droplet: Transmitter {
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
}

class MiaoMiao: Transmitter {
    override var name: String { "MiaoMiao" }
    override class var dataServiceUUID: String { "6E400001-B5A3-F393-E0A9-E50E24DCCA9E" }
    override class var dataReadCharacteristicUUID: String { "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" }
    override class var dataWriteCharacteristicUUID: String { "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" }

    enum ResponseType: UInt8, CustomStringConvertible {
        case dataPacket = 0x28
        case newSensor =  0x32
        case noSensor =   0x34
        case frequencyChange = 0xD1

        var description: String {
            switch self {
            case .dataPacket:
                return "Data packet received"
            case .newSensor:
                return "New sensor detected"
            case .noSensor:
                return "No sensor detected"
            case .frequencyChange:
                return "Reading frequency change"
            }
        }
    }
}
