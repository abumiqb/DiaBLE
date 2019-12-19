import Foundation
import CoreNFC

class NFCReader: NSObject, NFCTagReaderSessionDelegate {

    var tagSession: NFCTagReaderSession?
    var main: MainDelegate!

    func startSession() {
        tagSession = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self)
        tagSession?.alertMessage = "Hold the top of your iPhone near the Libre sensor"
        tagSession?.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("NFC: Session Did Become Active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("NFC: Session Did Invalidate With Error")
        print(error.localizedDescription)
        // session.invalidate();
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("NFC: Did Detect Tags")
        guard let tag = tags.first else { return }

        if case .iso15693(let iso15693Tag) = tag {

            session.connect(to: tag) { error in
                if error != nil {
                    print(error!.localizedDescription)
                    session.invalidate(errorMessage: "Connection failure")
                    return
                }

                iso15693Tag.getSystemInfo(requestFlags: [.address, .highDataRate]) {  (dfsid: Int, afi: Int, blockSize: Int, memorySize: Int, icRef: Int, error: Error?) in
                    if error != nil {
                        session.invalidate(errorMessage: "getSystemInfo error: " + error!.localizedDescription)
                        print("NFC: error while getSystemInfo: \(error!.localizedDescription)")
                        return
                    }
                    let uidString = iso15693Tag.identifier.hex
                    session.alertMessage = "Tag UID : \(uidString)"
                    print("IC Identifier = \(uidString)")
                    print("IC ManufacturerCode = \(iso15693Tag.icManufacturerCode)")
                    print(String(format: "IC Reference 0x%X", icRef))
                    print(String(format: "Block Size %d", blockSize))
                    print(String(format: "Memory Size %d blocks", memorySize))
                }

                iso15693Tag.readSingleBlock(requestFlags: [.highDataRate, .address], blockNumber: 0) { (data, error) in
                    if error != nil {
                        print("Error while reading single block: \(error!.localizedDescription)")
                        session.invalidate(errorMessage: "Error while reading single block: \(error!.localizedDescription)")
                        return
                    }

                    print("NFC Block 0: \(data.hex)")

                    session.invalidate()
                }
            }
        }
    }
}
