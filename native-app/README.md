# Wrestling Manager — combined launch candidate

This is the original main app assembled with the current billing and remote capture components. It retains the existing bundle ID and signing team. It is not the separate RemoteScaleCheck app.

Open `Wrestling Manager Xcode App.xcodeproj` and select the **Wrestling Manager** scheme. Build number is 9. The application still loads `https://theteammanager.app/`; a local Xcode build does not publish the candidate web page or deploy backend services.

**Do not submit or begin another physical acceptance round yet.** Complete the prerequisites in `../docs/launch-acceptance-batch.md` first. Keep the owner's working project and installed build available until this candidate passes the combined round.

`Wrestling Manager Local StoreKit` is an optional simulation scheme. Normal Run uses Apple sandbox services. A simulated purchase is not evidence of a live payment or a server entitlement.

Canonical reusable components remain in `../billing-candidate` and `../native-candidate`; the tested scale package is `../native-device-check/AmericanScaleKit`. `python3 ../scripts/check-launch-native.py` checks these copies and the app identity. The combined CI builds the entire app in Debug and Release and exercises the production capture coordinator and encrypted queue in an iPad simulator.

No service-role key, private signing key or database password belongs in this directory.
