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
            Monitor().environmentObject(app).environmentObject(info).environmentObject(history)
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

    @State var showingLog = false

    var body: some View {
        NavigationView {
            
            VStack {

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
                    Spacer()

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

                Text(" ")
                Text(info.text)
                    .multilineTextAlignment(.center)
                    .font(.footnote)
                    .layoutPriority(2)
            }
            .navigationBarItems(trailing:
                Button(action: {
                    self.app.main.nfcReader.startSession()
                }) { VStack {
                    Image(systemName: "radiowaves.left")
                        .resizable()
                        .rotationEffect(Angle(degrees: 90))
                        .frame(width: 15, height: 30)
                    Text("NFC").bold().offset(y: -16)
                    }
            })
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
    @EnvironmentObject var app: App
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

            VStack(alignment: .center, spacing: 14) {

                Button(action: {
                    self.app.main.nfcReader.startSession()
                }) { VStack {
                    Image(systemName: "radiowaves.left")
                        .resizable()
                        .rotationEffect(Angle(degrees: 90))
                        .frame(width: 20, height: 40)
                    Text("NFC").bold().offset(y: -18)
                    }
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
                let transmitter = self.app.transmitter
                // FIXME: crashes in a playground
                self.selectedTab = .monitor
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
