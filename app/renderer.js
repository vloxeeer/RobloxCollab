// ===== STATE =====
let serverRunning = false;
let tunnelConnected = false;
let currentPage = 'dashboard';
let roomsRefreshInterval = null;
const activities = [];

// ===== PAGES =====
function showPage(pageId) {
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));

    const page = document.getElementById('page-' + pageId);
    const btn = document.querySelector(`.nav-btn[data-page="${pageId}"]`);

    if (page) {
        page.classList.add('active');
        // Re-trigger animations
        page.style.animation = 'none';
        page.offsetHeight;
        page.style.animation = '';
    }
    if (btn) btn.classList.add('active');

    currentPage = pageId;

    if (pageId === 'rooms') refreshRooms();
}

// ===== TOASTS =====
function showToast(message, type = 'info', duration = 4000) {
    const container = document.getElementById('toastContainer');
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    
    const icons = { success: '✅', error: '❌', info: 'ℹ️', warning: '⚠️' };
    toast.innerHTML = `<span>${icons[type] || 'ℹ️'}</span><span>${message}</span>`;
    
    container.appendChild(toast);

    setTimeout(() => {
        toast.classList.add('toast-out');
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

// ===== COPY =====
function copyText(element) {
    const text = element.textContent.trim();
    navigator.clipboard.writeText(text).then(() => {
        const original = element.textContent;
        element.textContent = '✅ Скопировано!';
        element.classList.add('copied');
        setTimeout(() => {
            element.textContent = original;
            element.classList.remove('copied');
        }, 1500);
        showToast('Скопировано в буфер обмена', 'success', 2000);
    });
}

// ===== ACTIVITY LOG =====
function addActivity(text, icon = '📌') {
    const time = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    activities.unshift({ text, icon, time });
    if (activities.length > 50) activities.pop();
    renderActivities();
}

function renderActivities() {
    const list = document.getElementById('activityList');
    if (!list) return;

    if (activities.length === 0) {
        list.innerHTML = '<div class="activity-empty">Пока нет событий. Запустите сервер!</div>';
        return;
    }

    list.innerHTML = activities.slice(0, 20).map(a => `
        <div class="activity-item">
            <span class="activity-time">${a.time}</span>
            <span>${a.icon}</span>
            <span>${a.text}</span>
        </div>
    `).join('');
}

// ===== SERVER =====
async function toggleServer() {
    const btn = document.getElementById('btnStartServer');
    const port = parseInt(document.getElementById('serverPort').value) || 3000;

    if (serverRunning) {
        btn.classList.add('loading');
        btn.innerHTML = '<span class="btn-icon">⏳</span> Останавливаю...';
        const result = await api.stopServer();
        btn.classList.remove('loading');
        if (result.success) {
            serverRunning = false;
            updateServerUI();
            showToast('Сервер остановлен', 'info');
            addActivity('Сервер остановлен', '⛔');
        }
    } else {
        btn.classList.add('loading');
        btn.innerHTML = '<span class="btn-icon">⏳</span> Запускаю...';
        const result = await api.startServer(port);
        btn.classList.remove('loading');
        if (result.success) {
            serverRunning = true;
            updateServerUI();
            showToast(`Сервер запущен на порту ${result.port}`, 'success');
            addActivity(`Сервер запущен (порт ${result.port})`, '✅');
        } else {
            showToast(`Ошибка: ${result.error}`, 'error');
            addActivity(`Ошибка запуска: ${result.error}`, '❌');
            updateServerUI();
        }
    }
}

async function quickStartServer() {
    if (!serverRunning) {
        await toggleServer();
    } else {
        showToast('Сервер уже запущен!', 'info');
    }
}

function updateServerUI() {
    const btn = document.getElementById('btnStartServer');
    const badge = document.getElementById('serverBadge');
    const infoCard = document.getElementById('serverInfoCard');
    const sidebarInd = document.getElementById('sidebarIndicator');
    const dashStatus = document.getElementById('dash-server-status');
    const port = document.getElementById('serverPort').value || 3000;

    if (serverRunning) {
        btn.innerHTML = '<span class="btn-icon">⏹️</span> Остановить сервер';
        btn.className = 'btn btn-danger btn-lg';
        badge.innerHTML = '<div class="indicator-dot online"></div><span>Работает</span>';
        infoCard.style.display = 'block';
        document.getElementById('localUrl').textContent = `http://localhost:${port}`;
        sidebarInd.innerHTML = '<div class="indicator-dot online"></div><span>Сервер вкл.</span>';
        if (dashStatus) dashStatus.textContent = 'Работает';
    } else {
        btn.innerHTML = '<span class="btn-icon">▶️</span> Запустить сервер';
        btn.className = 'btn btn-success btn-lg';
        badge.innerHTML = '<div class="indicator-dot offline"></div><span>Остановлен</span>';
        infoCard.style.display = 'none';
        sidebarInd.innerHTML = '<div class="indicator-dot offline"></div><span>Сервер выкл.</span>';
        if (dashStatus) dashStatus.textContent = 'Выключен';
    }
}

// ===== TUNNEL =====
async function toggleTunnel() {
    const btn = document.getElementById('btnStartTunnel');
    const port = parseInt(document.getElementById('serverPort')?.value) || 3000;

    if (tunnelConnected) {
        const result = await api.stopTunnel();
        if (result.success) {
            tunnelConnected = false;
            updateTunnelUI();
            showToast('Туннель закрыт', 'info');
            addActivity('Туннель закрыт', '🌐');
        }
    } else {
        if (!serverRunning) {
            showToast('Сначала запустите сервер!', 'warning');
            return;
        }

        btn.classList.add('loading');
        btn.innerHTML = '<span class="btn-icon">⏳</span> Подключаю...';

        const result = await api.startTunnel(port);
        btn.classList.remove('loading');

        if (result.success) {
            tunnelConnected = true;
            document.getElementById('tunnelUrl').textContent = result.url;
            updateTunnelUI();
            showToast('Туннель создан! Отправьте ссылку другу', 'success', 6000);
            addActivity(`Туннель открыт: ${result.url}`, '🌐');
        } else {
            showToast(`Ошибка: ${result.error}`, 'error');
            updateTunnelUI();
        }
    }
}

function updateTunnelUI() {
    const btn = document.getElementById('btnStartTunnel');
    const badge = document.getElementById('tunnelBadge');
    const info = document.getElementById('tunnelInfo');

    if (tunnelConnected) {
        btn.innerHTML = '<span class="btn-icon">🔌</span> Закрыть туннель';
        btn.className = 'btn btn-danger btn-lg';
        badge.innerHTML = '<div class="indicator-dot online"></div><span>Подключён</span>';
        info.style.display = 'block';
    } else {
        btn.innerHTML = '<span class="btn-icon">🌐</span> Открыть туннель';
        btn.className = 'btn btn-primary btn-lg';
        badge.innerHTML = '<div class="indicator-dot offline"></div><span>Отключён</span>';
        info.style.display = 'none';
    }
}

// ===== ROOMS =====
async function refreshRooms() {
    try {
        const rooms = await api.getRooms();
        renderRooms(rooms);
    } catch (e) {
        // Server not running
    }
}

function renderRooms(rooms) {
    const container = document.getElementById('roomsList');
    const countEl = document.getElementById('dash-rooms-count');
    
    if (countEl) countEl.textContent = rooms.length;

    if (!rooms || rooms.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-icon">🚪</div>
                <p>Нет активных комнат</p>
                <p class="empty-hint">Комнаты создаются через плагин в Roblox Studio</p>
            </div>`;
        return;
    }

    container.innerHTML = rooms.map((room, i) => `
        <div class="room-card" style="animation-delay: ${i * 0.05}s">
            <div class="room-info">
                <div class="room-name">${room.hasPassword ? '🔒' : '🚪'} ${escapeHtml(room.name)}</div>
                <div class="room-id">ID: ${room.roomId}</div>
                <div class="room-meta">
                    <span>👥 ${room.userCount} онлайн</span>
                    <span>📊 ${room.opsCount || 0} операций</span>
                    <span>🕐 ${formatTime(room.createdAt)}</span>
                </div>
                ${room.users ? `<div class="room-meta">${room.users.map(u => `<span>• ${escapeHtml(u.username)}</span>`).join('')}</div>` : ''}
            </div>
            <div class="room-actions">
                <button class="btn btn-sm btn-danger" onclick="deleteRoom('${room.roomId}')">🗑️</button>
            </div>
        </div>
    `).join('');
}

async function deleteRoom(roomId) {
    const result = await api.deleteRoom(roomId);
    if (result.success) {
        showToast(`Комната ${roomId} удалена`, 'info');
        addActivity(`Комната ${roomId} удалена`, '🗑️');
        refreshRooms();
    }
}

// ===== PLUGIN =====
async function installPlugin() {
    const result = await api.installPlugin();
    const resultDiv = document.getElementById('pluginInstallResult');
    resultDiv.style.display = 'block';

    if (result.success) {
        resultDiv.className = 'install-result success';
        resultDiv.innerHTML = `✅ Плагин установлен!<br><small>${result.path}</small><br><strong>Перезапустите Roblox Studio</strong>`;
        showToast('Плагин установлен! Перезапустите Studio', 'success', 5000);
        addActivity('Плагин установлен', '🧩');
    } else {
        resultDiv.className = 'install-result error';
        resultDiv.innerHTML = `❌ Ошибка: ${result.error}`;
        showToast('Ошибка установки плагина', 'error');
    }
}

async function quickInstallPlugin() {
    await installPlugin();
    showPage('plugin');
}

// ===== LOGS =====
function addLog(message, type = 'info') {
    const container = document.getElementById('logsContainer');
    if (!container) return;

    const entry = document.createElement('div');
    entry.className = `log-entry log-${type}`;
    entry.textContent = message;
    container.appendChild(entry);

    // Auto-scroll
    container.scrollTop = container.scrollHeight;

    // Limit
    while (container.children.length > 500) {
        container.removeChild(container.firstChild);
    }
}

function clearLogs() {
    const container = document.getElementById('logsContainer');
    container.innerHTML = '<div class="log-entry log-info">Логи очищены</div>';
}

// ===== HELPERS =====
function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function formatTime(timestamp) {
    if (!timestamp) return '';
    const d = new Date(timestamp);
    return d.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
}

function formatUptime(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) return `${h}ч ${m}м`;
    if (m > 0) return `${m}м ${s}с`;
    return `${s}с`;
}

// ===== EVENT LISTENERS =====
api.on('server-log', (msg) => {
    addLog(msg, msg.includes('✅') || msg.includes('📸') ? 'success' :
                msg.includes('❌') || msg.includes('⛔') ? 'error' :
                msg.includes('⚠') ? 'warning' : 'info');
});

api.on('server-status', (data) => {
    serverRunning = data.running;
    updateServerUI();
});

api.on('tunnel-status', (data) => {
    if (data.status === 'connected') {
        tunnelConnected = true;
        if (data.url) document.getElementById('tunnelUrl').textContent = data.url;
    } else if (data.status === 'disconnected' || data.status === 'error') {
        tunnelConnected = false;
    }
    updateTunnelUI();
});

api.on('room-event', (data) => {
    if (data.type === 'created') {
        addActivity(`Создана комната ${data.roomId} (${data.username})`, '🏠');
        showToast(`Новая комната: ${data.roomName}`, 'info');
    } else if (data.type === 'joined') {
        addActivity(`${data.username} → ${data.roomId}`, '👤');
    } else if (data.type === 'left') {
        addActivity(`${data.username} покинул ${data.roomId}`, '👋');
    }
    refreshRooms();
});

api.on('stats-update', (data) => {
    const rc = document.getElementById('dash-rooms-count');
    const uc = document.getElementById('dash-users-count');
    const oc = document.getElementById('dash-ops-count');
    const ut = document.getElementById('serverUptime');

    if (rc) rc.textContent = data.roomCount || 0;
    if (uc) uc.textContent = data.totalUsers || 0;
    if (oc) oc.textContent = data.totalOps || 0;
    if (ut) ut.textContent = formatUptime(data.uptime || 0);
});

// ===== INIT =====
(async () => {
    const status = await api.getServerStatus();
    serverRunning = status.running;
    updateServerUI();
    updateTunnelUI();
    renderActivities();

    // Refresh rooms periodically
    setInterval(() => {
        if (currentPage === 'rooms' || currentPage === 'dashboard') {
            refreshRooms();
        }
    }, 5000);
})();