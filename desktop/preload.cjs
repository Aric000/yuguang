const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('yuguang', {
  getState: () => ipcRenderer.invoke('yuguang:get-state'),
  command: (command, value) => ipcRenderer.invoke('yuguang:command', command, value),
  subscribe: callback => {
    const listener = (_event, state) => callback(state);
    ipcRenderer.on('yuguang:state', listener);
    return () => ipcRenderer.removeListener('yuguang:state', listener);
  }
});
