import Foundation

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
        let current = GlucoseMeasurement(rawGlucose: realTimeGlucose.value, date: date)
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
            let glucose = GlucoseMeasurement(rawGlucose: g.value, minutesCounter: g.id, date: date)
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
