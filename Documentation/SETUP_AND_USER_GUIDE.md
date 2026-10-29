# 🔮 Kissa Focus — Setup & User Guide

Welcome to **Kissa Focus**, a macOS deep-work headquarters crafted with a CleanMyMac-inspired liquid gradient interface, real-time SceneKit 3D worlds, adaptive AI flow sentinels, and system-wide floating check-in overlays.

---

## ⚡️ Part 1: Fast Setup & Permissions (1-Minute Quickstart)

### 1. macOS Focus Mode & Distraction Shield
Kissa Focus automatically silences notifications and blocks distractions when you start a session.
- Open **macOS System Settings** → **Focus**.
- Ensure Focus modes or Do Not Disturb are enabled.
- Alternatively, tap **"Open macOS Focus Settings"** in Kissa Focus Settings.

### 2. Apple Calendar Sync (EventKit)
- When opening the **Calendar** tab or tapping **"Sync"**, macOS will prompt to allow access to Calendar.
- Tap **Allow**. Your daily events will render on the dashboard's 3D globe and you can schedule focus sessions directly into Apple Calendar.

### 3. Screen Time & Active App Velocity
- Kissa Focus monitors the frontmost running application to measure your deep-work-to-distraction ratio.
- No special configuration needed; it tracks foreground app transitions automatically every second.

### 4. Optional AI Agent Keys
- Go to **Settings** → **AI Agents & Verification**.
- Toggle on and paste your API key for **OpenAI**, **Gemini**, **Claude**, or **GitHub** if you want external API verification.

---

## 🚀 Part 2: How to Use Kissa Focus

### 1. Start on the Dashboard
- View your real-time **Focus Score**, active deep-work velocity, and scheduled meetings around the interactive **3D Earth Globe**.
- Tap **"Begin Today's Sprint"** to jump straight into a session.

### 2. Define Your Mission & Utilize AI Rephrase
- In the **Focus Session** tab, type what you want to achieve today (e.g. *"finish essay"* or *"fix backend bug"*).
- Tap **`✨ AI Rephrase`**: The built-in AI will rephrase your thought into an outcome-oriented goal (e.g., *"🎯 Ship robust API error handling with comprehensive unit tests"*).

### 3. Choose Duration & Target App
- **Duration**: Tap standard presets (`15 min`, `25 min`, `45 min`, `60 min`) or tap **`Custom`** to dial in any sprint length from 5 to 360 minutes.
- **Target App**: Select the primary tool you'll be utilizing (e.g., **Google Chrome**, **Xcode**, **Notion**, **Cursor**, **Terminal**, **Figma**, etc.).

### 4. System-Wide Floating AI Check-In HUD
- While working inside Chrome, Xcode, or Word, the AI monitors your flow state and adaptively decides optimal moments to check in.
- A translucent, non-intrusive floating HUD will appear over your screen with 2 questions:
  1. **Energy & Flow**: (*⚡️ Energized*, *🧘 Deep Flow*, *🧱 Blocked*, *☕️ Need Break*).
  2. **Completion Slider**: Slide from **0% to 100%** to record your progress.
- Tap **"Continue Flow"** to dismiss the HUD and stay in the zone.

### 5. Victory Debrief & Project Studio Sync
- When you finish your sprint or complete your day, tap **"Finish Task & Run Final Debrief"**.
- Record your final outcome and reflection notes.
- Kissa Focus automatically saves a formatted Markdown note directly into your **Project Studio Notes** workspace.

---

*Crafted with native SwiftUI, SceneKit, EventKit, and AppKit.*
