# KissaFocus Setup & Build Guide

## Quick Start (3 minutes)

1. **Open Project**
   ```bash
   open "LockenTestApp/KissaFocus.xcodeproj"
   ```

2. **Select Target & Destination**
   - Product → Scheme → KissaFocus
   - Product → Destination → My Mac (or your Mac model)

3. **Build & Run**
   - `Cmd + R` or Product → Run
   - Expected launch: ~15 seconds on first build

4. **Verify**
   - Window opens with "What's up next, Sir?" greeting
   - Sidebar shows 5 sample sessions
   - Metrics cards display (94%, 3h 45m, 14 Days, 100%)
   - 3D rotating torus visible in session details panel

---

## Detailed Xcode Configuration

### Project Settings

**General Tab**
- Identity: `KissaFocus`
- Bundle Identifier: `com.kissa.focus.test`
- Version: 1.0 (Build 1)
- Deployment Target: macOS 13.0

**Signing & Capabilities Tab**
- Signing: Automatic (leave Development Team blank for test)
- Capabilities: None required (SwiftUI + SceneKit are built-in)

**Build Settings → Search Paths**
- Framework Search Paths: (empty)
- Header Search Paths: (empty)
- Library Search Paths: (empty)

### Swift Compiler Settings

- Language Dialect: C++20
- Optimization Level (Debug): `-Onone`
- Optimization Level (Release): `-O`
- Strict Concurrency: Complete

### Linking

**Framework & Library Section**
- No external frameworks needed (uses only Apple frameworks):
  - SwiftUI (built-in)
  - SwiftData (built-in, iOS 17+/macOS 14+)
  - SceneKit (built-in)
  - AppKit (built-in)

---

## File Organization & Build Phases

### Expected Project Structure

```
KissaFocus.xcodeproj
├── project.pbxproj               (Xcode configuration)
└── xcshareddata/
    └── xcschemes/
        └── KissaFocus.xcscheme   (run scheme)

KissaFocus/ (source folder)
├── KissaFocusApp.swift
├── Info.plist
├── Models/
│   └── Session.swift
└── Views/
    ├── ContentView.swift
    ├── SidebarView.swift
    ├── MainContentView.swift
    ├── OverviewCardView.swift
    ├── SessionDetailsView.swift
    ├── SceneKitViewWrapper.swift
    └── ChatBarView.swift
```

### Source Files Build Phase
The project includes 9 Swift files in the compile sources:
1. KissaFocusApp.swift
2. Session.swift
3. ContentView.swift
4. SidebarView.swift
5. MainContentView.swift
6. OverviewCardView.swift
7. SessionDetailsView.swift
8. SceneKitViewWrapper.swift
9. ChatBarView.swift

All are set to **Target Membership: KissaFocus** ✓

---

## Testing & Verification

### Launch Checklist
- [ ] App window opens (1400×900 pixels)
- [ ] Sidebar appears on left with dark background
- [ ] Greeting header: "What's up next, Sir?" visible
- [ ] 4 metric cards in grid layout
- [ ] Overview card with tabs (Overview / Models)
- [ ] Activity heatmap in Overview tab
- [ ] Chat bar at bottom with "Local" selector
- [ ] Sample sessions populate sidebar

### Interaction Tests
- [ ] Click sidebar sessions → details update
- [ ] Hover over metric cards → subtle highlight
- [ ] Click Overview/Models tabs → content switches
- [ ] 3D torus rotates continuously
- [ ] Type in chat bar → send button appears
- [ ] Context menu works (hover "Local")

### Build Tests
- [ ] Clean build succeeds: `Cmd + Shift + K` then `Cmd + B`
- [ ] No warnings in Issue Navigator
- [ ] Console shows no errors
- [ ] App signature verified (if code signing enabled)

---

## If Build Fails

### Issue: "SwiftData module not found"
**Cause**: Xcode/Swift version too old  
**Fix**:
```bash
xcode-select --install              # Update command line tools
sudo xcode-select --reset           # Reset Xcode path
xcode-select -p                     # Verify: should show /Applications/Xcode.app/...
```
Requires Xcode 15.1+ for SwiftData.

