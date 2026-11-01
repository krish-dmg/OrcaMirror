# OrcaMirror

High-performance native macOS USB iPhone & iPad mirroring application built directly with Apple's `AVFoundation`, `CoreMediaIO`, `AudioToolbox`, and `AppKit` frameworks.

Zero AirPlay overhead. Zero device heating. Raw 60 FPS low-latency display buffer delivery over USB for iPhone and iPad with real-time hardware color grading, OBS-stabilized borderless fullscreen, and a direct-to-DAC low-latency audio engine for competitive gaming.

---

## Key Features

- **Zero-Stress Display Pipeline**: Bypasses RTSP/AirPlay entirely. Uses native CoreMediaIO hardware framebuffer DMA over USB. Connected iPhones and iPads perform zero video compression, keeping the battery cool and CPU/GPU usage at baseline.
- **Universal iPhone & iPad Support**: Seamlessly connects to any iPhone or iPad via Lightning or USB-C. Dynamically handles any native aspect ratio (4:3, 16:9, 19.5:9, etc.) and native device resolution without distortion.
- **Ultra-Low Latency Audio Engine (25ms–45ms)**: Uses a dedicated CoreAudio Output `AudioUnit` (`kAudioUnitSubType_DefaultOutput`) paired with a lock-free power-of-two ring buffer. Delivers bit-perfect stereo sound directly to connected IEMs/headphones with active latency drift clamping.
- **Color Grading & Presentation**: Live hardware-accelerated CoreImage saturation, brightness, contrast, and gamma controls with instant presets (Vibrant, Esports Clarity, Cinematic, sRGB Accurate).
- **OBS Studio Optimization**: Space-persistent borderless fullscreen and static window titles prevent ScreenCaptureKit hook drops during live streaming.

---

## Ultra-Low Latency Audio Architecture

1. **Direct Hardware AudioUnit (`kAudioUnitSubType_DefaultOutput`)**:
   Instead of high-latency audio players, OrcaMirror hooks directly into the macOS CoreAudio hardware abstraction layer (`HALC_IOThread.client`), running in lock-step with your Mac's 3.5mm DAC or connected audio interface.

2. **Power-of-Two Lock-Free Ring Buffer (16,384 Samples / 32 KB)**:
   Buffers incoming USB audio packets seamlessly without heap allocations or mutex contention. Single-cycle bitwise masking (`& 16383`) guarantees zero dropped frames even through daisy-chained USB docks.

3. **Active Drift Clamping**:
   Continuously bounds hardware playback delay between 25ms and 45ms. If USB packet bursts or clock drift cause buffer accumulation, the engine gently pulls playback to 25ms, preserving directional audio accuracy and gunshot synchronization in competitive titles.

---

## Keyboard Shortcuts & Gestures

| Action | Shortcut / Gesture |
|---|---|
| **Display & Color Controls Panel** | `Command + ,` or `Command + C` |
| **Toggle Fullscreen** | `Command + F` (or double-click anywhere inside the window) |
| **Exit Fullscreen** | `Escape` or `Command + F` |
| **Lock / Unlock Aspect Ratio** | `Command + L` |
| **Always on Top (Floating)** | `Command + T` |
| **Actual Size (100% Retina)** | `Command + 1` |
| **Scale 75%** | `Command + 2` |
| **Scale 50%** | `Command + 3` |
| **Mute / Unmute Audio** | `Command + Shift + M` |
| **Reconnect / Refresh** | `Command + R` |
| **Context Menu** | Right-click anywhere inside the window |

---

## Building from Source

### Prerequisites
- macOS 14.0 or later (Apple Silicon native)
- Xcode Command Line Tools (`xcode-select --install`)

### Build & Run
```bash
git clone https://github.com/krish-dmg/OrcaMirror.git
cd OrcaMirror
chmod +x build.sh
./build.sh
open OrcaMirror.app
```

The build script compiles all Swift sources with `-O` release optimizations, links native Apple frameworks (`Cocoa`, `AVFoundation`, `AudioToolbox`, `CoreMediaIO`, `CoreMedia`, `CoreVideo`, `CoreImage`), bundles the resources, and codesigns the app ad-hoc.

---

## OBS Studio Setup for Streaming

1. Connect your iPhone or iPad via USB cable, unlock the device, and tap "Trust This Computer" if prompted.
2. Launch **OrcaMirror** on your Mac.
3. In **OBS Studio**, click `+` under **Sources** and add **macOS Screen Capture**.
4. Configure the source:
   - **Method**: Select **Window Capture**.
   - **Window**: Choose `[OrcaMirror] OrcaMirror — [Your Device Name]`.
5. For stretched or full view:
   - In OrcaMirror: Select **Stretch to Window** or **Aspect Fill** from the Controls panel (`Cmd + ,`) and toggle Fullscreen (`Cmd + F`).
   - In OBS: Right-click the source > **Transform** > **Stretch to Screen** (`Command + S`) or **Fit to Screen** (`Command + F`).
6. In OBS, add **Application Audio Capture** targeted at `OrcaMirror` to capture live iPhone/iPad game audio with zero delay.

---

## License

This project is licensed under the [MIT License](LICENSE).
