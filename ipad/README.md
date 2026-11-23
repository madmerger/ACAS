# ACAS for iPad

Minimal SwiftUI shell for iPadOS 18.0 or later. Module rows are placeholders;
there is no accounting data storage or backend integration yet.

Open `ACAS.xcodeproj` in Xcode 16.4 or later and select the shared `ACAS`
scheme and an iPad simulator. No signing team is needed for simulator builds.

From the repository root, choose an available iPad simulator running iOS 18.0 or later
and run the model tests:

```sh
xcrun simctl list devices available
IPAD_UDID="<available iPad UDID>"
xcodebuild test -project ipad/ACAS.xcodeproj -scheme ACAS \
  -destination "platform=iOS Simulator,id=$IPAD_UDID" CODE_SIGNING_ALLOWED=NO
```

For a build without tests, replace `test` with `build`.

The generated project is committed, so building and CI do not need XcodeGen.
After changing `project.yml`, install XcodeGen (`brew install xcodegen`) and run:

```sh
xcodegen generate --spec ipad/project.yml
```

Commit both the specification and regenerated project, including its shared scheme.
