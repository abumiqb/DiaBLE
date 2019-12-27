FIXME
-----

* clearing the log shrinks it
* Bubble:
   - Mac Catalyst stops receiving data from the read characteristic


TODO
----

* MiaoMiao:
   - varying the frequency (normal: [0xD1, 0x03], short:  [0xD1, 0x01], startup: [0xD1, 0x05])
   * save the app.settings (simply by using a wrappable property) and the measurements (simply by using HealthKit's bloodGlucose).
* a global timer for the next reading
* changing the calibration parameters updates a third blue curve
* a single slider for setting the desired glucose range and the alarms


PLANS / WISHES
---------------

* upload the scanned data to Nightscout
* an Apple Watch app connecting directly via Bluetooth
* a predictive meal log (see [WoofWoof](https://github.com/gshaviv/ninety-two))

