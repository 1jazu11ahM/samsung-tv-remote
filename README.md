# TV Remote for Samsung QN85BA (iPhone)

SwiftUI app that controls a 2016+ Samsung Tizen TV over your Wi‑Fi.

## Install on your iPhone (needs a Mac with Xcode 15+)
1. Unzip and double-click `SamsungRemote.xcodeproj`.
2. Click the project > target **SamsungRemote** > **Signing & Capabilities**.
   Pick your Team (a free Apple ID works). If Xcode says the bundle ID is taken,
   change it to anything unique, e.g. `com.yourname.tvremote`.
3. Plug in your iPhone, select it as the run destination, press **Run** (⌘R).
4. On the iPhone: Settings > General > VPN & Device Management > trust your developer profile.
   iOS 16+: also turn on Settings > Privacy & Security > Developer Mode.
5. Open the app, allow **Local Network** access, enter the TV's IP, tap Connect,
   then choose **Allow** on the TV.

Free Apple ID apps expire after 7 days; just press Run again from Xcode to refresh.

## TV settings
- IP address: Settings > General > Network > Network Status > IP Settings.
  Tip: reserve this IP in your router so it never changes.
- Turn on from phone: Settings > General > Network > Expert Settings > Power On with Mobile.

## Features
Power (with Wake-on-LAN), D-pad/OK, Back, Home, Source, Settings, Play/Pause,
hold-to-repeat volume/channel/arrows, mute, number pad, Netflix/YouTube/Prime/Disney+
shortcuts, and a phone keyboard that types into TV search boxes.
