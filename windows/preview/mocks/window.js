export function getCurrentWindow() {
  return { close: async () => {}, setFocus: async () => {}, unminimize: async () => {}, destroy: async () => { window.__destroyed = true; }, onCloseRequested: async (handler) => { window.__closeRequested = handler; return () => {}; } };
}
