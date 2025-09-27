### ArkOS 4.4 Kernel Support for Clone Devices

This repository aims to bring **ArkOS 4.4 kernel** support to certain clone devices.  
Currently, I can only maintain the devices I personally own, but contributions are always welcome via PRs.

## Supported Devices

- **XF40H** 
- **XF35H**
- **MyMini**
- **R36Pro** / **K36 PANEL1**
- **R36Max**
- **HG36**
- **R36Ultra**[[Only V1 is supported.](https://github.com/Vi-K36/EE-Clones-DTB/tree/main/R36%20Ultra%20(emmc)/Stock)]
- **R36T**
- **K36S**
- **RX6H**
- **A10Mini**
- **R36S Clone [G80CAMB v1.2 0422|0423]**

## What We Did

To make ArkOS work on clone devices, the following changes and adaptations were made:

1. **Controller driver modification**
   - Kernel Source:[lcdyk0517/arkos.bsp.4.4: Linux kernel source tree](https://github.com/lcdyk0517/arkos.bsp.4.4)
2. **DTS reverse-porting for compatibility**
   - The DTS files were **reverse-ported from the 5.10 kernel to the 4.4 kernel** to ensure proper hardware support.
   - Reference: [AveyondFly/rocknix_dts](https://github.com/AveyondFly/rocknix_dts/tree/main/3326/arkos_4.4_dts)
3. - **Built on the ArkOS distribution maintained by AeolusUX**
     - Reference repo: [AeolusUX/ArkOS-R3XS](https://github.com/AeolusUX/ArkOS-R3XS)
4. - **351Files GitHub repo**
     - Reference repo: [lcdyk0517/351Files](https://github.com/lcdyk0517/351Files)
5. - **ogage GitHub repo**
     - Reference repo: [lcdyk0517/ogage](https://github.com/lcdyk0517/ogage)

## How to Use

1. Download the **ArkOS** release image.
2. Flash the image to the SD card and run `dtb_selector.exe` to select the corresponding device, then reboot the device.

Or —
If you are a non-Windows user, enter the console, select the corresponding model, and then copy all the files to the root directory of the SD card.

## Known Limitations

- **eMMC installation is not yet supported** — currently, only booting from the SD card is available.

## Future Work

1. Enable **eMMC installation**.

## Contribution

I can only test and maintain devices I physically own.  
If you have other clone devices and want to help improve compatibility, feel free to submit a **PR**!
