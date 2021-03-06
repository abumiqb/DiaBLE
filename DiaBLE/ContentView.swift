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

    var body: some View {

        TabView(selection: $app.selectedTab) {
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

            SettingsView().environmentObject(app).environmentObject(settings)
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
                Spacer()
                VStack {
                    HStack {
                        Text("\(app.lastReading.shortTime)").frame(maxWidth: .infinity, alignment: .trailing ).padding(.trailing, 10).foregroundColor(.gray)

                        Text(app.currentGlucose > 0 ? "\(app.currentGlucose) " :
                            (app.currentGlucose < 0 ? "(\(-app.currentGlucose)) " : "--- "))
                            .fontWeight(.black)
                            .foregroundColor(.black)
                            .padding(10)
                            .background(abs(app.currentGlucose) > 0 && (abs(app.currentGlucose) > Int(settings.alarmHigh) || abs(app.currentGlucose) < Int(settings.alarmLow)) ? Color.red :
                                (app.currentGlucose < 0 ? Color.yellow : Color.blue))
                            .cornerRadius(5)

                        // TODO: trend arrow
                        Text("---").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
                    }
                    Text("\(app.oopAlarm.replacingOccurrences(of: "_", with: " ")) - \(app.oopTrend.replacingOccurrences(of: "_", with: " "))")
                        .foregroundColor(.blue)

                    HStack {
                        Text(app.transmitterState)
                            .foregroundColor(app.transmitterState == "Connected" ? .green : .red)
                            .fixedSize()

                        if app.readingTimer > -1 {
                            Text("\(app.readingTimer) s")
                                .fixedSize()
                                .onReceive(timer) { _ in
                                    if self.app.readingTimer > 0 {
                                        self.app.readingTimer -= 1
                                    }
                            }.foregroundColor(.orange)
                        }
                    }
                }


                Graph().environmentObject(history).environmentObject(settings).frame(width: 31 * 7 + 60, height: 150)


                HStack {
                    VStack {
                        Text(app.sensorState)
                            .foregroundColor(app.sensorState == "Ready" ? .green : .red)

                        if app.sensorSerial != "" {
                            Text("\(app.sensorSerial)")
                        }

                        if app.sensorAge > 0 {
                            Text("\(String(format: "%.1f", Double(app.sensorAge)/60/24)) days")
                        }

                    }

                    VStack {
                        if app.battery > -1 {
                            Text("Battery: \(app.battery)%")
                        }
                        if app.transmitterFirmware.count > 0 {
                            Text("Firmware: \(app.transmitterFirmware)")
                        }
                        if app.transmitterHardware.count > 0 {
                            Text("Hardware:\n\(app.transmitterHardware)")
                        }
                    }
                }
                .font(.footnote)
                .foregroundColor(.yellow)

                Text(info.text)
                    .font(.footnote)
                    .padding(.vertical, 5)

                VStack(spacing: 2) {
                    if history.values.count > 0 {
                        Text("OOP history: [\(history.values.map{ String($0) }.joined(separator: " "))]")
                            .foregroundColor(.blue)
                    }
                    if history.rawValues.count > 0 {
                        Text("Raw history: [\(history.rawValues.map{ String($0) }.joined(separator: " "))]")
                            .foregroundColor(.yellow)
                        Text("Raw trend: [\(history.rawTrend.map{ String($0) }.joined(separator: " "))]")
                            .foregroundColor(.yellow)
                    }
                }
                .font(.footnote)
                .layoutPriority(1.0)

                if app.params.offsetOffset != 0.0 {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Slope slope:")
                            TextField("Slope slope", value: $app.params.slopeSlope, formatter: settings.numberFormatter)
                                .foregroundColor(.purple)
                            Text("Slope offset:")
                            TextField("Slope offset", value: $app.params.offsetSlope, formatter: settings.numberFormatter)
                                .foregroundColor(.purple)
                        }

                        HStack {
                            Text("Offset slope:")
                            TextField("Offset slope", value: $app.params.slopeOffset, formatter: settings.numberFormatter)
                                .foregroundColor(.purple)
                            Text("Offset offset:")
                            TextField("Offset offset", value: $app.params.offsetOffset, formatter: settings.numberFormatter)
                                .foregroundColor(.purple)
                        }
                    }
                    .font(.footnote)
                    .keyboardType(.numbersAndPunctuation)
                }

                Spacer()

                // Same as Rescan
                Button(action: {
                    let transmitter = self.app.transmitter
                    let centralManager = self.app.main.centralManager
                    if transmitter != nil {
                        centralManager.cancelPeripheralConnection(transmitter!.peripheral!)
                    }
                    if centralManager.state == .poweredOn {
                        centralManager.scanForPeripherals(withServices: nil, options: nil)
                    }
                }
                ) { Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 32, height: 32).padding(.bottom, 8
                ).foregroundColor(.accentColor) }

            }
            .multilineTextAlignment(.center)
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
    @EnvironmentObject var settings: Settings

    var body: some View {
        ZStack {

            // Glucose range rect in the background
            GeometryReader { geometry in
                Path() { path in
                    let width  = Double(geometry.size.width) - 60.0
                    let height = Double(geometry.size.height)
                    let yScale = (height - 30.0) / (self.history.rawValues.count > 0 ? Double(self.history.rawValues.max()!) : 250.0)
                    path.addRect(CGRect(x: 1.0 + 30.0, y: height - self.settings.targetHigh * yScale + 1.0, width: width - 2.0, height: (self.settings.targetHigh - self.settings.targetLow) * yScale - 1.0))
                }.fill(Color.green).opacity(0.15)
            }

            // Glucose low and high labels at the right
            GeometryReader { geometry in
                ZStack {
                    Text("\(Int(self.settings.targetHigh))")
                        .position(x: CGFloat(Double(geometry.size.width) - 15.0), y: CGFloat(Double(geometry.size.height) - (Double(geometry.size.height) - 30.0) / (self.history.rawValues.count > 0 ? Double(self.history.rawValues.max()!) : 250.0) * self.settings.targetHigh))
                    Text("\(Int(self.settings.targetLow))")
                        .position(x: CGFloat(Double(geometry.size.width) - 15.0), y: CGFloat(Double(geometry.size.height) - (Double(geometry.size.height) - 30.0) / (self.history.rawValues.count > 0 ? Double(self.history.rawValues.max()!) : 250.0) * self.settings.targetLow))
                }.font(.footnote).foregroundColor(.gray)
            }

            // History raw values
            GeometryReader { geometry in
                Path() { path in
                    let width  = Double(geometry.size.width) - 60.0
                    let height = Double(geometry.size.height)
                    let count = self.history.rawValues.count
                    if count > 0 {
                        let v = self.history.rawValues
                        let max = v.max()!
                        let yScale = (height - 30.0) / Double(max)
                        let xScale = width / Double(count - 1)
                        var startingVoid = v[count - 1] < 1 ? true : false
                        if startingVoid == false { path.move(to: .init(x: 0.0 + 30.0, y: height - Double(v[count - 1]) * yScale)) }
                        for i in 1 ..< count {
                            if v[count - i - 1] > 0 {
                                let point = CGPoint(x: Double(i) * xScale + 30.0, y: height - Double(v[count - i - 1]) * yScale)
                                if startingVoid == false {
                                    path.addLine(to: point)
                                } else {
                                    startingVoid = false
                                    path.move(to: point)
                                }
                            }
                        }
                    }
                }.stroke(Color.yellow).opacity(0.6)
            }

            // History (OOP) values
            GeometryReader { geometry in
                Path() { path in
                    let width  = Double(geometry.size.width) - 60.0
                    let height = Double(geometry.size.height)
                    path.addRoundedRect(in: CGRect(x: 0.0 + 30, y: 0.0, width: width, height: height), cornerSize: CGSize(width: 8, height: 8))
                    let count = self.history.values.count
                    if count > 0 {
                        let v = self.history.values
                        let r = self.history.rawValues
                        let max = r.max()!
                        let yScale = (height - 30.0) / Double(max)
                        let xScale = width / Double(count - 1)
                        var startingVoid = v[count - 1] < 1 ? true : false
                        if startingVoid == false { path.move(to: .init(x: 0.0 + 30.0, y: height - Double(v[count - 1]) * yScale)) }
                        for i in 1 ..< count {
                            if v[count - i - 1] > 0 {
                                let point = CGPoint(x: Double(i) * xScale + 30.0, y: height - Double(v[count - i - 1]) * yScale)
                                if startingVoid == false {
                                    path.addLine(to: point)
                                } else {
                                    startingVoid = false
                                    path.move(to: point)
                                }
                            }
                        }
                    }
                }.stroke(Color.blue)
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
                Text(log.text)
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

                Button(action: { self.log.text = "Log cleared \(Date())" }) {
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
                    if !self.settings.reversedLog { self.log.text.append("\n") }
                }) { VStack {
                    Image(systemName: "backward.fill")
                        .resizable()
                        .frame(width: 12, height: 12).offset(y: 5)
                    Text(" REV ").offset(y: -2)
                    }
                }.background(settings.reversedLog ? Color.accentColor : Color.clear)
                    .border(Color.accentColor, width: 3)
                    .cornerRadius(5)
                    .foregroundColor(settings.reversedLog ? .black : .accentColor)

                
                Button(action: {
                    self.settings.logging.toggle()
                    self.app.main.log("\(self.settings.logging ? "Log started" : "Log stopped") \(Date())")
                }) { VStack {
                    Image(systemName: settings.logging ? "stop.circle" : "play.circle")
                        .resizable()
                        .frame(width: 32, height: 32)
                    }
                }.foregroundColor(settings.logging ? .red : .green)

                Spacer()

            }.font(.system(.footnote))
        }
    }
}


