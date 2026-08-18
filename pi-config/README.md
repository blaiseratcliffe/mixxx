# Mixxx Pi display configuration

Hardware:
- Raspberry Pi 5
- Waveshare 9-DSI-TOUCH-B, SKU 32772
- Native panel resolution: 720x1280
- Goodix capacitive touchscreen

Display:
- DRM output: DSI-2
- Sway transform: 270 degrees
- Effective desktop: 1280x720
- Scale: 1

Touch:
- Mapped to DSI-2
- No custom calibration matrix
- Sway handles touch rotation with the output transform

Mixxx:
- Runs through XWayland using QT_QPA_PLATFORM=xcb
- Custom binary:
  /home/pi/src/mixxx-cdj/build/mixxx
- Resource path:
  /usr/share/mixxx
- XWayland class: Mixxx
- XWayland instance: mixxx

Panel:
- Overlay:
  vc4-kms-dsi-waveshare-panel-v2,9_0_inch_b
- Kernel identification:
  waveshare,9.0-dsi-touch-b

Backlight:
- Tested successfully at brightness 255
- Temporary grey/corrupted bars disappeared after writing to the
  backlight control and did not return when brightness was restored to 255.
