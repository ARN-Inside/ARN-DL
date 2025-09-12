# ARN-DL

The ultimate GUI for high-quality media downloads, powered by an intelligent engine with multi-stage fallbacks, client emulation, and a fully integrated updater.

Our straightforward process is powered by a robust backend designed for maximum resilience and quality, wrapped in a unique, retro-inspired terminal interface with a custom audio ambiance.

## Core Features

* **Interactive Menu System**: A fully navigable, keyboard-driven interface for a smooth user experience.
* **Multiple Download Modes**: Choose between downloading `Video`, `Audio Only`, or both `Video + Audio` for any given link.
* **Selective Quality Profiles**: Select your desired video quality, from `480p` up to `Ultra HD (4K/8K)`, ensuring you get the perfect file for your needs.
* **Intelligent Format Analysis**: Automatically analyzes available streams to select the best possible video and audio quality based on your preferences.
* **Advanced Playlist Management**: When a playlist link is entered, the script displays an interactive menu to select all, or specific videos to download.
* **Multi-Stage Fallback System**: If a download fails, the script automatically retries using different strategies and containers (e.g., from MKV to MP4) to ensure success.
* **Multi-Client Emulation**: Bypasses regional or device-specific restrictions by emulating various clients (Web, iOS, Android, TV, etc.).
* **Exhaustive Brute-Force Cascade**: For the most challenging links, this mode systematically attempts every possible quality and client combination until it finds one that works.
* **Advanced Audio Processing**: Downloads audio in high-fidelity `.wav` (studio-grade 24-bit, 48kHz) or high-bitrate `.mp3` (320kbps).
* **Post-Download Toolkit**: Includes options for re-encoding MKV files to the more compatible MP4 format and automatically injecting metadata into downloaded files.
* **Integrated Updater**: Keeps the script and its core dependencies (yt-dlp, FFmpeg) up-to-date with a single command.
* **Companion Icon Utility**: A batch script is included to create a desktop shortcut, making it easy to launch ARN-DL.

## Getting Started

Follow these steps to get ARN-DL installed and configured.

### 1. Run the Setup Utility

Run the `Setup.exe` file located in the script directory.

This is a one-time setup utility that will configure ARN-DL for a seamless experience. 
It creates a desktop shortcut and uses the Windows Task Scheduler to handle administrator permissions automatically. 
This ensures you won't be prompted by UAC (the administrator approval pop-up) every time you launch the script.

### 2. Launch the Application

Double-click the newly created "ARN-DL" desktop icon to start the application.

### 3. Using Cookies (Optional)

For the best results, especially with websites that use anti-bot protections, it is highly recommended to use cookies from your browser.

1.  When you first run the script, a `cookies.txt` file is created in the same folder.
2.  Open this file in a text editor and follow the instructions inside to export your browser cookies using a recommended extension like **Get cookies.txt LOCALLY**.
3.  Paste the exported text into the `cookies.txt` file and save it.

This step allows ARN-DL to download age-restricted content, private videos (from your account), and bypass most "prove you are human" checks.

## User Guide: The Download Flow

The script guides you through a series of menus to configure your download precisely.

1.  **Main Menu**: After starting, you are presented with the main menu. Here, you can choose to:
    * Paste a single or multiple links.
    * Manage cookies (opens `cookies.txt`).
    * Access the Options menu.
    * Update the tools or the script itself.

2.  **Format Selection Menu**: After providing a link, you'll be asked what you want to download:
    * **Video**: Downloads the video with its audio track in a single file (MP4 or MKV).
    * **Audio Only**: Downloads only the audio track and saves it as a high-quality `.wav` or `.mp3` file.
    * **VIDEO + SEPARATE AUDIO**: Downloads the video file and also creates a separate, high-quality audio file.

3.  **Quality Selection Menu**: Next, you define the quality:
    * **Video Quality**: Choose a maximum resolution, such as "High (Max 1080p)" or "Ultra (4k, 8k...)". The script will find the best available quality up to that limit.
    * **Audio Quality**: If you are downloading audio, choose between `.WAV` (lossless, highest quality) and `.MP3` (high-bitrate, smaller file size).

4.  **Playlist Selection Menu**: If you enter a link to a playlist, a final menu appears. It lists all the videos in that playlist, allowing you to:
    * Navigate through the list.
    * Select or deselect individual videos.
    * Press 'A' to select or deselect all videos at once.
    * Press 'V' to validate your selection and begin downloading.

## In-Depth: Core Mechanisms Explained

ARN-DL is built on several layers of technology to ensure a high success rate for downloads.

