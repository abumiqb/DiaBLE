FIXME
-----

* Bubble:
   - Mac Catalyst stops receiving data from the read characteristic


TODO
----

* background mode and notifications
* with a new sensor and less than 32 values, show "NO" instead of OOP history "-1" and raw zeroes; don't draw bogus lines. 
* MiaoMiao:
   - varying the frequency (normal: [0xD1, 0x03], short:  [0xD1, 0x01], startup: [0xD1, 0x05])
* save the app.settings (simply by using a property wrapper) and the OOP measurements (simply by using HealthKit's bloodGlucose)
* a global timer for the next reading
* changing the calibration parameters updates a third curve
* a single slider for setting the desired glucose range and the alarms (see [SwiftExtensions](https://github.com/SwiftExtensions/SwiftUIExtensions))
* log: limit the number of readings; add the time when prepending "\t"; add a search field; save to a file


PLANS / WISHES
---------------

* upload the OOP data to Nightscout
* an Apple Watch app connecting directly via Bluetooth
* a predictive meal log (see [WoofWoof](https://github.com/gshaviv/ninety-two))
