Experimenting with the Droplet, Bubble and MiaoMiao transmitters I bought for the Abbott FreeStyle Libre sensor and trying something new compared to the current apps:

* a universal **SwiftUI** application for iPhone, iPad and Mac Catalyst;
* scanning the Libre directly via **NFC**;
* using online servers for calibrating just like **Abbott’s algorithm**;
* a detailed **log** to check the traffic from/to the BLE devices and remote servers.

Still too early to decide the final design (and the evil logo 😈), here there are the first rough screenshots:

<img src="https://drive.google.com/uc?export=view&id=155iMrE7xJzAYH0XLx4OlVP1o0u5otryC" width="25%" />&nbsp;<img src="https://drive.google.com/uc?export=view&id=1r3pdVHJf_-pgqLHOCHtXLo56C7Dvh4-9" width="25%" />

The project started as a single script for the iPad Swift Playgrounds and was quickly converted to an app by using a standard Xcode template.

It should compile finely without dependencies just after changing the _Bundle Identifier_ in the _General_ panel and the _Team_ in the _Signing and Capabilities_ tab of Xcode (Spike users know already very well what that means... ;) ).
