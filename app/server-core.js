const express = require('express');
const { v4: uuidv4 } = require('uuid');
const WebSocket = require('ws');
const http = require('http');
const compression = require('compression');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const EventEmitter = require('events');

class ServerCore extends EventEmitter {
    constructor() {
        super();
        this.server = null;
        this.wss = null;
        this.port = 3000;
        this.running = false;

        this.rooms = new Map();
        this.roomUsers = new Map();
        this.operationQueues = new Map();
        this.userCursors = new Map();
        this.snapshots = new Map();
        this.chatMessages = new Map();
        this.objectLocks = new Map();
        this.wsClients = new Map();
        this.terrainData = new Map();

        this.totalConnections = 0;
        this.totalOps = 0;
    }

    start(port) {
        return new Promise((resolve, reject) => {
            if (this.running) {
                reject(new Error('Server already running'));
                return;
            }

            this.port = port || 3000;
            const app = express();
            this.server = http.createServer(app);
            this.wss = new WebSocket.Server({ server: this.server });

            app.use(compression());
            app.use(cors());
            app.use(express.json({ limit: '100mb' }));

            this._setupWebSocket();
            this._setupRoutes(app);
            this._startCleanup();

            this.server.listen(this.port, '0.0.0.0', () => {
                this.running = true;
                this.log(`✅ Сервер запущен на порту ${this.port}`);
                resolve({ port: this.port });
            });

            this.server.on('error', (err) => {
                if (err.code === 'EADDRINUSE') {
                    this.log(`❌ Порт ${this.port} занят`);
                    reject(new Error(`Порт ${this.port} уже используется`));
                } else {
                    reject(err);
                }
            });

            // Stats interval
            this._statsInterval = setInterval(() => {
                this.emit('stats-update', this.getStatus());
            }, 2000);
        });
    }

    stop() {
        if (this.server) {
            this.server.close();
            this.server = null;
        }
        if (this.wss) {
            this.wss.close();
            this.wss = null;
        }
        if (this._cleanupInterval) clearInterval(this._cleanupInterval);
        if (this._statsInterval) clearInterval(this._statsInterval);
        this.running = false;
        this.log('⛔ Сервер остановлен');
    }

    getStatus() {
        let totalUsers = 0;
        let roomList = [];
        for (const [id, room] of this.rooms.entries()) {
            const users = this.roomUsers.get(id) || [];
            const active = users.filter(u => (Date.now() - u.lastSeen) < 60000);
            totalUsers += active.length;
            roomList.push({
                roomId: id,
                name: room.name,
                hasPassword: !!room.password,
                userCount: active.length,
                users: active.map(u => ({ username: u.username, userId: u.userId })),
                createdAt: room.createdAt,
                opsCount: (this.operationQueues.get(id) || []).length
            });
        }
        return {
            running: this.running,
            port: this.port,
            rooms: roomList,
            roomCount: this.rooms.size,
            totalUsers,
            totalConnections: this.totalConnections,
            totalOps: this.totalOps,
            uptime: this.server ? process.uptime() : 0
        };
    }

    getRooms() {
        return this.getStatus().rooms;
    }

    kickUser(roomId, userId) {
        const users = this.roomUsers.get(roomId);
        if (users) {
            const idx = users.findIndex(u => u.userId === userId);
            if (idx !== -1) {
                const username = users[idx].username;
                users.splice(idx, 1);
                this._broadcastToRoom(roomId, { type: 'user_kicked', username }, userId);
                this.log(`👢 ${username} кикнут из ${roomId}`);
                return { success: true };
            }
        }
        return { success: false };
    }

    deleteRoom(roomId) {
        this.rooms.delete(roomId);
        this.roomUsers.delete(roomId);
        this.operationQueues.delete(roomId);
        this.snapshots.delete(roomId);
        this.chatMessages.delete(roomId);
        this.objectLocks.delete(roomId);
        this.terrainData.delete(roomId);
        this.wsClients.delete(roomId);
        this.log(`🗑️ Комната ${roomId} удалена`);
        return { success: true };
    }

