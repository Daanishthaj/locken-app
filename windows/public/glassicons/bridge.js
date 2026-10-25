// Windows: the buttons run in an iframe of the app window, which is the same origin. Their messages ("select:<id>", "ready")
// reach the parent by a direct call, through the name the Mac bundle already calls. Opened from another origin, the call is
// refused by the browser and nothing happens.
window.webkit = { messageHandlers: { locken: { postMessage: (message) => { try { window.parent.__lockenRailMessage?.(String(message)); } catch { /* not in the app window */ } } } } };
window.__initialProps = { items: '[]' };
