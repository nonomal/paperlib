/**
 * This file is used specifically for security reasons.
 * Here you can access Nodejs stuff and inject functionality into
 * the renderer thread (accessible there through the "window" object)
 *
 * WARNING!
 * If you import anything from node_modules, then make sure that the package is specified
 * in package.json > dependencies and NOT in devDependencies
 *
 * Example (injects window.myAPI.doAThing() into renderer thread):
 *
 *   import { contextBridge } from 'electron'
 *
 *   contextBridge.exposeInMainWorld('myAPI', {
 *     doAThing: () => {}
 *   })
 */

import { contextBridge, shell, ipcRenderer } from "electron";
import { app, BrowserWindow } from "@electron/remote";
import { Interactor } from "../src/interactors/interactor";
import * as pathLib from "path";

const interactor = new Interactor();

contextBridge.exposeInMainWorld("api", {
  // Window functions
  minimize() {
    BrowserWindow.getFocusedWindow().minimize();
  },

  toggleMaximize() {
    const win = BrowserWindow.getFocusedWindow();

    if (win.isMaximized()) {
      win.unmaximize();
    } else {
      win.maximize();
    }
  },

  close() {
    BrowserWindow.getFocusedWindow().close();
  },

  // ==============================
  // Interactor functions
  // Listening to Realm change
  listenRealmChange(callback) {
    interactor.listenRealmChange(callback);
  },

  // Load
  async load(search, flag, tag, folder, sortBy, sortOrder) {
    return await interactor.load(search, flag, tag, folder, sortBy, sortOrder);
  },

  async loadTags() {
    return await interactor.loadTags();
  },

  async loadFolders() {
    return await interactor.loadFolders();
  },

  // Add
  async add(pathList) {
    return await interactor.add(pathList);
  },

  addSups(id, pathList) {
    interactor.addSups(id, pathList);
  },

  // Delete
  delete(entities) {
    interactor.delete(entities);
  },

  deleteSup(entity, supURL) {
    interactor.deleteSup(entity, supURL);
  },

  deleteTag(tagName) {
    interactor.deleteTag(tagName);
  },

  deleteFolder(folderName) {
    interactor.deleteFolder(folderName);
  },

  // Update
  flag(entities) {
    interactor.flag(entities);
  },

  async match(entities) {
    return await interactor.match(entities);
  },

  update(entity) {
    interactor.update(entity);
  },

  // Open
  open(url) {
    let joinedPath = pathLib
      .join(interactor.appLibPath(), url)
      .replace("file://", "");
    shell.openPath(joinedPath);
  },

  // Export
  export(entities, format) {
    interactor.export(entities, format);
  },

  // ==============================
  // Settings
  loadSettings() {
    return interactor.loadSettings();
  },

  async saveSettings(settings) {
    let realmChanged = await interactor.saveSettings(settings);
    if (realmChanged) {
      BrowserWindow.getFocusedWindow().webContents.send("realmChanged");
    }
    return true;
  },

  getFolder(path) {
    return pathLib.dirname(path);
  },

  version() {
    return app.getVersion();
  },

  loadAppLibPath() {
    return interactor.appLibPath();
  },

  getJoinedPath(url, withProtocol) {
    let joinedPath = pathLib.join(interactor.appLibPath(), url);
    if (withProtocol) {
      return "file://" + joinedPath;
    } else {
      return joinedPath.replace("file://", "");
    }
  },

  registerSignal(signal, callback) {
    ipcRenderer.on(signal, callback);
  },

  setRoutineTimer() {
      interactor.setRoutineTimer();
  }
});
