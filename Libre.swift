import SwiftUI
import CoreBluetooth
import PlaygroundSupport

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
}


enum Tab: Hashable {
    case monitor
    case log
    case settings
}

struct ContentView: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var info: Info
    @EnvironmentObject var log: Log
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @State var selectedTab: Tab = .monitor

    #if os(iOS)

    var body: some View {
        TabView(selection: $selectedTab) {
            Monitor().environmentObject(app).environmentObject(info).environmentObject(history)
                .tabItem {
                    Image(systemName: "gauge")
                    Text("Monitor")
            }.tag(Tab.monitor)

            LogView().environmentObject(log).environmentObject(settings)
                .tabItem {
                    Image(systemName: "doc.plaintext")
                    Text("Log")
            }.tag(Tab.log)

            SettingsView(selectedTab: $selectedTab).environmentObject(app).environmentObject(settings)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
            }.tag(Tab.settings)
        }
    }

    #else

    // FIXME: Mac playgrounds don't display tabs
    var body: some View {
        VStack {
            Monitor().environmentObject(app).environmentObject(info).environmentObject(history)
            LogView().environmentObject(log).environmentObject(settings)
            SettingsView(selectedTab: $selectedTab).environmentObject(app).environmentObject(settings)
        }.frame(idealHeight: 400)
    }

    #endif
}

struct Monitor: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var info: Info
    @EnvironmentObject var history: History

    @State var showingLog = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack {
                    Text(app.currentGlucose > 0 ? "\(app.currentGlucose)" : "---")
                        .fontWeight(.black)
                        .foregroundColor(.black)
                        .padding(10)
                        .background(Color.yellow)
                    Text("\(app.glucoseAlarm)  \(app.glucoseTrend)")
                        .foregroundColor(.yellow)
                    Text(app.transmitterState)
                        .foregroundColor(app.transmitterState == "Connected" ? .green : .red)
                }

                Graph().environmentObject(history).frame(width: 30*5, height: 80)

                HStack {
                    VStack {
                        if app.batteryLevel > 0 {
                            Text("Battery: \(app.batteryLevel)%")
                        }
                        Text(app.sensorState)
                            .foregroundColor(app.sensorState == "Ready" ? .green : .red)

                        if app.sensorStart > 0 {
                            Text("\(app.sensorSerial)")
                            Text("\(String(format: "%.1f", Double(app.sensorStart)/60/24)) days")
                        }
                    }
                    VStack {
                        if app.transmitterFirmware.count > 0 {
                            Text("Firmware\n\(app.transmitterFirmware)")
                        }
                        if app.transmitterHardware.count > 0 {
                            Text("Hardware:\n\(app.transmitterHardware)")
                        }
                    }
                }
                .font(.footnote)
                .foregroundColor(.yellow)
                .multilineTextAlignment(.center)

                Spacer()
            }

            Text(info.text)
                .multilineTextAlignment(.center)
                .font(.footnote)
                .layoutPriority(2)
        }
    }
}

struct Graph: View {
    @EnvironmentObject var history: History
    var body: some View {
        // FIXME: called multiple times (15-40) on the Mac
        GeometryReader { geometry in
            Path() { path in
                let width  = Double(geometry.size.width)
                let height = Double(geometry.size.height)
                path.addRoundedRect(in: CGRect(x: 0.0, y: 0.0, width: width, height: height), cornerSize: CGSize(width: 8, height: 8))
                let count = self.history.values.count
                if count > 0 {
                    let v = self.history.values
                    let max = v.max()!
                    let yScale = (height - 30) / Double(max)
                    let xScale = width / Double(count - 1)
                    path.move(to: .init(x: 0.0, y: height - Double(v[count - 1]) * yScale))
                    for i in 1 ..< count {
                        path.addLine(to: .init(
                            x: Double(i) * xScale,
                            y: height - Double(v[count - i - 1]) * yScale)
                        )
                    }
                }
            }.stroke(Color.purple)
        }
    }
}