### Issue: "Cannot find type 'some' in scope"
**Cause**: Swift language version set below 5.9  
**Fix**: Build Settings → Swift Language Dialect → C++20 (or latest)

### Issue: "Cannot connect to scene" (SceneKit)
**Cause**: Render server issue (rare)  
**Fix**:
```bash
killall Finder
killall Dock
# Restart Mac if persists
```

### Issue: App crashes on launch with "ModelContainer initialization failed"
**Cause**: SwiftData migration issue  
**Fix**:
```bash
# Delete app-specific container
rm -rf ~/Library/Containers/com.kissa.focus.test
# Rebuild
```

### Issue: "Cannot build for 'My Mac' — no team selected"
**Cause**: Code signing configured  
**Fix**: Build Settings → Signing → Development Team → (none) for test

---

## Advanced: Manual Project Creation (Fallback)

If the `.xcodeproj` file doesn't open correctly, create a new project manually:

1. **Create Project in Xcode**
   ```
   File → New → Project → macOS → App
   Product Name: KissaFocus
   Team: None (test app)
   Bundle ID: com.kissa.focus.test
   Language: Swift
   User Interface: SwiftUI
   ```

2. **Copy Swift Files**
   - Delete auto-generated files: ContentView.swift, KissaFocusApp.swift
   - Drag all Swift files from `/KissaFocus/` folder to project
   - Ensure "Copy items if needed" is checked

3. **Organize Groups**
   - Right-click project → New Group → "Models"
   - Drag Session.swift into Models
   - Right-click project → New Group → "Views"
   - Drag all View*.swift files into Views

4. **Configure Info.plist**
   - Copy Info.plist from provided folder
   - Build Settings → Info.plist File → `KissaFocus/Info.plist`

5. **Verify Build Settings**
   - macOS Deployment Target: 13.0
   - Swift Language Dialect: C++20
   - Product Bundle Identifier: com.kissa.focus.test

6. **Build**: `Cmd + B` should compile without errors

---

## Environment Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Xcode | 15.1 | 16.0+ |
| macOS (host) | 12.4 | 14.0+ |
| macOS (deployment) | 13.0 | 14.0+ |
| Swift | 5.9 | 6.0+ |
| RAM | 8 GB | 16 GB |

---

## Data Persistence Details

### SwiftData Configuration
- **Storage**: Local `~/Library/Application Support/com.kissa.focus.test/`
- **Models**: Session, Focus, Activity
- **Migrations**: None (fresh build)
- **Backup**: User can archive .app for version control

### Sample Data
On first launch, `initializeDummyData()` creates:
- "Untitled session" (0 min, 0%)
- "Locken site UI refinement" (145 min, 65%)
- "Framer" (230 min, 85%)
- "Clarification needed" (45 min, 30%)
- "Obsidian notes vault inspection" (120 min, 55%)

These are test fixtures only; deleting the app removes all data.

---

## Next Steps

### To Customize UI
1. Edit individual View files (Views/*.swift)
2. Change colors in ObsidianBackground() or MetricCard
3. Rebuild: `Cmd + B`
4. Preview in Canvas or run: `Cmd + R`

### To Add More Sessions
1. Open ContentView.swift
2. Modify `initializeDummyData()` function (line ~27)
3. Add new Session objects to the array
4. Rebuild & run

### To Deploy/Archive
1. Product → Archive
2. Organizer → Distribute App
3. Select "Copy App" to save .app bundle
4. Share via email, Dropbox, or cloud storage

---

## Support & Troubleshooting

**Q: Window won't open?**  
A: Check Console (Cmd + Shift + C). Look for "NSApplication initialization failed" or similar. Try cleaning build folder (Shift + Cmd + K).

**Q: 3D object not rotating?**  
A: Verify SceneKit initializes in SceneKitViewWrapper.swift. Check System Report → Graphics for Metal support.

**Q: Sidebar text is tiny?**  
A: Xcode DPI scaling issue. Restart Xcode or try different Mac external display scaling.

**Q: App quits immediately after launch?**  
A: Check Crash Logs: `~/Library/Logs/DiagnosticMessages/`. SwiftData container initialization may have failed.

---

**Happy building!** 🚀  
*Last Updated: 2026-09-18*
