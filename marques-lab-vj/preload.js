const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('marquesLabVJ', {
  pickMedia: () => ipcRenderer.invoke('pick-media'),
  getAppInfo: () => ipcRenderer.invoke('app-info'),
  on: (channel, callback) => {
    const allowed = new Set(['open-import', 'save-project', 'show-shortcuts']);
    if (!allowed.has(channel)) return () => {};
    const listener = (_, ...args) => callback(...args);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  }
});
