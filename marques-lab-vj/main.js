const { app, BrowserWindow, Menu, dialog, ipcMain } = require('electron');
const path = require('path');

app.setName('Marques Lab VJ');

function createWindow() {
  const win = new BrowserWindow({
    width: 1760,
    height: 1050,
    minWidth: 1280,
    minHeight: 760,
    backgroundColor: '#09090d',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 18, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

function buildMenu() {
  const isMac = process.platform === 'darwin';
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    ...(isMac ? [{
      label: 'Marques Lab VJ',
      submenu: [
        { role: 'about', label: 'Sobre o Marques Lab VJ' },
        { type: 'separator' },
        { role: 'hide', label: 'Ocultar' },
        { role: 'hideOthers', label: 'Ocultar outros' },
        { role: 'unhide', label: 'Mostrar tudo' },
        { type: 'separator' },
        { role: 'quit', label: 'Sair do Marques Lab VJ' }
      ]
    }] : []),
    {
      label: 'Projeto',
      submenu: [
        { label: 'Importar mídia…', click: (_, browserWindow) => browserWindow?.webContents.send('open-import') },
        { label: 'Salvar projeto', click: (_, browserWindow) => browserWindow?.webContents.send('save-project') },
        { type: 'separator' },
        { role: 'close', label: 'Fechar janela' }
      ]
    },
    {
      label: 'Visualizar',
      submenu: [
        { role: 'reload', label: 'Recarregar interface' },
        { role: 'resetZoom', label: 'Zoom padrão' },
        { role: 'zoomIn', label: 'Aumentar zoom' },
        { role: 'zoomOut', label: 'Diminuir zoom' },
        { type: 'separator' },
        { role: 'togglefullscreen', label: 'Tela cheia' }
      ]
    },
    {
      label: 'Ajuda',
      submenu: [
        { label: 'Atalhos', click: (_, browserWindow) => browserWindow?.webContents.send('show-shortcuts') }
      ]
    }
  ]));
}

ipcMain.handle('pick-media', async () => {
  const result = await dialog.showOpenDialog({
    properties: ['openFile', 'multiSelections'],
    filters: [
      { name: 'Mídia', extensions: ['mp4', 'mov', 'm4v', 'webm', 'png', 'jpg', 'jpeg', 'gif', 'mp3', 'wav', 'aiff'] }
    ]
  });
  return result.canceled ? [] : result.filePaths;
});

ipcMain.handle('app-info', () => ({ version: app.getVersion(), platform: process.platform, arch: process.arch }));

app.whenReady().then(() => {
  buildMenu();
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
