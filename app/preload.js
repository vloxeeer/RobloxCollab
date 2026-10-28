const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
    // Window
    minimize: () => ipcRenderer.send('window-minimize'),
    maximize: () => ipcRenderer.send('window-maximize'),
    close: () => ipcRenderer.send('window-close'),

    // Server
    startServer: (port) => ipcRenderer.invoke('server-start', port),
    stopServer: () => ipcRenderer.invoke('server-stop'),
    getServerStatus: () => ipcRenderer.invoke('server-get-status'),

    // Tunnel
    startTunnel: (port) => ipcRenderer.invoke('tunnel-start', port),
    stopTunnel: () => ipcRenderer.invoke('tunnel-stop'),

    // Plugin
    installPlugin: () => ipcRenderer.invoke('install-plugin'),

    // Rooms
    getRooms: () => ipcRenderer.invoke('get-rooms'),
    kickUser: (roomId, userId) => ipcRenderer.invoke('kick-user', roomId, userId),
    deleteRoom: (roomId) => ipcRenderer.invoke('delete-room', roomId),

    // Misc
    openExternal: (url) => ipcRenderer.invoke('open-external', url),

    // Events
    on: (channel, callback) => {
        const validChannels = [
            'server-status', 'server-log', 'tunnel-status',
            'room-event', 'stats-update'
        ];
        if (validChannels.includes(channel)) {
            ipcRenderer.on(channel, (event, ...args) => callback(...args));
        }
    }
});