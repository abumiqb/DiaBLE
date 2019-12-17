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
}

struct Monitor: View {
    @EnvironmentObject var app: App
    @EnvironmentObject var info: Info
    @EnvironmentObject var history: History
    
    @State var showingLog = false
    
    var body: some View {
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
    // TODO
    @State var interval = 5
    
    // FIXME: timer doesn't update
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            Text("TODO: Settings")

            Spacer()

            HStack {
                
                Picker(selection: $preferredTransmitter, label: Text("Preferred transmitter")) {
                    ForEach(TransmitterType.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }.pickerStyle(SegmentedPickerStyle())
                
                Button(action: {
                    let transmitter = self.app.currentTransmitter
                    // FIXME: crashes in a playground
                    self.selectedTab = .monitor
                    let centralManager = self.app.main.centralManager
                    centralManager.cancelPeripheralConnection(transmitter!.peripheral!)
                    self.app.preferredTransmitter = self.preferredTransmitter
                    centralManager.scanForPeripherals(withServices: nil, options: nil)
                }
                ) { Text("Rescan") }
            }

            // FIXME: Stepper doesn't update when in a tabview
            Stepper(value: $interval, in: 1 ... 15, label: { Text("Reading interval: \(interval)m") })
            
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
