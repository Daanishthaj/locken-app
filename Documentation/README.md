# Kissa Focus

Kissa Focus is a premium native macOS focus and accountability app inspired by the intentional environment of Japanese work cafés.

## Open and Run in Xcode

1. Run the setup script to generate the Xcode project:
   ```bash
   ruby setup_project.rb
   ```
2. Open `KissaFocus.xcodeproj` in Xcode.
3. Select the **KissaFocus** macOS scheme.
4. Choose a compatible Mac destination (My Mac).
5. Configure signing with your Apple developer team in the Signing & Capabilities tab.
6. Build and run using `Command + R`.

## Credentials & Configuration

Configure AI and integration credentials through the app’s Settings interface, not by editing source code. 

For local development testing of integrations, a `Configuration.example.plist` is provided. **Do not** add real API keys to this file if it will be committed. Rename it to `Configuration.plist` (which is git-ignored) and add your keys there.

Use the Integrations section to connect Notion and Google Drive securely.

## Privacy & Tokens

- Tokens (Notion, Google Drive, AI Providers) are stored in the macOS Keychain.
- They are NEVER stored in source code, UserDefaults, or exported.
- Do not commit any real `.env` or credential files.
