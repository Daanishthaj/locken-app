// Windows: the card runs in an iframe of the app window. Its messages (openSettings, playPause) go to the parent
// window with postMessage, same origin only, through the name the Mac bundle already calls.
window.webkit = { messageHandlers: { locken: { postMessage: (message) => window.parent.postMessage({ profileCard: String(message) }, window.location.origin) } } };
// A blank picture until the app sends the real one: the bundle's default address fails to load, and a failed
// avatar is hidden for good.
window.__initialProps = { avatarUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==', musicState: 'idle', musicIdleText: 'Nothing playing' };