struct SettingsView: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var settings: Settings

    var body: some View {

        NavigationView {
            VStack {
                Spacer()

                HStack {
                    Image(systemName: "heart.fill").foregroundColor(.red)
                    Picker(selection: $settings.preferredTransmitter, label: Text("Preferred")) {
                        ForEach(TransmitterType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }

                Spacer()

                HStack {
                    Stepper(value: $settings.readingInterval,
                            in:   settings.preferredTransmitter == .miaomiao ? 1 ... 5 : 1 ... 15,
                            step: settings.preferredTransmitter == .miaomiao ? 2 : 1,
                            label: {
                                Image(systemName: "timer").resizable().frame(width: 32, height: 32)
                                Text(" \(settings.readingInterval) m") })
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 90)

                Spacer()

                Button(action: {
                    let transmitter = self.app.transmitter
                    self.app.selectedTab = .monitor
                    let centralManager = self.app.main.centralManager
                    if transmitter != nil {
                        centralManager.cancelPeripheralConnection(transmitter!.peripheral!)
                    }
                    if centralManager.state == .poweredOn {
                        centralManager.scanForPeripherals(withServices: nil, options: nil)
                    }
                }
                ) { Text(" Rescan ").bold().padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2)) }

                Spacer()

                // TODO: a unified slider
                VStack {
                    VStack(spacing: 0) {
                        Image(systemName: "hand.thumbsup.fill").foregroundColor(.green).padding(4)
                        Text("\(Int(settings.targetLow)) - \(Int(settings.targetHigh))").foregroundColor(.green)
                        HStack {
                            Slider(value: $settings.targetLow,  in: 20 ... 100, step: 1)
                            Slider(value: $settings.targetHigh, in: 140 ... 350, step: 1)
                        }
                    }.accentColor(.green)

                    VStack(spacing: 0) {
                        Image(systemName: "bell.fill").foregroundColor(.red).padding(4)
                        Text("<\(Int(settings.alarmLow))   >\(Int(settings.alarmHigh))").foregroundColor(.red)
                        HStack {
                            Slider(value: $settings.alarmLow,  in: 20 ... 100, step: 1)
                            Slider(value: $settings.alarmHigh, in: 140 ... 350, step: 1)
                        }
                    }.accentColor(.red)
                }.padding(.horizontal, 40)

                Button(action: {
                    self.settings.mutedAudio.toggle()
                }) {
                    Image(systemName: settings.mutedAudio ? "speaker.slash.fill" : "speaker.2.fill").resizable().frame(width: 24, height: 24).foregroundColor(.accentColor)
                }

                Spacer()

            }.navigationBarTitle("DiaBLE  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String)  -  Settings", displayMode: .inline)
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}


struct ContentView_Previews: PreviewProvider {
    @EnvironmentObject var app: App
    @EnvironmentObject var info: Info
    @EnvironmentObject var log: Log
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    static var previews: some View {

        Group {
            ContentView()
                .environmentObject(App(
                    currentGlucose: 234,
                    oopAlarm: "HIGH_GLUCOSE",
                    oopTrend: "FALLING_QUICKLY",
                    transmitterState: "Connected",
                    readingTimer: 567,
                    sensorState: "Ready",
                    sensorSerial: "0M0008B8CSR",
                    sensorAge: 3407,
                    battery: 54,
                    transmitterFirmware: "4.56",
                    transmitterHardware: "Version 1.23\nAA:BB:CC:DD:EE:FF",
                    params: CalibrationParameters(slopeSlope: 0.123456, slopeOffset: 0.123456, offsetOffset: -15.123456, offsetSlope: 0.123456)))
                .environmentObject(Info("Sensor + Transmitter\nError Line 1\nError Line 2"))
                .environmentObject(Log())
                .environmentObject(History(
                    values: [231, 252, 253, 254, 245, 196, 177, 128, 149, 150, 101, 122, 133, 144, 155, 166, 177, 178, 149, 140, 141, 142, 143, 144, 155, 166, 177, 178, 169, 150, 141, 132],
                    rawValues: [241, 252, 263, 254, 205, 196, 187, 138, 159, 160, 121, 132, 133, 154, 165, 176, 157, 148, 149, 140, 131, 132, 143, 154, 155, 176, 177, 168, 159, 150, 142],
                    rawTrend:  [241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 241, 242, 243, 244, 245]
                ))
                .environmentObject(Settings())
                .environment(\.colorScheme, .dark)

            LogView()
                .environmentObject(App())
                .environmentObject(Log())
                .environmentObject(Settings())
                .environment(\.colorScheme, .dark)

            SettingsView()
                .environmentObject(App())
                .environmentObject(Settings())
                .environment(\.colorScheme, .dark)
        }
    }
}
