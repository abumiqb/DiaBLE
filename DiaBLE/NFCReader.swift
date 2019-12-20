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
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        main.log("NFC: Did Detect Tags")

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        session.connect(to: firstTag) { error in
            if error != nil {
                self.main.log("NFC: \(error!.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(error!.localizedDescription)")
                return
            }

            tag.getSystemInfo(requestFlags: [.address, .highDataRate]) {  (dfsid: Int, afi: Int, blockSize: Int, memorySize: Int, icRef: Int, error: Error?) in
                if error != nil {
                    session.invalidate(errorMessage: "getSystemInfo error: " + error!.localizedDescription)
                    self.main.log("NFC: error while getSystemInfo: \(error!.localizedDescription)")
                    return
                }
                let uidString = tag.identifier.hex
                session.alertMessage = "Tag UID : \(uidString)"
                self.main.log("NFC: IC Identifier: \(uidString)")

                var manufacturer = String(tag.icManufacturerCode)
                if manufacturer == "7" {
                    manufacturer.append(" (Texas Instruments)")
                }
                self.main.log("NFC: IC ManufacturerCode: \(manufacturer)")
                self.main.log("NFC: IC Serial Number: \(tag.icSerialNumber.hex)")

                self.main.log(String(format: "NFC: IC Reference: 0x%X", icRef))

                self.main.log(String(format: "NFC: Block Size: %d", blockSize))
                self.main.log(String(format: "NFC: Memory Size: %d blocks", memorySize))
            }

            // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/NFCReaderX.java

            //TODO: read multiple blocks (0x23 command code): don't work (Tag response error)

            //                tag.readMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: NSRange(0...42)) { (dataArray, error) in
            //                    if error != nil {
            //                        self.main.log("Error while reading multiple blocks: \(error!.localizedDescription)")
            //                        session.invalidate(errorMessage: "Error while reading multiple blocks: \(error!.localizedDescription)")
            //                        return
            //                    }
            //                    for (n, data) in dataArray.enumerated() {
            //                        self.main.log("NFC block #\(String(format:"%02d", n)): \(data.reduce("", { $0 + String(format: "%02X", $1) + " "}))")
            //                        if n == 42 { session.invalidate() }
            //                    }
            //                }


            // (0x20 command code)
            for b: UInt8 in 0...42 {
                tag.readSingleBlock(requestFlags: [.highDataRate, .address], blockNumber: b) { (data, error) in
                    if error != nil {
                        self.main.log("NFC: Error while reading single block: \(error!.localizedDescription)")
                        session.invalidate(errorMessage: "Error while reading single block: \(error!.localizedDescription)")
                        return
                    }

                    self.main.log("NFC block #\(String(format:"%02d", b)): \(data.reduce("", { $0 + String(format: "%02X", $1) + " "}))")

                    if b == 42 { session.invalidate() }
                }
            }

            // TODO: a func to return FRAM and the PatchInfo
        }
    }
}