    log(message) {
        const time = new Date().toLocaleTimeString('ru-RU');
        const logMsg = `[${time}] ${message}`;
        this.emit('log', logMsg);
    }

    // ===== Internal =====

    _getOperations(roomId) {
        if (!this.operationQueues.has(roomId)) this.operationQueues.set(roomId, []);
        return this.operationQueues.get(roomId);
    }

    _trimOperations(roomId) {
        const ops = this._getOperations(roomId);
        if (ops.length > 20000) {
            const trim = ops.length - 10000;
            ops.splice(0, trim);
            for (const [key, cursor] of this.userCursors.entries()) {
                if (key.startsWith(roomId + ':')) {
                    this.userCursors.set(key, Math.max(0, cursor - trim));
                }
            }
        }
    }

    _broadcastToRoom(roomId, message, excludeUserId) {
        const clients = this.wsClients.get(roomId) || [];
        const data = JSON.stringify(message);
        for (const client of clients) {
            if (client.userId !== excludeUserId && client.ws.readyState === WebSocket.OPEN) {
                try { client.ws.send(data); } catch (e) {}
            }
        }
    }

    _startCleanup() {
        this._cleanupInterval = setInterval(() => {
            const now = Date.now();
            for (const [roomId, users] of this.roomUsers.entries()) {
                const disconnected = users.filter(u => (now - u.lastSeen) >= 60000);
                const active = users.filter(u => (now - u.lastSeen) < 60000);
                this.roomUsers.set(roomId, active);

                for (const user of disconnected) {
                    const locks = this.objectLocks.get(roomId) || {};
                    for (const [id, lock] of Object.entries(locks)) {
                        if (lock.userId === user.userId) delete locks[id];
                    }
                }

                if (active.length === 0 && (now - this.rooms.get(roomId)?.createdAt > 600000)) {
                    this.deleteRoom(roomId);
                }
            }
        }, 15000);
    }

    _setupWebSocket() {
        this.wss.on('connection', (ws) => {
            let info = { roomId: null, userId: null, username: null };
            this.totalConnections++;

            ws.on('message', (raw) => {
                try {
                    const msg = JSON.parse(raw);
                    if (msg.type === 'register') {
                        info = { roomId: msg.roomId, userId: msg.userId, username: msg.username };
                        if (!this.wsClients.has(msg.roomId)) this.wsClients.set(msg.roomId, []);
                        this.wsClients.get(msg.roomId).push({ ws, ...info });
                        ws.send(JSON.stringify({ type: 'registered', success: true }));
                        this._broadcastToRoom(msg.roomId, { type: 'user_joined', username: msg.username }, msg.userId);
                    } else if (msg.type === 'operations') {
                        const ops = this._getOperations(info.roomId);
                        for (const op of msg.operations) {
                            ops.push({ id: uuidv4(), ...op, userId: info.userId, username: info.username, timestamp: Date.now() });
                            this.totalOps++;
                        }
                        this._trimOperations(info.roomId);
                        this._broadcastToRoom(info.roomId, {
                            type: 'operations',
                            operations: msg.operations.map(op => ({ ...op, userId: info.userId, username: info.username }))
                        }, info.userId);
                    } else if (msg.type === 'chat') {
                        const chat = this.chatMessages.get(info.roomId) || [];
                        chat.push({ username: info.username, message: msg.message?.substring(0, 500), timestamp: Date.now() });
                        if (chat.length > 500) chat.splice(0, chat.length - 500);
                        this.chatMessages.set(info.roomId, chat);
                        this._broadcastToRoom(info.roomId, { type: 'chat', username: info.username, message: msg.message, timestamp: Date.now() }, info.userId);
                    } else if (msg.type === 'ping') {
                        ws.send(JSON.stringify({ type: 'pong' }));
                        const users = this.roomUsers.get(info.roomId);
                        if (users) { const u = users.find(x => x.userId === info.userId); if (u) u.lastSeen = Date.now(); }
                    }
                } catch (e) {}
            });

            ws.on('close', () => {
                if (info.roomId) {
                    const clients = this.wsClients.get(info.roomId) || [];
                    this.wsClients.set(info.roomId, clients.filter(c => c.ws !== ws));
                    const locks = this.objectLocks.get(info.roomId) || {};
                    for (const [id, lock] of Object.entries(locks)) {
                        if (lock.userId === info.userId) delete locks[id];
                    }
                    this._broadcastToRoom(info.roomId, { type: 'user_left', username: info.username }, info.userId);
                    this.emit('user-left', { roomId: info.roomId, username: info.username });
                }
            });
        });
    }

