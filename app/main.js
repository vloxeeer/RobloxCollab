const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, shell, dialog } = require('electron');
const path = require('path');
const ServerCore = require('./server-core');
const TunnelManager = require('./tunnel');

let mainWindow;
let tray;
let serverCore;
let tunnelManager;

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1100,
        height: 750,
        minWidth: 900,
        minHeight: 600,
        frame: false,
        transparent: false,
        backgroundColor: '#0d0d14',
        titleBarStyle: 'hidden',
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false
        },
        icon: path.join(__dirname, 'icon.ico'),
        show: false
    });

    mainWindow.loadFile('index.html');

    mainWindow.once('ready-to-show', () => {
        mainWindow.show();
    });

    mainWindow.on('close', (e) => {
        e.preventDefault();
        mainWindow.hide();
    });
}

function createTray() {
    const icon = nativeImage.createFromPath(path.join(__dirname, 'icon.ico'));
    tray = new Tray(icon.resize({ width: 16, height: 16 }));
    
    const contextMenu = Menu.buildFromTemplate([
        { label: 'Открыть RobloxCollab', click: () => mainWindow.show() },
        { type: 'separator' },
        { label: 'Выход', click: () => { app.quit(); process.exit(0); } }
    ]);
    
    tray.setToolTip('RobloxCollab');
    tray.setContextMenu(contextMenu);
    tray.on('double-click', () => mainWindow.show());
}

app.whenReady().then(() => {
    createWindow();
    createTray();

    serverCore = new ServerCore();
    tunnelManager = new TunnelManager();

    // ====== IPC: Window Controls ======
    ipcMain.on('window-minimize', () => mainWindow.minimize());
    ipcMain.on('window-maximize', () => {
        mainWindow.isMaximized() ? mainWindow.unmaximize() : mainWindow.maximize();
    });
    ipcMain.on('window-close', () => mainWindow.hide());

    // ====== IPC: Server ======
    ipcMain.handle('server-start', async (event, port) => {
        try {
            const result = await serverCore.start(port || 3000);
            sendToRenderer('server-status', { running: true, port: result.port });
            
            // Подписка на события сервера
            serverCore.on('log', (msg) => sendToRenderer('server-log', msg));
            serverCore.on('room-created', (data) => sendToRenderer('room-event', { type: 'created', ...data }));
            serverCore.on('user-joined', (data) => sendToRenderer('room-event', { type: 'joined', ...data }));
            serverCore.on('user-left', (data) => sendToRenderer('room-event', { type: 'left', ...data }));
            serverCore.on('stats-update', (data) => sendToRenderer('stats-update', data));
            
            return { success: true, port: result.port };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('server-stop', async () => {
        serverCore.stop();
        sendToRenderer('server-status', { running: false });
        return { success: true };
    });

    ipcMain.handle('server-get-status', async () => {
        return serverCore.getStatus();
    });

    // ====== IPC: Tunnel ======
    ipcMain.handle('tunnel-start', async (event, port) => {
        try {
            sendToRenderer('tunnel-status', { status: 'connecting' });
            const url = await tunnelManager.start(port || 3000);
            sendToRenderer('tunnel-status', { status: 'connected', url });
            return { success: true, url };
        } catch (err) {
            sendToRenderer('tunnel-status', { status: 'error', error: err.message });
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('tunnel-stop', async () => {
        tunnelManager.stop();
        sendToRenderer('tunnel-status', { status: 'disconnected' });
        return { success: true };
    });

    // ====== IPC: Plugin Install ======
    ipcMain.handle('install-plugin', async () => {
        try {
            const fs = require('fs');
            const os = require('os');
            const pluginSrc = path.join(__dirname, '..', 'plugin', 'CollabPlugin.lua');
            const pluginDst = path.join(os.homedir(), 'AppData', 'Local', 'Roblox', 'Plugins', 'CollabPlugin.lua');
            
            const pluginsDir = path.dirname(pluginDst);
            if (!fs.existsSync(pluginsDir)) {
                fs.mkdirSync(pluginsDir, { recursive: true });
            }
            
            fs.copyFileSync(pluginSrc, pluginDst);
            return { success: true, path: pluginDst };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    // ====== IPC: Misc ======
    ipcMain.handle('open-external', async (event, url) => {
        shell.openExternal(url);
    });

    ipcMain.handle('get-rooms', async () => {
        return serverCore.getRooms();
    });

    ipcMain.handle('kick-user', async (event, roomId, userId) => {
        return serverCore.kickUser(roomId, userId);
    });

    ipcMain.handle('delete-room', async (event, roomId) => {
        return serverCore.deleteRoom(roomId);
    });
});

function sendToRenderer(channel, data) {
    if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send(channel, data);
    }
}

app.on('before-quit', () => {
    serverCore?.stop();
    tunnelManager?.stop();
    app.exit(0);
});