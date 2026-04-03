# Personal Single-App Android Bridge (Automatic Install)

This is now tuned for your personal use and your provided APK URL.

Default APK source used by the script:

`https://www.apkmirror.com/wp-content/themes/APKMirror/download.php?id=8688287&key=469c435740615b5924a1d6224990def37bacc66a`

## One command

```bash
bash tools/android_app_bridge.sh
```

What happens automatically:

1. Installs Homebrew if missing.
2. Installs `adb` + `scrcpy` if missing.
3. Waits for your Android phone (USB debugging on).
4. Downloads and installs your APK.
5. Tries to auto-detect the installed package.
6. Syncs files via `~/AndroidBridge/upload` and `~/AndroidBridge/download`.
7. Launches the app and opens direct control (`scrcpy`).

## Optional flags

- `--no-apk-install` to skip download/install.
- `--apk-url <url>` to override the default APK URL.
- `--package <package>` to force package name.
- `--activity <activity>` for a specific activity.
- `--ask` to turn on confirmation prompts.

## File transfer paths

- Local upload: `~/AndroidBridge/upload`
- Local download: `~/AndroidBridge/download`
- Device upload: `/sdcard/Download/BridgeUpload`
- Device download: `/sdcard/Download/BridgeDownload`
