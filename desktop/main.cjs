const { app, BrowserWindow, ipcMain, Menu, Tray, nativeImage, nativeTheme, screen, globalShortcut, net } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { fileURLToPath } = require('node:url');
const { LiveAPI, LiveController, cleanPreferences, score, status, heading } = require('./core.cjs');
const { clampBounds, snapBounds } = require('./geometry.cjs');
const demo = process.argv.includes('--demo');
const diagnostics = process.argv.includes('--self-test');
let win, tray, controller, settingsPath, quitting = false, shortcut = '', hoverTimer, saveTimer, drag, changingFrame = false;
let config = {};
const root = path.join(__dirname, '..');
const pagePath = path.join(root, 'web-dist', 'index.html');
const boundsOK = b => b && ['x','y','width','height'].every(k => Number.isFinite(b[k])) && b.width >= 360 && b.width <= 2000 && b.height >= 32 && b.height <= 1600;
const areas = () => screen.getAllDisplays().map(d => d.workArea);
const clamp = b => clampBounds(b, areas());
function persist() {
  if (demo || diagnostics || !settingsPath) return;
  config.preferences = controller.state.preferences;
  const temporary = `${settingsPath}.tmp`;
  try { fs.writeFileSync(temporary, JSON.stringify(config, null, 2), { mode: 0o600 }); fs.renameSync(temporary, settingsPath); }
  catch (e) { console.error('偏好保存失败', e.message); }
}
function saveBounds() {
  if (!win || changingFrame) return;
  config[controller.state.compact ? 'compactBounds' : 'expandedBounds'] = win.getBounds();
  clearTimeout(saveTimer); saveTimer = setTimeout(persist, 180);
}
function applyAppearance() {
  nativeTheme.themeSource = controller.state.preferences.theme;
  win.setAlwaysOnTop(controller.state.preferences.pinned, 'floating');
  win.setHasShadow(!controller.state.compact || controller.state.hovered || controller.state.menuOpen);
}
function sendState() {
  if (!win || win.isDestroyed()) return;
  win.webContents.send('yuguang:state', { ...controller.state, systemDark: nativeTheme.shouldUseDarkColors, platform: process.platform, version: app.getVersion() });
}
function show() { if (!win) return; win.show(); win.focus(); }
function toggleVisibility() { if (win.isVisible()) win.hide(); else show(); }
function setMode(compact) {
  if (controller.state.compact === compact) return;
  config[controller.state.compact ? 'compactBounds' : 'expandedBounds'] = win.getBounds();
  controller.state.compact = compact;
  const current = win.getBounds();
  const saved = config[compact ? 'compactBounds' : 'expandedBounds'];
  const width = saved?.width || (compact ? 680 : 420);
  const height = compact ? controller.state.preferences.rows * 32 : Math.max(460, saved?.height || 640);
  changingFrame = true;
  win.setMinimumSize(360, compact ? height : 460);
  win.setMaximumSize(compact ? 1400 : 760, compact ? height : 1200);
  win.setBounds(clamp({ x: current.x, y: current.y, width, height }));
  changingFrame = false;
  applyAppearance(); saveBounds(); controller.publish();
}
function registerShortcut(next) {
  if (shortcut === next) return true;
  try {
    if (!globalShortcut.register(next, toggleVisibility)) return false;
    if (shortcut) globalShortcut.unregister(shortcut);
    shortcut = next; return true;
  } catch { return false; }
}
function openPage(page) { setMode(false); controller.state.page = page; controller.publish(); show(); }
function rebuildTray() {
  const s = controller.state;
  tray.setToolTip(heading(s.selectedMatch));
  if (process.platform === 'darwin') tray.setTitle(s.preferences.menuScore && s.selectedMatch ? ` ${s.selectedMatch.awayTeamName} ${score(s.selectedMatch)} ${s.selectedMatch.homeTeamName}` : '', { fontType: 'monospacedDigit' });
}
function trayMenu() {
  const s = controller.state;
  return Menu.buildFromTemplate([
    { label: heading(s.selectedMatch), enabled: false }, { type: 'separator' },
    { label: '显示 / 隐藏直播', click: toggleVisibility },
    { label: '选择比赛', click: () => openPage('matches') },
    { label: '精简 / 展开', click: () => { setMode(!s.compact); show(); } },
    { label: '偏好设置…', click: () => openPage('settings') }, { type: 'separator' },
    { label: '退出余光', click: () => { quitting = true; app.quit(); } }
  ]);
}
function quickMenu() {
  controller.state.menuOpen = true; applyAppearance(); controller.publish();
  const s = controller.state;
  const menu = Menu.buildFromTemplate([
    { label: s.days.find(d => d.day === s.selectedDay)?.dayBlock || '比赛', enabled: false },
    ...controller.switchableMatches().map(m => ({ label: heading(m), type: 'checkbox', checked: m.matchId === s.selectedMatch?.matchId, click: () => controller.select(m) })),
    ...(controller.switchableMatches().length ? [] : [{ label: s.loadingSchedule ? '正在获取赛程…' : '这一天暂无比赛', enabled: false }]),
    { type: 'separator' },
    { label: '比赛日期', submenu: s.days.map(d => ({ label: d.dayBlock || d.day, type: 'radio', checked: s.selectedDay === d.day, click: () => { s.selectedDay = d.day; controller.publish(); setImmediate(quickMenu); } })) },
    { label: '刷新赛程', click: () => void controller.refreshSchedule() }
  ]);
  menu.popup({ window: win, callback: () => { s.menuOpen = false; applyAppearance(); controller.publish(); } });
}
function updatePreferences(patch) {
  if (!patch || typeof patch !== 'object') throw new Error('设置参数无效');
  const allowed = ['theme','pinned','rows','simple','scoreOnly','menuScore','shortcut'];
  const filtered = Object.fromEntries(Object.entries(patch).filter(([k]) => allowed.includes(k)));
  const previous = controller.state.preferences;
  const next = cleanPreferences({ ...previous, ...filtered });
  if (next.shortcut !== previous.shortcut && !registerShortcut(next.shortcut)) {
    controller.state.shortcutError = '快捷键已被占用，原快捷键仍有效。'; controller.publish(); return;
  }
  controller.state.shortcutError = '';
  controller.setPreferences(next);
  if (previous.simple !== next.simple) setMode(next.simple);
  if (controller.state.compact && next.rows !== previous.rows) {
    const b = win.getBounds(), height = next.rows * 32;
    changingFrame = true; win.setMinimumSize(360, height); win.setMaximumSize(1400, height);
    win.setBounds(clamp({ ...b, height })); changingFrame = false; saveBounds();
  }
  applyAppearance(); controller.publish();
}
function validSender(event) {
  if (event.sender !== win?.webContents || event.senderFrame !== win.webContents.mainFrame) return false;
  try { return fileURLToPath(event.senderFrame.url).split('?')[0] === pagePath; } catch { return false; }
}
ipcMain.handle('yuguang:get-state', event => {
  if (!validSender(event)) throw new Error('无效的窗口请求');
  return { ...controller.state, systemDark: nativeTheme.shouldUseDarkColors, platform: process.platform, version: app.getVersion() };
});
ipcMain.handle('yuguang:command', (event, command, value) => {
  if (!validSender(event)) throw new Error('无效的窗口请求');
  const s = controller.state;
  switch (command) {
    case 'hide': win.hide(); break;
    case 'mode': setMode(!s.compact); break;
    case 'page': if (['matches','live','settings'].includes(value)) openPage(value); break;
    case 'select': { const m = s.days.flatMap(d => d.matchList).find(m => m.matchId === value); if (m) controller.select(m); break; }
    case 'date': if (s.days.some(d => d.day === value)) { s.selectedDay = value; controller.publish(); } break;
    case 'filter': if (typeof value === 'string' && value.length < 40) { s.teamFilter = value; controller.publish(); } break;
    case 'favorite': if (typeof value === 'string' && s.days.some(d => d.matchList.some(m => m.homeTeamName === value || m.awayTeamName === value))) {
      controller.setPreferences({ favorites: s.preferences.favorites.includes(value) ? s.preferences.favorites.filter(t => t !== value) : [...s.preferences.favorites, value] });
    } break;
    case 'preferences': updatePreferences(value); break;
    case 'refresh': void controller.refreshSchedule(); break;
    case 'retry': controller.retry(); break;
    case 'following': controller.toggleFollowing(); break;
    case 'quick-menu': quickMenu(); break;
    case 'drag-start': if (value && Number.isFinite(value.x) && Number.isFinite(value.y)) drag = { x: value.x, y: value.y, bounds: win.getBounds() }; break;
    case 'drag-move': if (drag && value && Number.isFinite(value.x) && Number.isFinite(value.y)) win.setPosition(Math.round(drag.bounds.x + value.x - drag.x), Math.round(drag.bounds.y + value.y - drag.y)); break;
    case 'drag-end': if (drag) { drag = null; win.setBounds(clamp(snapBounds(win.getBounds(), screen.getDisplayMatching(win.getBounds()).workArea))); saveBounds(); } break;
    case 'resize-start': if (value && Number.isFinite(value.x) && Number.isFinite(value.y)) drag = { ...value, resize: true, bounds: win.getBounds() }; break;
    case 'resize-move': if (drag?.resize && value && Number.isFinite(value.x) && Number.isFinite(value.y)) {
      win.setSize(Math.max(360, Math.min(s.compact ? 1400 : 760, Math.round(drag.bounds.width + value.x - drag.x))), s.compact ? s.preferences.rows * 32 : Math.max(460, Math.min(1200, Math.round(drag.bounds.height + value.y - drag.y))));
    } break;
    default: throw new Error('未知操作');
  }
});
app.setName('余光');
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', show);
  app.whenReady().then(async () => {
    settingsPath = path.join(app.getPath('userData'), 'preferences.json');
    try { config = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch { config = {}; }
    if (!config.preferences && process.platform === 'darwin' && !demo) {
      try {
        const plist = execFileSync('/usr/bin/defaults', ['export','app.yuguang.live','-'], { stdio: ['ignore','pipe','ignore'] });
        const old = JSON.parse(execFileSync('/usr/bin/plutil', ['-convert','json','-o','-','-'], { input: plist }));
        config.preferences = cleanPreferences({ theme: old.theme, pinned: old.pinned, rows: old.compactRows, simple: old.simpleModeEnabled, scoreOnly: old.scoreOnly, menuScore: old.menuScore, favorites: old.favoriteTeams, lastMatch: old.lastMatch });
      } catch { /* No native preferences to migrate. */ }
    }
    controller = new LiveController(new LiveAPI((...args) => net.fetch(...args)), config.preferences, () => persist());
    if (demo) controller.loadDemo();
    if (diagnostics) { controller.state.preferences = cleanPreferences(); controller.state.compact = false; }
    const s = controller.state;
    const initial = config[s.compact ? 'compactBounds' : 'expandedBounds'];
    const area = screen.getPrimaryDisplay().workArea;
    const base = boundsOK(initial) ? initial : { x: area.x + area.width - 448, y: area.y + 64, width: s.compact ? 680 : 420, height: 640 };
    const bounds = clamp({ ...base, height: s.compact ? s.preferences.rows * 32 : Math.max(460, base.height) });
    win = new BrowserWindow({ ...bounds, title: '余光', frame: false, transparent: true, backgroundColor: '#00000000', hasShadow: true, show: false, resizable: true, minWidth: 360, minHeight: s.compact ? bounds.height : 460, maxWidth: s.compact ? 1400 : 760, maxHeight: s.compact ? bounds.height : 1200, skipTaskbar: true, fullscreenable: false, maximizable: false, icon: path.join(__dirname, 'assets', 'icon.png'), webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: false, webSecurity: true } });
    if (process.platform === 'darwin') win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    win.on('close', event => { if (!quitting) { event.preventDefault(); win.hide(); } });
    win.on('move', saveBounds); win.on('resize', saveBounds);
    win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    win.webContents.on('will-navigate', event => event.preventDefault());
    win.webContents.session.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
    const trayImage = nativeImage.createFromPath(path.join(__dirname, 'assets', process.platform === 'darwin' ? 'trayTemplate.png' : 'icon.png')).resize({ width: process.platform === 'darwin' ? 22 : 24, height: process.platform === 'darwin' ? 22 : 24 });
    if (process.platform === 'darwin') { trayImage.setTemplateImage(true); app.dock.hide(); }
    tray = new Tray(trayImage);
    tray.on('click', () => tray.popUpContextMenu(trayMenu()));
    tray.on('right-click', () => tray.popUpContextMenu(trayMenu()));
    if (process.platform === 'win32') tray.on('double-click', show);
    Menu.setApplicationMenu(Menu.buildFromTemplate([{ label: '余光', submenu: [{ label: '偏好设置…', accelerator: 'CommandOrControl+,', click: () => openPage('settings') }, { label: '退出余光', accelerator: 'CommandOrControl+Q', click: () => { quitting = true; app.quit(); } }] }, { label: '编辑', submenu: [{ role: 'undo' }, { role: 'redo' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] }]));
    controller.on('change', () => { rebuildTray(); sendState(); });
    if (!registerShortcut(s.preferences.shortcut)) s.shortcutError = '全局快捷键注册失败，请在设置中选择其他组合。';
    nativeTheme.on('updated', sendState);
    screen.on('display-removed', () => win.setBounds(clamp(win.getBounds())));
    screen.on('display-metrics-changed', () => win.setBounds(clamp(win.getBounds())));
    hoverTimer = setInterval(() => {
      if (!win.isVisible() || !s.compact || s.menuOpen) return;
      const p = screen.getCursorScreenPoint(), b = win.getBounds();
      const hovered = p.x >= b.x && p.x < b.x + b.width && p.y >= b.y && p.y < b.y + b.height;
      if (s.hovered !== hovered) { s.hovered = hovered; applyAppearance(); controller.publish(); }
    }, 80);
    applyAppearance(); rebuildTray(); await win.loadFile(pagePath);
    show();
    if (!demo) void controller.start();
    if (diagnostics) await runDiagnostics();
    const captureIndex = process.argv.indexOf('--capture');
    if (demo && captureIndex >= 0 && process.argv[captureIndex + 1]) await captureScreenshots(process.argv[captureIndex + 1]);
  }).catch(e => { console.error(e); app.exit(1); });
}
app.on('activate', show);
app.on('before-quit', () => { quitting = true; if (win) saveBounds(); clearTimeout(saveTimer); persist(); controller?.stop(); clearInterval(hoverTimer); });
app.on('will-quit', () => globalShortcut.unregisterAll());
async function runDiagnostics() {
  const assert = (condition, message) => { if (!condition) throw new Error(message); console.log(`PASS: ${message}`); };
  try {
    assert(win.webContents.getLastWebPreferences().sandbox && !win.webContents.getLastWebPreferences().nodeIntegration, 'Renderer is sandboxed and Node is isolated');
    assert(globalShortcut.isRegistered(shortcut), 'Global hide shortcut registered');
    assert(trayMenu().items[0].label === '湖人 102 : 99 勇士 · 第四节 剩2:18', 'Tray heading shows score and status');
    setMode(true); assert(win.getBounds().height === 32, 'Single line is 32 points');
    const before = win.getBounds(); updatePreferences({ rows: 3 });
    assert(win.getBounds().height === 96 && win.getBounds().y === before.y, 'Three lines preserve the top edge');
    controller.select(controller.state.days[0].matchList[1]);
    assert(controller.state.compact && win.getBounds().height === 96, 'Switching matches preserves compact mode');
    updatePreferences({ rows: 6 }); assert(win.getBounds().height === 192, 'Six lines are 192 points');
    win.hide(); assert(!win.isVisible(), 'Hide removes window'); show(); assert(win.isVisible(), 'Restore shows window');
    setMode(false); assert(win.getBounds().height >= 460, 'Expanded window restored');
    updatePreferences({ simple: true }); assert(controller.state.compact, 'Simple preference enters compact mode');
    setMode(false); assert(controller.state.preferences.simple, 'Temporary expansion preserves simple preference');
    await new Promise(resolve => setTimeout(resolve, 200));
    const result = await win.webContents.executeJavaScript(`({ title: document.querySelector('h1')?.textContent, teamLogos: document.querySelectorAll('.team-logo').length, bridge: typeof window.yuguang.command, node: typeof window.require })`);
    assert(result.bridge === 'function' && result.node === 'undefined', 'Preload exposes narrow bridge only');
    assert(result.teamLogos === 0, 'Simple preference removes team logos from full window');
    console.log('Desktop checks complete'); app.exit(0);
  } catch (e) { console.error('FAIL:', e); app.exit(1); }
}

