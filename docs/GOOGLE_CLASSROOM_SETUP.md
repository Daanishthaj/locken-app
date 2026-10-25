# Google Classroom: one-time setup

Locken's Mac app can link Google Classroom (Settings › Connections, or the link sheet on the Focus tab). It shows nothing until Locken has a Google OAuth client ID. Google issues one; it can't be created from the code.

## What to create (Google Cloud Console, the Locken project or a new one)

1. **Enable the API:** APIs & Services › Library › "Google Classroom API" › Enable.
2. **OAuth consent screen** (Google Auth platform › Branding and Data access):
   - App name Locken, support email, the privacy policy link `https://locken-app.vercel.app/privacy`.
   - Add exactly these two scopes (read-only, no write scopes):
     - `https://www.googleapis.com/auth/classroom.courses.readonly`
     - `https://www.googleapis.com/auth/classroom.coursework.me.readonly`
   - While the app is in **Testing**, only the test users you list (up to 100) can sign in. Add yourself.
3. **Create the client:** Credentials › Create credentials › OAuth client ID › Application type **iOS**, bundle ID `com.locken.LockenTestApp`. (iOS-type clients need no client secret, which is why none is in the app.)
4. **Put the client ID in the app:** `LockenTestApp/Info.plist`, key `GoogleClassroomClientID`, value like `1234567890-abc.apps.googleusercontent.com`. Rebuild. The link sheet's Google Classroom tab then offers "Sign in with Google".

## Before everyone can use it

- The two scopes are **sensitive**. Past 100 users Google requires verification (a demo video, the privacy policy, a domain you own). Until then it stays in Testing.
- **School accounts:** many schools block students from letting third-party apps read Classroom (Google Workspace admin › Security › API controls). Those students see "Your school doesn't let students use apps like Locken with Google Classroom." Locken can't get around that, and shouldn't. Personal Google accounts that are in Classroom work.
- The privacy policy and data-security docs already describe this connection; keep them true if the scopes change.

## How it works in the app

Sign-in uses the system browser sheet with PKCE and a random `state`. Locken keeps only the refresh token, in the Keychain, and asks Google for short-lived access tokens. It reads courses, assignments, due dates and whether each is handed in, and shows them in the same lists as Canvas (ids start with `gc:`). Unlinking tells Google to revoke the token. Only one of Canvas and Google Classroom is linked at a time.
