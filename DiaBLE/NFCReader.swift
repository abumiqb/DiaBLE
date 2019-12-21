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
        main.log("NFC: Session Did Become Active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code != .readerSessionInvalidationErrorUserCanceled {
                main.log("NFC: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(error.localizedDescription)")
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        main.log("NFC: Did Detect Tags")

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        session.alertMessage = "Scan complete"
        session.connect(to: firstTag) { error in
            if error != nil {
                self.main.log("NFC: \(error!.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(error!.localizedDescription)")
                return
            }

            // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

            tag.getSystemInfo(requestFlags: [.address, .highDataRate]) {  (dfsid: Int, afi: Int, blockSize: Int, memorySize: Int, icRef: Int, error: Error?) in
                if error != nil {
                    session.invalidate(errorMessage: "getSystemInfo error: " + error!.localizedDescription)
                    self.main.log("NFC: error while getSystemInfo: \(error!.localizedDescription)")
                    return
                }

                // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/NFCReaderX.java

                tag.customCommand(requestFlags: RequestFlag(rawValue: 0x02), customCommandCode: 0xA1, customRequestParameters: Data([0x07])) { (customResponse: Data, error: Error?) in
                    if error != nil {
                        session.invalidate(errorMessage: "Error getting PatchInfo: " + error!.localizedDescription)
                        self.main.log("NFC: \(error!.localizedDescription)")
                        return
                    }
                    var dataArray = [Data]()

                    // FIXME: readMultipleBlock dooesn't work and returns a Tap response error

//                    tag.readMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: NSRange(UInt8(0)...UInt8(42))) { (blockArray, error) in
//                        if error != nil {
//                            self.main.log("Error while reading multiple blocks: \(error!.localizedDescription)")
//                            session.invalidate(errorMessage: "Error while reading multiple blocks: \(error!.localizedDescription)")
//                            return
//                        }
//                        for (n, data) in blockArray.enumerated() {
//                            dataArray.append(data)
//
//                            if n == 42 {
//                                session.invalidate()
//                                self.main.log("NFC: Read \(blockArray.count) blocks: \(blockArray)")
//                            }
//                        }
//                    }

                    for b: UInt8 in 0...42 {
                        tag.readSingleBlock(requestFlags: [.highDataRate, .address], blockNumber: b) { (data, error) in
                            if error != nil {
                                self.main.log("NFC: Error while reading single block: \(error!.localizedDescription)")
                                session.invalidate(errorMessage: "Error while reading single block: \(error!.localizedDescription)")
                                return
                            }
                            dataArray.append(data)

                            if b == 42 {
                                session.invalidate()

                                // Create a dummy transmitter when none is available in order to be able
                                // to call parseSensorData(transmitter) at the end
                                let transmitter = self.main.app.transmitter ?? Transmitter()

                                var fram = Data()

                                for (n, data) in dataArray.enumerated() {
                                    fram.append(data)
                                    self.main.log("NFC block #\(String(format:"%02d", n)): \(data.reduce("", { $0 + String(format: "%02X", $1) + " "}))")
                                }

                                let uid = tag.identifier.hex
                                self.main.log("NFC: IC Identifier: \(uid)")

                                var manufacturer = String(tag.icManufacturerCode)
                                if manufacturer == "7" {
                                    manufacturer.append(" (Texas Instruments)")
                                }
                                self.main.log("NFC: IC ManufacturerCode: \(manufacturer)")
                                self.main.log("NFC: IC Serial Number: \(tag.icSerialNumber.hex)")

                                self.main.log(String(format: "NFC: IC Reference: 0x%X", icRef))

                                self.main.log(String(format: "NFC: Block Size: %d", blockSize))
                                self.main.log(String(format: "NFC: Memory Size: %d blocks", memorySize))

                                let patchUid = Data(tag.identifier.reversed())
                                transmitter.patchUid = patchUid

                                let serialNumber = sensorSerialNumber(uid: patchUid)
                                self.main.app.sensorSerial = serialNumber
                                self.main.log("NFC: sensor serial number: \(serialNumber)")

                                transmitter.patchInfo = Data(customResponse)
                                self.main.log("NFC: PatchInfo: \(customResponse.hex)")

                                transmitter.fram = Data(fram)
                                self.main.parseSensorData(transmitter: transmitter)
                            }
                        }
                    }
                }
            }
        }
    }
}

// TODO: a func to return FRAM and the PatchInfo



