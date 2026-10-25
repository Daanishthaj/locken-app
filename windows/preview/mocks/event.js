// Preview only: events between windows (main and check-in tabs) travel over a BroadcastChannel.
const channel = new BroadcastChannel('locken-preview-events');
const handlers = new Map();
channel.onmessage = ({ data }) => (handlers.get(data.name) || []).forEach((fn) => fn({ payload: data.payload }));
export async function listen(name, fn) {
  handlers.set(name, [...(handlers.get(name) || []), fn]);
  return () => handlers.set(name, (handlers.get(name) || []).filter((f) => f !== fn));
}
export async function emit(name, payload) { channel.postMessage({ name, payload }); }
export async function emitTo(_target, name, payload) { channel.postMessage({ name, payload }); }