### Intelligent Format Selection

Instead of just grabbing the "best" format available, the script performs a **Smart Analysis** when you provide a link. It fetches a complete list of all available video and audio streams, then filters them based on your quality selection (e.g., max 1080p). It prioritizes modern, high-quality codecs like AV1/VP9 for video and Opus for audio, which are typically found in separate streams. If these are available, it downloads them and merges them into a high-quality MKV or MP4 container.

### Multi-Stage Fallback Engine

If the initial Smart Analysis fails, the script doesn't just give up. It initiates a fallback sequence:
1.  **Container Fallback**: If the preferred container (e.g., MKV with Opus audio) fails, it will automatically try a more compatible combination (e.g., MP4 with AAC audio).
2.  **Generic Fallback**: If specific format selection fails, it will ask for the `bestvideo+bestaudio` streams and attempt to merge them.
3.  **Last Resort Fallback**: If all else fails, it will attempt to download into the *other* primary container format as a last-ditch effort.

This multi-layered approach ensures that even if one method is blocked, another is likely to succeed.

### Client Emulation

Some websites serve different media files depending on the device making the request. ARN-DL leverages this by cycling through different **client profiles** (like `web`, `ios`, `android`, `tv_embedded`). If a download fails with the default client, it will retry the same request while pretending to be another device, often bypassing blocks that target standard desktop browsers.

### Cookie Management

The script automatically creates and manages a `cookies.txt` file. When this file contains valid, Netscape-formatted cookies, `yt-dlp` will include them with every download request. This makes your requests appear as if they are coming from a logged-in browser session. This is essential for accessing private content, bypassing age-gates, and avoiding CAPTCHA challenges.

### Brute-Force Mode

When Smart Analysis isn't enough, you can enable **Brute-Force Mode**. This is the script's ultimate weapon. It generates a comprehensive list of every possible resolution and codec combination and systematically tries to download each one, iterating through every available client profile for each attempt. While extremely slow, this method is designed to find a working combination for even the most problematic and heavily protected video links.

### Post-Download Processing

Once a file is downloaded, ARN-DL can perform additional tasks:
* **High-Quality Re-encoding**: If you download a `.mkv` file but need a more compatible `.mp4`, the script can re-encode it using FFmpeg. It uses `libx264` with a quality-focused CRF setting and high-bitrate AAC audio to minimize quality loss.
* **Metadata Injection**: The script automatically uses FFmpeg to write a "Downloaded by ARN-DL" comment into the file's metadata, making it easy to identify where your files came from.

## A Note on the Integrated Audio Experience

ARN-DL is a labor of love, offered to the community for free. A great deal of effort went into creating not just a functional tool, but also a unique user experience, complete with custom animations and a distinct audio ambiance.

The choice of music is a deliberate tribute to the monumental work of Terry A. Davis. It reflects the project's own creative ambition:

> Terry A. Davis built an entire OS alone, a digital temple dictated by a revelation. Imagine his creative power with today's AI and cloud capabilities. This is the scale of creation I'm aiming for.

To preserve this intended experience, the script includes an **integrity check mechanism**. At startup and during runtime, it verifies that the core audio files (`ARN_Inside.wav` and the TempleOS remix) are present and have not been modified by checking their unique digital signatures (SHA256 hashes).

If these files are missing or altered, the application will lock down to protect and preserve user experience. We kindly ask users to respect the work put into this project by not modifying or removing these core audio components.

## Dependencies & Credits

This project relies on amazing external tools and assets to function. A huge thank you to their respective creators.

### Software & Libraries

**yt-dlp**

Used to extract information and download content from web platforms. Although its license (The Unlicense) does not impose any restrictions, the project deserves our full recognition.
* **Project:** [yt-dlp on GitHub](https://github.com/yt-dlp/yt-dlp)
* **License:** The Unlicense

**FFmpeg**

Used for all video and audio processing operations, such as re-encoding, converting to .mp4 or .wav, and extracting stream information.
The FFmpeg binaries included in this project are builds from gyan.dev and are licensed under the LGPL v3.0.
* **Project:** [Official FFmpeg Website](https://ffmpeg.org/)
* **License:** LGPL v3.0
* **License Copy:** The full text of the license is available in the `LICENSE_FFMPEG.txt` file in this repository.

### Assets & Music

**Download Music:** TempleOS Hymn Risen (Remix)
* **Artist:** Dave Eddy
* **Artist Website:** [daveeddy.com](https://daveeddy.com)
* **Related Project:** [ysap.sh](https://ysap.sh)