# KissaFocus — Private Test macOS Application

A native macOS test application featuring a luxury obsidian dark-slate aesthetic with premium squircle design system, matching the **The Atelier — Mission Readiness** reference dashboard.

## 📋 Project Structure

```
KissaFocus/
├── KissaFocusApp.swift           # Main app entry point & AppDelegate
├── Models/
│   └── Session.swift             # SwiftData models (Session, Focus, Activity)
├── Views/
│   ├── ContentView.swift         # Main layout (sidebar + content)
│   ├── SidebarView.swift         # Navigation sidebar with routines
│   ├── MainContentView.swift     # Primary content area with metrics grid
│   ├── OverviewCardView.swift    # Overview/Models metrics card
│   ├── SessionDetailsView.swift  # Selected session details panel
│   ├── SceneKitViewWrapper.swift # 3D torus visualization
│   └── ChatBarView.swift         # Bottom input bar + utilities
├── Info.plist                     # App metadata
└── KissaFocus.xcodeproj/
    └── project.pbxproj           # Xcode project configuration
```

## 🎯 Features

### Core UI Components
- **Sidebar Navigation**: Collapsible sidebar with primary nav items and expandable Routines section
- **Metrics Cards**: 4-card grid showing Cognitive State, Chronometer, Discipline, Sanctuary
- **Overview Card**: Tabbed card with stats (Sessions, Messages, Tokens, etc.) and activity heatmap
- **3D Visualization**: SceneKit-rendered rotating torus with luxury lighting
- **Chat/Command Bar**: Bottom-docked input with context selector and action buttons

### Design System
- **Obsidian Dark Theme**: Deep navy-slate background with subtle noise overlay
- **Squircle Borders**: Continuous rounded corners (14-16pt radius) on all containers
- **Ultra-Thin Materials**: Native `.ultraThinMaterial` vibrancy and backdrop blur
- **Aurora Lighting**: Animated gradient effects in the greeting header
- **Premium Typography**: SF Pro (system) + monospaced metrics

### Data & Architecture
- **SwiftData Persistence**: Isolated local-only test data (no network/backend)
- **Mock Sessions**: 5 pre-populated sample sessions for testing
- **Activity Tracking**: Per-session focus time and completion percentage
- **No Production Crossover**: Completely separate app bundle and data directory

### Accessibility
- **VoiceOver Support**: All interactive elements labeled with accessibility traits
- **Keyboard Navigation**: Native macOS keyboard shortcuts and focus rings
- **Reduced Motion**: Respects system motion preferences
- **High Contrast**: Dark mode optimized with adequate foreground/background ratios

## 🚀 Getting Started

### Prerequisites
- **Xcode 15.4+** (tested with 16.0+)
- **macOS 13.0+** deployment target
- **Swift 5.9+** language runtime

### Opening in Xcode

1. Navigate to the project directory:
   ```bash
   cd "LockenTestApp"
   ```

2. Open in Xcode:
   ```bash
   open KissaFocus.xcodeproj
   ```

3. Select the **KissaFocus** target and **My Mac** destination

4. Press `Cmd + R` to build and run

### First Run
- The app will automatically populate 5 sample sessions on launch
- Select any session from the sidebar to see details
- Toggle the Routines folder to collapse/expand the session list
- Interact with the 3D visualization (it auto-animates)

## 🎨 Customization

### Changing Colors
Edit color values in individual View files:
- **ObsidianBackground()**: Background gradients (ChatBarView.swift:205)
- **Metric Cards**: Update `.blue`, `.green`, etc. in MetricCard (MainContentView.swift:95)
- **3D Torus**: Modify rimLight/keyLight colors in SceneKitViewWrapper.swift:50

### Adding Sessions
Modify `initializeDummyData()` in ContentView.swift:27 to add/remove sample sessions.

### Adjusting Layout
- **Sidebar width**: Line 45 in SidebarView.swift → `.frame(width: expanded ? 220 : 70)`
- **Spacing**: Global `spacing:` parameters in VStack/HStack
- **Metrics grid**: Adjust 2x2 layout in MetricsGridView (MainContentView.swift:40)

## 📝 Build Configuration

**Bundle Identifier**: `com.kissa.focus.test`  
**Deployment Target**: macOS 13.0  
**Swift Language Dialect**: Swift 5.9+  
**Code Sign Style**: Automatic (unsigned for test build)

## ⚙️ SwiftData Models

```swift
// Session: Focus project workspace
@Model final class Session {
    var id: UUID
    var title: String                    // e.g., "Locken site UI refinement"
    var category: String                 // e.g., "Design"
    var description: String
    var createdAt: Date
    var isActive: Bool
    var focusMinutes: Int                // Total minutes focused
    var completionPercentage: Double     // 0–100
    var activities: [Activity]           // Activity log
}

// Focus: Available focus areas/categories
@Model final class Focus {
    var id: UUID
    var name: String
    var description: String
    var color: String                    // Hex or system color name
    var icon: String                     // SF Symbol
}

// Activity: Daily focus log entry
@Model final class Activity {
    var id: UUID
    var date: Date
    var count: Int                       // Number of focus sessions
    var focusMinutes: Int                // Total minutes
}
```

## 🔐 Privacy & Isolation

- **No network calls**: All data is local-only
- **SwiftData only**: No Supabase or remote sync in test version
- **Separate bundle**: Cannot interfere with production app
- **Temp data**: Sessions are test fixtures; will not affect real user data

## 🐛 Troubleshooting

### Build Fails
- Verify Xcode 15.4+: `xcode-select --version`
- Clean build folder: `Shift + Cmd + K`
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`

### 3D Visualization Not Visible
- SceneKit requires macOS 10.13+
- If blank, verify SCNView is properly initialized in SceneKitViewWrapper.swift:22
- Check Console for any Metal/rendering errors

### Sessions Not Loading
- Verify SwiftData is properly initialized in KissaFocusApp.swift:15
- Check that `KissaFocus/Models/Session.swift` exists and compiles
- Look for migration errors in Xcode console

## 📄 License

Copyright © 2026 – All rights reserved.  
Private test application for KissaFocus.

---

**Status**: ✅ Ready for Xcode import and testing  
**Last Updated**: 2026-09-18  
**Swift Version**: 5.9+
