import Foundation
import CoreNFC

class NFCReader: NSObject, NFCTagReaderSessionDelegate {

    var tagSession: NFCTagReaderSession?
    var main: MainDelegate!

    func startSession() {
        // execute in the .main queue because of main.log
        tagSession = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main)
        tagSession?.alertMessage = "Hold the top of your iPhone near the Libre sensor"
        tagSession?.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        main.log("NFC: session did become active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code != .readerSessionInvalidationErrorUserCanceled {
                main.log("NFC: \(readerError.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(readerError.localizedDescription)")
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        main.log("NFC: did detect tags")

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        session.alertMessage = "Scan complete"
        var dataArray = [Data](repeating: Data(), count: 45)

        session.connect(to: firstTag) { error in
            if error != nil {
                self.main.log("NFC: \(error!.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(error!.localizedDescription)")
                return
            }

            // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

            tag.getSystemInfo(requestFlags: [.address, .highDataRate]) {  (dfsid: Int, afi: Int, blockSize: Int, memorySize: Int, icRef: Int, error: Error?) in
                if error != nil {
                    session.invalidate(errorMessage: "Error while getting system info: " + error!.localizedDescription)
                    self.main.log("NFC: error while getting system info: \(error!.localizedDescription)")
                    return
                }

                // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/NFCReaderX.java

                tag.customCommand(requestFlags: RequestFlag(rawValue: 0x02), customCommandCode: 0xA1, customRequestParameters: Data([0x07])) { (customResponse: Data, error: Error?) in
                    if error != nil {
                        session.invalidate(errorMessage: "Error while getting patch info: " + error!.localizedDescription)
                        self.main.log("NFC: error while getting patch info: \(error!.localizedDescription)")
                        return
                    }

                    for i in 0...14 {

                        tag.readMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: NSRange(UInt8(i * 3)...UInt8(i * 3 + 2))) { (blockArray, error) in
                            if error != nil {
                                self.main.log("NFC: error while reading multiple blocks: \(error!.localizedDescription)")
                                session.invalidate(errorMessage: "Error while reading multiple blocks: \(error!.localizedDescription)")
                                return
                            }
                            dataArray[i * 3]     = blockArray[0]
                            dataArray[i * 3 + 1] = blockArray[1]
                            dataArray[i * 3 + 2] = blockArray[2]

                            if i == 14 {

                                session.invalidate()

                                let sensor = Sensor()

                                var fram = Data()

                                for (n, data) in dataArray.enumerated().dropLast(2) {
                                    fram.append(data)
                                    self.main.log("NFC block #\(String(format:"%02d", n)): \(data.reduce("", { $0 + String(format: "%02X", $1) + " "}))")
                                }

                                let uid = tag.identifier.hex
                                self.main.log("NFC: IC identifier: \(uid)")

                                var manufacturer = String(tag.icManufacturerCode)
                                if manufacturer == "7" {
                                    manufacturer.append(" (Texas Instruments)")
                                }
                                self.main.log("NFC: IC manufacturer code: \(manufacturer)")
                                self.main.log("NFC: IC serial number: \(tag.icSerialNumber.hex)")

                                self.main.log(String(format: "NFC: IC reference: 0x%X", icRef))

                                self.main.log(String(format: "NFC: block size: %d", blockSize))
                                self.main.log(String(format: "NFC: memory size: %d blocks", memorySize))

                                sensor.uid = Data(tag.identifier.reversed())

                                self.main.app.sensorSerial = sensor.serial
                                self.main.log("NFC: sensor serial number: \(sensor.serial)")

                                let patchInfo = customResponse
                                sensor.patchInfo = Data(patchInfo)
                                self.main.log("NFC: patch info: \(patchInfo.hex)")
                                self.main.log("NFC: Libre type: \(sensorType(patchInfo: patchInfo).rawValue)")

                                sensor.fram = Data(fram)
                                self.main.parseSensorData(sensor)
                            }
                        }
                    }
                }
            }
        }
    }
}