    _setupRoutes(app) {
        const self = this;

        app.get('/health', (req, res) => res.json({ status: 'ok', ...self.getStatus() }));

        app.get('/plugin-source', (req, res) => {
            const p = path.join(__dirname, '..', 'plugin', 'CollabPlugin.lua');
            if (fs.existsSync(p)) res.type('text/plain').send(fs.readFileSync(p, 'utf8'));
            else res.status(404).send('Not found');
        });

        app.post('/api/rooms/create', (req, res) => {
            const { roomName, password, username } = req.body;
            if (!roomName || !username) return res.status(400).json({ error: 'missing fields' });
            const roomId = uuidv4().substring(0, 8).toUpperCase();
            const userId = uuidv4();
            self.rooms.set(roomId, { name: roomName, password: password || null, createdAt: Date.now(), hostUser: userId });
            self.roomUsers.set(roomId, [{ userId, username, lastSeen: Date.now() }]);
            self.operationQueues.set(roomId, []);
            self.chatMessages.set(roomId, []);
            self.objectLocks.set(roomId, {});
            self.log(`🏠 Комната ${roomId} создана (${username})`);
            self.emit('room-created', { roomId, roomName, username });
            res.json({ success: true, roomId, userId, isHost: true });
        });

        app.post('/api/rooms/join', (req, res) => {
            const { roomId, password, username } = req.body;
            if (!roomId || !username) return res.status(400).json({ error: 'missing fields' });
            const id = roomId.toUpperCase();
            const room = self.rooms.get(id);
            if (!room) return res.status(404).json({ error: 'Комната не найдена' });
            if (room.password && room.password !== password) return res.status(403).json({ error: 'Неверный пароль' });
            const userId = uuidv4();
            const users = self.roomUsers.get(id) || [];
            const existing = users.find(u => u.username === username);
            if (existing) { existing.lastSeen = Date.now(); existing.userId = userId; }
            else users.push({ userId, username, lastSeen: Date.now() });
            self.roomUsers.set(id, users);
            const ops = self._getOperations(id);
            self.userCursors.set(`${id}:${userId}`, ops.length);
            const chat = self.chatMessages.get(id) || [];
            chat.push({ username: 'SYSTEM', message: `${username} присоединился`, timestamp: Date.now() });
            self.chatMessages.set(id, chat);
            self._broadcastToRoom(id, { type: 'user_joined', username }, userId);
            self.log(`👤 ${username} → комната ${id}`);
            self.emit('user-joined', { roomId: id, username });
            res.json({ success: true, roomId: id, userId, roomName: room.name, isHost: false });
        });

        app.post('/api/rooms/heartbeat', (req, res) => {
            const { roomId, userId } = req.body;
            const users = self.roomUsers.get(roomId);
            if (!users) return res.status(404).json({ error: 'Room not found' });
            const user = users.find(u => u.userId === userId);
            if (user) user.lastSeen = Date.now();
            res.json({
                success: true,
                users: users.map(u => ({ username: u.username, online: (Date.now() - u.lastSeen) < 60000 })),
                userCount: users.filter(u => (Date.now() - u.lastSeen) < 60000).length
            });
        });

        app.post('/api/operations/push', (req, res) => {
            const { roomId, userId, username, operations } = req.body;
            if (!roomId || !operations) return res.status(400).json({ error: 'invalid' });
            const ops = self._getOperations(roomId);
            for (const op of operations) {
                ops.push({ id: uuidv4(), type: op.type, data: op.data, userId, username, timestamp: Date.now() });
                self.totalOps++;
            }
            self._trimOperations(roomId);
            self._broadcastToRoom(roomId, { type: 'operations', operations: operations.map(op => ({ ...op, userId, username })) }, userId);
            const users = self.roomUsers.get(roomId);
            if (users) { const u = users.find(x => x.userId === userId); if (u) u.lastSeen = Date.now(); }
            res.json({ success: true });
        });

        app.post('/api/operations/pull', (req, res) => {
            const { roomId, userId } = req.body;
            if (!roomId || !userId) return res.status(400).json({ error: 'invalid' });
            const ops = self._getOperations(roomId);
            const key = `${roomId}:${userId}`;
            const cursor = self.userCursors.get(key) || 0;
            const newOps = ops.slice(cursor).filter(op => op.userId !== userId);
            self.userCursors.set(key, ops.length);
            const chat = self.chatMessages.get(roomId) || [];
            res.json({ success: true, operations: newOps, chatMessages: chat.slice(-30) });
        });

        app.post('/api/snapshot/upload', (req, res) => {
            const { roomId, userId, data } = req.body;
            if (!roomId || !data) return res.status(400).json({ error: 'invalid' });
            self.snapshots.set(roomId, { data, timestamp: Date.now(), userId });
            self.log(`📸 Снапшот загружен (${roomId})`);
            res.json({ success: true });
        });

        app.post('/api/snapshot/download', (req, res) => {
            const { roomId } = req.body;
            const snapshot = self.snapshots.get(roomId);
            if (!snapshot) return res.json({ success: true, hasSnapshot: false });
            res.json({ success: true, hasSnapshot: true, data: snapshot.data, timestamp: snapshot.timestamp });
        });

        app.post('/api/chat/send', (req, res) => {
            const { roomId, username, message } = req.body;
            if (!roomId || !username || !message) return res.status(400).json({ error: 'invalid' });
            const chat = self.chatMessages.get(roomId) || [];
            chat.push({ username, message: message.substring(0, 500), timestamp: Date.now() });
            if (chat.length > 500) chat.splice(0, chat.length - 500);
            self.chatMessages.set(roomId, chat);
            self._broadcastToRoom(roomId, { type: 'chat', username, message, timestamp: Date.now() }, null);
            res.json({ success: true });
        });

        app.post('/api/locks/acquire', (req, res) => {
            const { roomId, userId, username, instanceId } = req.body;
            const locks = self.objectLocks.get(roomId) || {};
            self.objectLocks.set(roomId, locks);
            if (locks[instanceId] && locks[instanceId].userId !== userId) return res.json({ success: false, lockedBy: locks[instanceId].username });
            locks[instanceId] = { userId, username, lockedAt: Date.now() };
            res.json({ success: true });
        });

        app.post('/api/locks/release', (req, res) => {
            const { roomId, userId, instanceId } = req.body;
            const locks = self.objectLocks.get(roomId) || {};
            if (instanceId) { if (locks[instanceId]?.userId === userId) delete locks[instanceId]; }
            else { for (const [id, l] of Object.entries(locks)) { if (l.userId === userId) delete locks[id]; } }
            res.json({ success: true });
        });

        app.post('/api/rooms/leave', (req, res) => {
            const { roomId, userId, username } = req.body;
            const users = self.roomUsers.get(roomId);
            if (users) { const i = users.findIndex(u => u.userId === userId); if (i !== -1) users.splice(i, 1); }
            const locks = self.objectLocks.get(roomId) || {};
            for (const [id, l] of Object.entries(locks)) { if (l.userId === userId) delete locks[id]; }
            self._broadcastToRoom(roomId, { type: 'user_left', username }, userId);
            self.log(`👋 ${username} покинул ${roomId}`);
            self.emit('user-left', { roomId, username });
            res.json({ success: true });
        });

        app.post('/api/terrain/upload', (req, res) => {
            self.terrainData.set(req.body.roomId, req.body.data);
            self.log(`🏔️ Terrain загружен (${req.body.roomId})`);
            res.json({ success: true });
        });

        app.post('/api/terrain/download', (req, res) => {
            const d = self.terrainData.get(req.body.roomId);
            res.json({ success: true, hasData: !!d, data: d || null });
        });

        app.get('/api/rooms/list', (req, res) => {
            res.json({ rooms: self.getRooms() });
        });
    }
}

module.exports = ServerCore;