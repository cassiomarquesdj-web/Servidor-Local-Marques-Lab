# iOS app shell

Open the `ui16-iphone` Swift package in Xcode and create an iOS App target named `UI16Phone`.

Add `Sources/UI16Controller/App/UI16PhoneApp.swift` to the app target, and add the `UI16Controller` local package target as a dependency.

Required iOS capability:

- Local Network access

Info.plist usage description:

`NSLocalNetworkUsageDescription = Controlar a mesa Soundcraft Ui16 pela rede Wi‑Fi local.`

The live controller does not require internet access. The iPhone and Ui16 must be on the same local Wi‑Fi network.