async function captureScreenshots(directory) {
  fs.mkdirSync(directory, { recursive: true });
  const capture = async name => {
    await new Promise(resolve => setTimeout(resolve, 200));
    const png = await win.webContents.capturePage();
    fs.writeFileSync(path.join(directory, `${name}.png`), png.toPNG());
  };
  setMode(false); win.setBounds({ ...win.getBounds(), width: 420, height: 640 });
  controller.state.preferences.simple = false; controller.state.preferences.theme = 'light'; applyAppearance(); controller.publish();
  await capture('live-light');
  controller.state.preferences.theme = 'dark'; applyAppearance(); controller.publish(); await capture('live-dark');
  controller.state.preferences.theme = 'light'; controller.state.page = 'matches'; applyAppearance(); controller.publish(); await capture('matches');
  controller.state.page = 'settings'; controller.publish(); await capture('settings');
  controller.state.page = 'live'; controller.state.preferences.rows = 1; setMode(true);
  controller.state.menuOpen = true; controller.publish(); await capture('compact');
  controller.state.menuOpen = false; controller.state.hovered = false; controller.publish(); await capture('compact-text-only');
  updatePreferences({ rows: 3 }); controller.state.menuOpen = true; controller.publish(); await capture('compact-multiline');
  controller.state.menuOpen = false; controller.state.hovered = false; controller.publish(); await capture('compact-multiline-transparent');
  app.exit(0);
}
