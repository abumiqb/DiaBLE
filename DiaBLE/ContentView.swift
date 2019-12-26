import SwiftUI

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

    var body: some View {

        TabView(selection: $selectedTab) {
            Monitor().environmentObject(app).environmentObject(info).environmentObject(history).environmentObject(settings)
                .tabItem {
                    Image(systemName: "gauge")
                    Text("Monitor")
            }.tag(Tab.monitor)

            LogView().environmentObject(app).environmentObject(log).environmentObject(settings)
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
}

struct Monitor: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var info: Info
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    @State private var showingNFCAlert = false

    // TODO: a global timer
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            
            VStack {

                VStack {
                    Text(app.currentGlucose > 0 ? "\(app.currentGlucose)" : "---")
                        .fontWeight(.black)
                        .foregroundColor(.black)
                        .padding(10)
                        .background(Color.yellow)
                        .fixedSize()

                    Text("\(app.glucoseAlarm)  \(app.glucoseTrend)")
                        .foregroundColor(.yellow)

                    HStack {
                        Text(app.transmitterState)
                            .foregroundColor(app.transmitterState == "Connected" ? .green : .red)
                            .fixedSize()

                        if self.app.nextReading > -1 {
                            Text("\(self.app.nextReading) s")
                                .fixedSize()
                                .onReceive(timer) { _ in
                                    if self.app.nextReading > 0 {
                                        self.app.nextReading -= 1
                                    }
                            }.foregroundColor(.orange)
                        }
                    }
                }

                Graph().environmentObject(history).frame(width: 30*7, height: 150)

                HStack {
                    Spacer()

                    HStack {
                        VStack {
                            if app.battery > 0 {
                                Text("Battery: \(app.battery)%")
                            }
                            Text(app.sensorState)
                                .foregroundColor(app.sensorState == "Ready" ? .green : .red)

                            if app.sensorAge > 0 {
                                Text("\(app.sensorSerial)")
                                Text("\(String(format: "%.1f", Double(app.sensorAge)/60/24)) days")
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

                Text(" ")

                VStack {

                    Text(info.text)
                        .layoutPriority(2)

                    Text(" ")

                    if history.values.count > 0 {
                        Text("OOP history: [\(history.values.map{ String($0) }.joined(separator: " "))]")
                            .foregroundColor(.purple)
                    }
                    if history.rawValues.count > 0 {
                        Text("Raw history: [\(history.rawValues.map{ String($0) }.joined(separator: " "))]")
                            .foregroundColor(.yellow)
                        Text("Raw trend: [\(history.rawTrend.map{ String($0) }.joined(separator: " "))]")
                            .foregroundColor(.yellow)
                    }

                }
                .font(.footnote)
                .multilineTextAlignment(.center)

                if app.params.offsetOffset != 0.0 {
                    VStack {
                        HStack {
                            Text("Slope slope:")
                            TextField("Slope slope", value: $app.params.slopeSlope, formatter: settings.numberFormatter)
                                .foregroundColor(.blue)
                            Text("Slope offset:")
                            TextField("Slope offset", value: $app.params.offsetSlope, formatter: settings.numberFormatter)
                                .foregroundColor(.blue)
                        }

                        HStack {
                            Text("Offset slope:")
                            TextField("Offset slope", value: $app.params.slopeOffset, formatter: settings.numberFormatter)
                                .foregroundColor(.blue)
                            Text("Offset offset:")
                            TextField("Offset offset", value: $app.params.offsetOffset, formatter: settings.numberFormatter)
                                .foregroundColor(.blue)
                        }
                    }
                    .font(.footnote)
                }

                Text(" ")
            }
            .navigationBarTitle("DiaBLE  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String)", displayMode: .inline)
            .navigationBarItems(trailing:
                Button(action: {
                    if self.app.main.nfcReader.isNFCAvailable {
                        self.app.main.nfcReader.startSession()
                    } else {
                        self.showingNFCAlert = true
                    }
                }) { VStack {
                    Image(systemName: "radiowaves.left")
                        .resizable()
                        .rotationEffect(.degrees(90))
                        .frame(width: 15, height: 30)
                    Text("NFC").bold().offset(y: -16)
                    }
                }.alert(isPresented: $showingNFCAlert) {
                    Alert(
                        title: Text("NFC not supported"),
                        message: Text("This device doesn't allow scanning the Libre."))
                }
            )
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct Graph: View {
    @EnvironmentObject var history: History
    var body: some View {
        ZStack {

            // Raw Values
            GeometryReader { geometry in
                Path() { path in
                    let width  = Double(geometry.size.width)
                    let height = Double(geometry.size.height)
                    let count = self.history.rawValues.count
                    if count > 0 {
                        let v = self.history.rawValues
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
                }.stroke(Color.yellow).opacity(0.6)
            }

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
}

struct LogView: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var log: Log
    @EnvironmentObject var settings: Settings

    @State private var showingNFCAlert = false

    var body: some View {
        HStack {
            ScrollView(showsIndicators: true) {
                Text(self.log.text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(idealWidth: 640, alignment: .topLeading)
                    .background(Color.blue)
                    .padding(4)
            }.background(Color.blue)

            VStack(alignment: .center, spacing: 14) {

                Button(action: {
                    if self.app.main.nfcReader.isNFCAvailable {
                        self.app.main.nfcReader.startSession()
                    } else {
                        self.showingNFCAlert = true
                    }
                }) { VStack {
                    Image(systemName: "radiowaves.left")
                        .resizable()
                        .rotationEffect(.degrees(90))
                        .frame(width: 20, height: 40)
                    Text("NFC").bold().offset(y: -18)
                    }
                }.alert(isPresented: $showingNFCAlert) {
                    Alert(
                        title: Text("NFC not supported"),
                        message: Text("This device doesn't allow scanning the Libre."))
                }

                Spacer()

                Button(action: { UIPasteboard.general.string = self.log.text }) {
                    VStack {
                        Image(systemName: "doc.on.doc")
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text("Copy").offset(y: -6)
                    }
                }

                Button(action: { self.log.text = "" }) {
                    VStack {
                        Image(systemName: "clear")
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text("Clear").offset(y: -6)
                    }
                }

                Button(action: {
                    self.settings.reversedLog.toggle()
                    self.log.text = self.log.text.split(separator:"\n").reversed().joined(separator: "\n")
                }) { VStack {
                    Image(systemName: "backward.fill")
                        .resizable()
                        .frame(width: 12, height: 12).offset(y: 4)
                    Text(" REV ").offset(y: -4)
                    }
                }.background(self.settings.reversedLog ? Color.accentColor : Color.clear)
                    .border(Color.accentColor, width: 3)
                    .cornerRadius(5)
                    .foregroundColor(self.settings.reversedLog ? .black : .accentColor)

                Spacer()

            }.font(.system(.footnote))
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var settings: Settings

    @Binding var selectedTab: Tab

    @State var preferredTransmitter: TransmitterType = .none

    var body: some View {

        NavigationView {
            VStack {
                Spacer()

                HStack {
                    Image(systemName: "heart.fill").foregroundColor(.red)
                    Picker(selection: $preferredTransmitter, label: Text("Preferred")) {
                        ForEach(TransmitterType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }

                HStack {
                    Stepper(value: $settings.readingInterval, in: 1 ... 15, label: {
                        Image(systemName: "timer")
                        Text("\(settings.readingInterval) m") })
                }
                .foregroundColor(.orange)
                .padding(100)

                Button(action: {
                    let transmitter = self.app.transmitter

                    self.selectedTab = .monitor
                    let centralManager = self.app.main.centralManager
                    if transmitter != nil {
                        centralManager.cancelPeripheralConnection(transmitter!.peripheral!)
                    }
                    self.app.preferredTransmitter = self.preferredTransmitter
                    if centralManager.state == .poweredOn {
                        centralManager.scanForPeripherals(withServices: nil, options: nil)
                    }
                }
                ) { Text("Rescan").bold() }

                Spacer()

            }.navigationBarTitle("DiaBLE  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String)  -  Settings", displayMode: .inline)
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

// TODO
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