struct LogView: View {
    @EnvironmentObject var log: Log
    @EnvironmentObject var settings: Settings

    var body: some View {
        HStack {
            ScrollView(showsIndicators: true) {
                Text(self.log.text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(idealWidth: 640, alignment: .topLeading)
                    .background(Color.blue)
                    .padding(4)
            }.background(Color.blue)

            VStack(alignment: .center, spacing: 8) {

                Spacer()

                #if os(macOS)
                // FIXME: only works with iPad
                Button("Copy") { NSPasteboard.general.setString(self.log.text, forType: .string) }
                #else
                Button("Copy") { UIPasteboard.general.string = self.log.text }
                #endif

                Button("Clear") { self.log.text = "" }

                Button(action: {
                    self.settings.reversedLog.toggle()
                    self.log.text = self.log.text.split(separator:"\n").reversed().joined(separator: "\n")
                }) {
                    Text(" REV ")
                }.padding(2)
                    .background(self.settings.reversedLog ? Color.accentColor : Color.clear)
                    .border(Color.accentColor, width: 3)
                    .cornerRadius(5)
                    .foregroundColor(self.settings.reversedLog ? .black : .accentColor)

                Spacer()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var settings: Settings

    @Binding var selectedTab: Tab

    @State var preferredTransmitter: TransmitterType = .none

    // FIXME: timer doesn't update
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {

            Spacer()
            
            Text("TODO: Settings")

            Spacer()

            HStack {

                Picker(selection: $preferredTransmitter, label: Text("Preferred transmitter")) {
                    ForEach(TransmitterType.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }.pickerStyle(SegmentedPickerStyle())

            }

            // FIXME: Stepper doesn't update when in a tabview
            Stepper(value: $settings.readingInterval, in: 1 ... 15, label: { Text("Reading interval: \(settings.readingInterval)m") })

            Spacer()

            Button(action: {
                let transmitter = self.app.currentTransmitter
                // FIXME: crashes in a playground
                // self.selectedTab = .monitor
                let centralManager = self.app.main.centralManager
                centralManager.cancelPeripheralConnection(transmitter!.peripheral!)
                self.app.preferredTransmitter = self.preferredTransmitter
                centralManager.scanForPeripherals(withServices: nil, options: nil)
                self.app.nextReading = self.settings.readingInterval * 60
            }
            ) { Text("Rescan") }

            Spacer()

            Text("\(self.app.nextReading)s")
                .onReceive(timer) { _ in
                    if self.app.nextReading > 0 {
                        self.app.nextReading -= 1
                    }
            }

            Spacer()
        }
    }
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

// https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/Transmitter/CGMBluetoothTransmitter/Libre/Utilities/LibreSensorSerialNumber.swift

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

// https://github.com/bubbledevteam/xdripswift/blob/master/xdrip/Transmitter/CGMBluetoothTransmitter/Libre/Utilities/LibreRawGlucoseData.swift

struct HistoricGlucose: Codable {
    let dataQuality: Int
    let id: Int
    let value: Int
}

struct OOPHistoryData: Codable {
    var alarm: String
    var esaMinutesToWait: Int
    var historicGlucose: [HistoricGlucose]
    var isActionable: Bool
    var lsaDetected: Bool
    var realTimeGlucose: HistoricGlucose
    var trendArrow: String

    func glucoseData(date: Date) -> (GlucoseMeasurement, [GlucoseMeasurement]) {
        let current = GlucoseMeasurement(rawGlucose: realTimeGlucose.value * 10, date: date)
        var array = [GlucoseMeasurement]()
        let gap: TimeInterval = 60 * 15
        var date = date
        var history = historicGlucose
        if (history.first?.id ?? 0) < (history.last?.id ?? 0) {
            history = history.reversed()
        }
        for g in history {
            date = date.addingTimeInterval(-gap)
            if g.dataQuality != 0 { continue }
            let glucose = GlucoseMeasurement(rawGlucose: g.value * 10, minutesCounter: g.id, date: date)
            array.append(glucose)
        }
        return (current, array)
    }
}

struct OOPCalibrationResponse: Codable {
    let errcode: Int
    let parameters: CalibrationParameters
    enum CodingKeys: String, CodingKey {
        case errcode
        case parameters = "slope"
    }
}

// https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/Transmitter/CGMBluetoothTransmitter/Libre/Utilities/LibreOOPClient.swift
// https://github.com/bubbledevteam/xdripswift/blob/master/xdrip/Transmitter/CGMBluetoothTransmitter/Libre/Utilities/LibreOOPClient.swift
// https://github.com/bubbledevteam/xdripswift/commit/a1779402

func postToLibreOOP(bytes: Data, patchUid: Data? = nil, patchInfo: Data? = nil, completion: @escaping (_ data: Data?, _ errorDescription: String?) -> Void) {
    var site = "http://www.glucose.space/"
    site += patchInfo == nil ? "calibrateSensor" : "libreoop2"
    let token = "bubble-201907"
    let date = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    var json = ["content": "\(bytes.hex)"]
    if let patchInfo = patchInfo {
        json["accesstoken"] = token
        json["patchUid"] = patchUid!.hex
        json["patchInfo"] = patchInfo.hex
    } else {
        json["token"] = token
        json["timestamp"] = "\(date)"
    }
    let request = NSMutableURLRequest(url: URL(string: site)!)
    request.httpMethod = "POST"
    var allowedCharset = NSMutableCharacterSet.alphanumeric()
    allowedCharset.addCharacters(in: "-._~")
    let parameters = json.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowedCharset as CharacterSet)!)" }
    request.httpBody = parameters.joined(separator: "&").data(using: .utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    URLSession.shared.dataTask(with: request as URLRequest) {
        data, urlResponse, error in
        var errorDescription: String? = nil
        defer {
            DispatchQueue.main.sync {
                completion(data, errorDescription)
            }
        }
        if let error = error {
            errorDescription = error.localizedDescription
            return
        }
    }.resume()
}

public class MainDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    var app: App
    var log: Log
    var info: Info
    var history: History
    var settings: Settings


    var host: PlaygroundLiveViewable

    var bubble: Bubble?
    var droplet: Droplet?
    var limitter: Limitter?
    var miaomiao: MiaoMiao?

    var centralManager: CBCentralManager

    override init() {
        app = App()
        log = Log()
        info = Info()
        history = History()
        settings = Settings()

        #if os(macOS)
        host = NSHostingView(rootView: ContentView().environmentObject(app).environmentObject(log).environmentObject(info).environmentObject(history).environmentObject(settings))
        #elseif os(iOS)
        host = UIHostingController(rootView: ContentView().environmentObject(app).environmentObject(log).environmentObject(info).environmentObject(history).environmentObject(settings))
        #endif
        self.centralManager = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        self.centralManager.delegate = self
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
        log("Sending FRAM to a LibreOOP server for calibration...")

        postToLibreOOP(bytes: fram) { data, errorDescription in
            if let data = data {
                let json = String(decoding: data, as: UTF8.self)
                self.log("LibreOOP Server calibration response: \(json))")
                let decoder = JSONDecoder.init()
                if let oopCalibration = try? decoder.decode(OOPCalibrationResponse.self, from: data) {
                    let params = oopCalibration.parameters
                    self.log("Calibration parameters: \(params)")

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
            log("Sending FRAM to a LibreOOP server for measurements...")

            postToLibreOOP(bytes: fram, patchUid: transmitter.patchUid, patchInfo: transmitter.patchInfo) { data, errorDescription in
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

let mainDelegate = MainDelegate()
mainDelegate.app.main = mainDelegate
var host = mainDelegate.host
PlaygroundPage.current.liveView = host
PlaygroundPage.current.needsIndefiniteExecution = true
