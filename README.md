# BYEREDX

## 📖 Overview

**BYEREDX** solves a common frustration for macOS users coming from other operating systems. By default, clicking the red 'x' on a macOS window closes the window but often leaves the application running in the background, consuming memory and cluttering the Dock.

**BYEREDX** runs silently in the background and intercepts the window-close action to terminate the application process entirely. It features robust operation modes to either exclude specific applications or target only specific ones, offering seamless integration with macOS via the menu bar.

<img width="520" height="501" alt="Screenshot 2" src="https://github.com/user-attachments/assets/627f187c-a246-4df9-b5ca-e86ea6f97fbb" />
<img width="514" height="498" alt="Screenshot 1" src="https://github.com/user-attachments/assets/bb8c80c3-678f-4bc2-b141-4f90bc421513" />


## ✨ Key Features

-   **True Quit Automation:** Instantly quits the application when the last window is closed via the red 'x'.
-   **Dual Operation Modes:**
    -   **Exclude Mode (Whitelist):** Close everything *except* selected apps.
    -   **Target Mode (Blacklist):** Close *only* the selected apps.
-   **Smart List Management:** Automatically remembers separate lists for each mode.
-   **In-App Updates:** Check for the latest version directly within the app settings.
-   **Menu Bar Integration:** Unobtrusive status bar icon for quick access to settings.
-   **Start at Login:** Option to launch automatically upon system startup.
-   **Language Support:** Interface available in English and Thai.

## 📅 Version History
### Version 1.0.5 (Current)
-   Added 'Report a Problem' feature.

### Version 1.0.4
-   Watchlist Trap System: Fixed a persistent issue where apps like Apple Notes and Music would not close on the very first launch.
-   CoreGraphics Verification: The app now uses a direct screen scan (CoreGraphics) when specific apps lose focus, ensuring 100% reliable closing without waiting for Accessibility connections.
-   Improved Stability: Optimized background monitoring logic.
            
### v1.0.3
-   Adjust stability.

### v1.0.2 
-   Added **Target Mode** (Blacklist). You can now choose to only close specific apps.
-   Added **Check for Updates** button in the "About" section.
-   Automatic update checking upon application launch.
-   **Improvement:** Separated database lists for Exclude Mode and Target Mode (lists are now independent).
-   **Improvement:** Enhanced UI for List Manager with visual indicators (Green Shield for Exclude, Red Target for Blacklist).

### v1.0.1
-   Added **Start at Login** functionality.
-   Implemented **Google Chrome Protection** logic (prevents closing Chrome if a whitelisted Chrome App is running).
-   Added "About" menu with version information.
-   Refined Whitelist system logic.

### v1.0.0
-   Initial release.
-   Core functionality: Detect window closure and terminate processes.
-   Basic Whitelist system (Exclude Mode only).
-   Multi-language support (English/Thai).

## ⚙️ Installation

### 1. Download
Go to the [**Releases**](https://github.com/trondarkmode/BYEREDX/releases/) page on this repository and download the latest version (`.zip` or `.dmg`).

### 2. Install
1.  Unzip the downloaded file.
2.  Move **BYEREDX.app** to your **Applications** folder.
3.  Open BYEREDX.app.

HOW TO INSTALL [**YOUTUBE**](https://youtu.be/7C3wo4A3gWY)

### 3. Grant Permissions (Crucial Step)
MacOS requires explicit permission for applications to control other windows.
1.  Launch **BYEREDX**.
2.  A system prompt may appear requesting **Accessibility Access**.
3.  Open **System Settings** > **Privacy & Security** > **Accessibility**.
4.  Find **BYEREDX** in the list and toggle the switch to **ON**.
    * *Note: If the app is already checked but not working, try unchecking and checking it again.*

## 🚀 Usage

Once installed and permissions are granted, BYEREDX works automatically in the background.

### Menu Bar Controls
-   **Right-click** the BYEREDX icon (blue 'x') in the status bar to access the menu.
-   **Settings:** Opens the main configuration window.
-   **About BYEREDX:** Check the current version and **Check for Updates**.
-   **Quit BYEREDX:** Completely stop the utility.

### Configuration (Settings)

#### 1. General Tab
-   **Enable Auto Quit:** Toggle the main functionality on/off.
-   **Start at Login:** Automatically start the app when you log in.
-   **Hide Recent Apps:** Helper tool to hide the "Recent Apps" section on the Dock.

#### 2. List Manager Tab (New in v1.0.2)
You can choose how BYEREDX behaves by selecting a **Mode** from the dropdown menu:

* **🛡️ Mode: Close All Apps (Except Whitelist)**
    * **How it works:** This is the default mode. BYEREDX will close *every* application you click 'x' on.
    * **Usage:** Add apps here that you **DO NOT** want to close (e.g., Music Players, File Copying tools).
    * *Visual Indicator:* Green Shield Icon.

* **🎯 Mode: Close Only Listed Apps (Target)**
    * **How it works:** BYEREDX will do nothing by default. It will *only* close applications that are added to this list.
    * **Usage:** Add specific annoying apps here that you definitely want to kill immediately (e.g., Calculators, System Tools).
    * *Visual Indicator:* Red Target Icon.

*Note: The lists for both modes are saved separately. Switching modes will automatically load the corresponding list.*

## 📋 Compatibility

-   **OS:** macOS 11.0 (Big Sur) or later.
-   **Architecture:** Apple Silicon (M1/M2/M3) and Intel-based Macs.

## 📄 License

**BYEREDX** is Freeware.
Copyright © 2026. All rights reserved.

This software is provided for personal use only. Redistribution for commercial purposes, modification, reverse engineering, or selling of this software is strictly prohibited. See the `LICENSE` file for more details.

---
*Developed with ❤️ for the macOS community.*
