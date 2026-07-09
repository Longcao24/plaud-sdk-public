# Plaud SDK Integration & Reverse Engineering Notes

This document summarizes the discoveries and workarounds required to make the legacy `PlaudBleSDK` successfully scan and connect to the newer **Plaud Note Pro** device.

## The Core Problem
The current `PlaudBleSDK` is outdated and uses a hardcoded service UUID whitelist when scanning for peripherals. Specifically, it ignores the `504C` service UUID broadcasted by the Plaud Note Pro. Because the SDK filters this out internally, `DeviceManager`'s `bleScanResult` delegate is never called, making the device completely invisible to the app.

## The Solution: A Step-by-Step Breakdown

### 1. Bypassing the Scan Filter
Since `PlaudDeviceAgent.shared.startScan()` drops the `504C` UUID, we must create a custom scanner (`DiagnosticScanner`) using our own `CBCentralManager` instance. This allows us to scan for all peripherals without restrictions and detect the Plaud Note Pro.

### 2. The CoreBluetooth Manager Ownership Constraint
Once our custom scanner finds the device, we **cannot** simply pass the `CBPeripheral` to the SDK. CoreBluetooth enforces a strict rule: a peripheral discovered by one `CBCentralManager` cannot be connected by another `CBCentralManager`. 

To solve this, we extract the peripheral's `identifier` (UUID) and use `BleAgent.shared.cbManager?.retrievePeripherals(withIdentifiers:)` to "steal" or retrieve a valid `CBPeripheral` instance directly from the SDK's internal `CBCentralManager`.

### 3. The Handshake & `BleDevice` Initialization (CRITICAL)
Once we have the correct `CBPeripheral`, we must manually construct a `BleDevice` object to feed back into `DeviceManager.shared.bleScanResult()`.

**What NOT to do:**
```swift
// DO NOT DO THIS
let bleDevice = BleDevice(sn: peripheral.identifier.uuidString)
```
If you initialize `BleDevice` manually with just a string or UUID, its internal `protVersion` (Protocol Version) remains `0`. When you attempt to connect, `PlaudDeviceAgent` sees `protVersion = 0` and **skips the pre-handshake entirely** (`PlaudDeviceAgent pre-handshake skipped: protVersion=0`). The Bluetooth connection succeeds at the OS level, but the app-level `blePenState` callback is never triggered, leaving the UI stuck in a "No Device" state.

**What TO do:**
```swift
// DO THIS
let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()
let bleDevice = BleDevice(
    peripheral: targetPeripheral,
    rssi: RSSI,
    manufacturerData: mfgData,
    localName: name
)
```
By using the full initializer and passing the `manufacturerData` intercepted during the scan, the `BleDevice` class automatically parses the manufacturer data to extract:
- The true Serial Number (`PL...`)
- The `projectCode`
- The `protVersion`

### 4. Preventing Cache Race Conditions
The app's UI often triggers `PlaudDeviceAgent.shared.startScan()` (e.g., in `SceneDelegate` or delayed UI blocks). By default, `DeviceManager.startScan()` clears the `cachedBleDevices` list. If the user taps "Connect" right after the cache is cleared, the app will throw a `device not in cache` error and fail to connect. 

**Fixes applied:**
- Modified `DeviceManager.startScan()` to NOT wipe `cachedBleDevices`.
- Modified `DeviceManager.bleScanResult` to merge new devices into the cache instead of overwriting it.
- Configured our `DiagnosticScanner` with `CBCentralManagerScanOptionAllowDuplicatesKey: true` so the device constantly refreshes its state in the list.

### 5. Proper Connection Invocation
Even though we inject the device manually, we must use the "front door" for connections:
```swift
PlaudDeviceAgent.shared.connectBleDevice(bleDevice: bleDevice, deviceToken: userId)
```
Calling `BleAgent.shared.connectBleDevice(...)` directly bypasses the `PlaudDeviceAgent` delegate, meaning the handshake logic will not execute, and the UI will not receive the `.connected` status or `blePenState` callbacks.

## Step 3: Transcription API Override (Bypassing Plaud Cloud)

To route the transcription audio upload directly to a custom API instead of the Plaud Cloud, the SDK's `TranscriptionManager` was modified.

1. **Upload Request**:
   - The default `uploadFile` method (which uses a 3-step S3 presigned URL approach) was replaced with a `transcribeWithCustomAPI` function.
   - The function makes a `multipart/form-data` POST request to `https://sate-v1-5.ngrok.io/process`.
   - The audio file is attached under the `audio_file` form key (e.g., `name="audio_file"`).

2. **Parsing Response**:
   - The `TranscriptionState` enum was updated to `.completed(transcript: [TranscriptionResult], summary: String)` so it could pass both the parsed transcript and summary up to the UI layer.
   - The custom API JSON is expected to return `transcript` (or `text`) and `summary`. If JSON parsing fails, the raw string response is rendered into the summary view.

3. **UI Bug Fix (Audio Player Visibility)**:
   - A critical UI bug was discovered where `FileDetailViewController` would unconditionally hide the `AudioPlayerView` if `transcriptResults` was empty (meaning the audio couldn't be played until a transcript was generated).
   - This was fixed by decoupling the player visibility from the transcript state. `prepareAudioPlayer()` is now triggered as long as the file is synced.
