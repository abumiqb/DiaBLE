import Foundation

enum SensorState: UInt8, CustomStringConvertible {
    case notYetStarted = 0x01
    case starting
    case ready
    case expired
    case shutdown
    case failure
    case unknown

    var description: String {
        switch self {
        case .notYetStarted:
            return "Not started"
        case .starting:
            return "Starting"
        case .ready:
            return "Ready"
        case .expired:
            return "Expired"
        case .shutdown:
            return "Shut down"
        case .failure:
            return "Failed"
        default:
            return "Unknown"
        }
    }
}

// https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/SensorSerialNumber.swift

func sensorSerialNumber(uid: Data) -> String {
    let lookupTable = ["0","1","2","3","4","5","6","7","8","9","A","C","D","E","F","G","H","J","K","L","M","N","P","Q","R","T","U","V","W","X","Y","Z"]
    guard uid.count == 8 else {return "invalid uid"}
    let bytes = Array(uid.reversed().suffix(6))
    var fiveBitsArray = [UInt8]()
    fiveBitsArray.append( bytes[0] >> 3 )
    fiveBitsArray.append( bytes[0] << 2 + bytes[1] >> 6 )
    fiveBitsArray.append( bytes[1] >> 1 )
    fiveBitsArray.append( bytes[1] << 4 + bytes[2] >> 4 )
    fiveBitsArray.append( bytes[2] << 1 + bytes[3] >> 7 )
    fiveBitsArray.append( bytes[3] >> 2 )
    fiveBitsArray.append( bytes[3] << 3 + bytes[4] >> 5 )
    fiveBitsArray.append( bytes[4] )
    fiveBitsArray.append( bytes[5] >> 3 )
    fiveBitsArray.append( bytes[5] << 2 )
    return fiveBitsArray.reduce("0", {
        $0 + lookupTable[ Int(0x1F & $1) ]
    })
}

// https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/CRC.swift

func crc16(_ data: Data) -> UInt16 {
    let crc16table: [UInt16] = [0, 4489, 8978, 12955, 17956, 22445, 25910, 29887, 35912, 40385, 44890, 48851, 51820, 56293, 59774, 63735, 4225, 264, 13203, 8730, 22181, 18220, 30135, 25662, 40137, 36160, 49115, 44626, 56045, 52068, 63999, 59510, 8450, 12427, 528, 5017, 26406, 30383, 17460, 21949, 44362, 48323, 36440, 40913, 60270, 64231, 51324, 55797, 12675, 8202, 4753, 792, 30631, 26158, 21685, 17724, 48587, 44098, 40665, 36688, 64495, 60006, 55549, 51572, 16900, 21389, 24854, 28831, 1056, 5545, 10034, 14011, 52812, 57285, 60766, 64727, 34920, 39393, 43898, 47859, 21125, 17164, 29079, 24606, 5281, 1320, 14259, 9786, 57037, 53060, 64991, 60502, 39145, 35168, 48123, 43634, 25350, 29327, 16404, 20893, 9506, 13483, 1584, 6073, 61262, 65223, 52316, 56789, 43370, 47331, 35448, 39921, 29575, 25102, 20629, 16668, 13731, 9258, 5809, 1848, 65487, 60998, 56541, 52564, 47595, 43106, 39673, 35696, 33800, 38273, 42778, 46739, 49708, 54181, 57662, 61623, 2112, 6601, 11090, 15067, 20068, 24557, 28022, 31999, 38025, 34048, 47003, 42514, 53933, 49956, 61887, 57398, 6337, 2376, 15315, 10842, 24293, 20332, 32247, 27774, 42250, 46211, 34328, 38801, 58158, 62119, 49212, 53685, 10562, 14539, 2640, 7129, 28518, 32495, 19572, 24061, 46475, 41986, 38553, 34576, 62383, 57894, 53437, 49460, 14787, 10314, 6865, 2904, 32743, 28270, 23797, 19836, 50700, 55173, 58654, 62615, 32808, 37281, 41786, 45747, 19012, 23501, 26966, 30943, 3168, 7657, 12146, 16123, 54925, 50948, 62879, 58390, 37033, 33056, 46011, 41522, 23237, 19276, 31191, 26718, 7393, 3432, 16371, 11898, 59150, 63111, 50204, 54677, 41258, 45219, 33336, 37809, 27462, 31439, 18516, 23005, 11618, 15595, 3696, 8185, 63375, 58886, 54429, 50452, 45483, 40994, 37561, 33584, 31687, 27214, 22741, 18780, 15843, 11370, 7921, 3960]
    var crc = data.reduce(UInt16(0xFFFF)) { ($0 >> 8) ^ crc16table[Int(($0 ^ UInt16($1)) & 0xFF)] }
    var reverseCrc = UInt16(0)
    for _ in 0 ..< 16 {
        reverseCrc = reverseCrc << 1 | crc & 1
        crc >>= 1
    }
    return reverseCrc.byteSwapped
}

// https://github.com/bubbledevteam/xdripswift/blob/master/xdrip/Transmitter/CGMBluetoothTransmitter/Libre/Utilities/LibreMeasurement.swift

struct CalibrationParameters: Codable {
    let slopeSlope, slopeOffset, offsetOffset, offsetSlope: Double
    enum CodingKeys: String, CodingKey {
        case slopeSlope   = "slope_slope"
        case slopeOffset  = "slope_offset"
        case offsetOffset = "offset_offset"
        case offsetSlope  = "offset_slope"
    }
}

class GlucoseMeasurement {
    let date: Date
    let minutesCounter: Int
    let rawGlucose: Int
    let rawTemperature: Int
    let slope: Double
    let offset: Double
    var calibrationParameters: CalibrationParameters?

    var glucose: Int {
        if let params = calibrationParameters {
            let slope  = params.slopeSlope  * Double(rawTemperature) + params.offsetSlope
            let offset = params.slopeOffset * Double(rawTemperature) + params.offsetOffset
            return Int(round(offset + slope * Double(rawGlucose)))
        } else {
            return Int(round(offset + slope * Double(rawGlucose)))
        }
    }

    init(rawGlucose: Int, rawTemperature: Int = 0, slope: Double = 0.1, offset: Double = 0.0, minutesCounter: Int = 0, date: Date = Date()) {
        self.date = date
        self.minutesCounter = minutesCounter
        self.rawGlucose = rawGlucose
        self.rawTemperature = rawTemperature
        self.slope = slope
        self.offset = offset
    }

    convenience init(bytes: [UInt8], slope: Double = 0.1, offset: Double = 0.0, minutesCounter: Int = 0, date: Date = Date()) {
        let rawGlucose = (Int(bytes[1] & 0x1F) << 8) + Int(bytes[0])
        let rawTemperature = (Int(bytes[4] & 0x3F) << 8)  + Int(bytes[3])
        self.init(rawGlucose: rawGlucose, rawTemperature: rawTemperature, slope: slope, offset: offset, minutesCounter: minutesCounter, date: date)
    }
}
