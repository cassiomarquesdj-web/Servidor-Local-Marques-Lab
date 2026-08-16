# Build on iPhone

1. Open `ui16-iphone` in Xcode.
2. Create an iOS App target named `UI16Phone` using SwiftUI and iOS 17+.
3. Add the `Sources/UI16Controller/App/UI16PhoneApp.swift` file to the app target.
4. Add the `Sources/UI16Controller` directory as the local `UI16Controller` package target.
5. Set the bundle identifier to `com.marqueslab.ui16`.
6. Add `ui16-iphone/ios/UI16Phone-Info.plist` to the app target.
7. Build to a physical iPhone. The iPhone and Ui16 must be connected to the same Wi-Fi network.

The live-control path is local-only. No account or internet connection is required while controlling the mixer.
