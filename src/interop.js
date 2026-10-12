import {
  addToNotebook,
  bootstrapDatabase,
  database,
  getNotebookEntries,
  getWordsByLevelAsNotebookEntries,
  removeFromNotebookById,
  removeFromNotebookByWordId,
  searchWords,
  updateCardStats,
  updateMemoryLevel,
} from './js/db.js';
import { init as cloudInit, requestSignIn, requestSignOut, syncDatabase } from './js/cloud.js';

const send = (port, value) => {
  if (port) port.send(value);
};

const waitForGoogle = () => new Promise((resolve) => {
  const startedAt = Date.now();
  const check = () => {
    if (window.google?.accounts?.oauth2) return resolve(true);
    if (Date.now() - startedAt > 10000) return resolve(false);
    window.setTimeout(check, 50);
  };
  check();
});

export const onReady = async ({ app }) => {
  if (!app.ports) return;

  const reportDbStatus = async () => {
    // Report the persisted install flag immediately. Waiting for IndexedDB
    // here can leave a newly opened Settings page stuck on Checking.
    send(app.ports.dbStatusReceived, localStorage.getItem('dict_db_loaded') === 'true');
    try {
      await database;
    } catch (error) {
      console.error('Database initialization failed:', error);
      send(app.ports.dbStatusReceived, false);
    }
  };

  // Subscribe before any awaits: Elm can issue requestDbStatus immediately
  // while onReady is still waiting for IndexedDB or Google APIs.
  app.ports.requestDbStatus?.subscribe(reportDbStatus);

  // Register all ports before awaiting anything, including Google APIs.
  const reloadNotebook = async () => {
    try {
      send(app.ports.receiveNotebook, await getNotebookEntries());
    } catch (error) {
      console.error('Notebook reload failed:', error);
    }
  };

  // Re-read IndexedDB whenever the tab becomes active again. This also picks
  // up changes made by another tab without requiring a full browser reload.
  const onActive = () => {
    if (document.visibilityState === 'visible') reloadNotebook();
  };

  document.addEventListener('visibilitychange', onActive);
  window.addEventListener('focus', onActive);

  app.ports.startDbInstall?.subscribe(async () => {
    try {
      await bootstrapDatabase(database, (message) => send(app.ports.installProgress, message));
      send(app.ports.dbStatusReceived, true);
      await reloadNotebook();
    } catch (error) {
      console.error('Bootstrap failed:', error);
      send(app.ports.installProgress, 'Error installing database.');
    }
  });

  app.ports.requestSearch?.subscribe(async (request) => {
    try { send(app.ports.receiveSearchResults, (await searchWords(request.query, request.lang, request.includeEnglish === true)).slice(0, 50)); }
    catch (error) { console.error('Search failed:', error); send(app.ports.receiveSearchResults, []); }
  });
  app.ports.requestNotebook?.subscribe(reloadNotebook);
  let characterIndex;
  app.ports.requestCharacterIndex?.subscribe(async () => {
    try {
      if (!characterIndex) {
        // GitHub Pages serves this app below /goldfish/, while local builds
        // serve it at /. Resolve beside the current document in either case.
        const response = await fetch(new URL('character-index.json', window.location.href).pathname);
        if (!response.ok) throw new Error(`Character index request failed: ${response.status}`);
        characterIndex = await response.json();
      }
      send(app.ports.receiveCharacterIndex, characterIndex);
    } catch (error) {
      console.error('Character index failed to load:', error);
      send(app.ports.receiveCharacterIndex, { count: 0, characters: [], components: {} });
    }
  });
  app.ports.scrollToTop?.subscribe(() => window.scrollTo({ top: 0, behavior: 'smooth' }));
  app.ports.requestWordsByLevelNotebook?.subscribe(async ({ lang, level }) => {
    send(app.ports.receiveWordsByLevelNotebook, await getWordsByLevelAsNotebookEntries(lang, level));
  });

  app.ports.mutateNotebook?.subscribe(async (mutation) => {
    try {
      switch (mutation.action) {
        case 'ADD': await addToNotebook(mutation.lang, mutation.wordId, mutation.refId); break;
        case 'REMOVE': await removeFromNotebookById(mutation.notebookIdString); break;
        case 'REMOVE_BY_WORD_ID': await removeFromNotebookByWordId(mutation.lang, mutation.wordId); break;
        case 'UPDATE_LEVEL': await updateMemoryLevel(mutation.notebookIdString, mutation.newLevel); break;
        case 'UPDATE_STATS': await updateCardStats(mutation.notebookIdString, mutation.newLevel, mutation.interval, mutation.easeFactor, mutation.nextReview); break;
        default: return;
      }
      localStorage.setItem('local_modified', Date.now().toString());
      await reloadNotebook();
    } catch (error) { console.error('Mutation failed:', error); }
  });

  app.ports.importDatabaseFile?.subscribe(async () => {
    try {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = 'application/json,.json';
      input.click();
      input.onchange = async () => {
        const file = input.files?.[0];
        if (!file) return;
        try {
          const parsed = JSON.parse(await file.text());
          const records = Array.isArray(parsed) ? parsed : parsed.notebook;
          if (!Array.isArray(records)) throw new Error('Expected a notebook array or an export object.');
          const db = await database;
          let imported = 0;
          const dictionaryCaches = new Map();
          const resolveWord = async (storeName, wordId) => {
            const direct = await db.get(storeName, wordId);
            if (direct) return direct;
            if (!dictionaryCaches.has(storeName)) dictionaryCaches.set(storeName, await db.getAll(storeName));
            return dictionaryCaches.get(storeName).find(word => String(word.id) === String(wordId));
          };
          const normalizedRecords = [];
          for (const source of records) {
            if (!source || typeof source.language !== 'string' || source.word_id == null) continue;
            const language = source.language === 'ja' ? 'jp' : source.language;
            const importedWordId = String(source.word_id);
            const dictionaryStore = language === 'cn' ? 'cn' : language === 'jp' ? 'jp' : 'ko';
            let canonicalWordId = importedWordId;
            const dictionaryWord = await resolveWord(dictionaryStore, importedWordId);
            if (dictionaryWord) canonicalWordId = String(dictionaryWord.id);

            const record = {
              language,
              word_id: canonicalWordId,
              memory_level: Number(source.memory_level || 0),
              interval: Number(source.interval || 0),
              easeFactor: Number(source.easeFactor || 2.5),
              nextReview: Number(source.nextReview || 0),
              tags: Array.isArray(source.tags) ? source.tags : []
            };
            delete record.id;
            normalizedRecords.push({ key: [language, canonicalWordId], record });
            imported += 1;
          }
          const tx = db.transaction('note', 'readwrite');
          const store = tx.objectStore('note');
          for (const { key, record } of normalizedRecords) {
            const existing = await store.index('language_word').get(key);
            await store.put(existing ? { ...existing, ...record, id: existing.id } : record);
          }
          await tx.done;
          send(app.ports.importStatus, `Imported ${imported} notebook entries.`);
          await reloadNotebook();
        } catch (error) {
          console.error('Database import failed:', error);
          send(app.ports.importStatus, `Import failed: ${error.message}`);
        }
      };
    } catch (error) {
      send(app.ports.importStatus, `Import failed: ${error.message}`);
    }
  });
  app.ports.requestExportDatabase?.subscribe(async () => {
    try {
      const db = await database;
      const notebook = await db.getAll('note');
      const payload = JSON.stringify({ version: 1, exportedAt: new Date().toISOString(), notebook });
      const blob = new Blob([payload], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'goldfish-notebook.json';
      link.click();
      URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Database export failed:', error);
    }
  });
  if (await waitForGoogle()) cloudInit();
  app.ports.requestSignIn?.subscribe(() => requestSignIn());
  app.ports.requestSignOut?.subscribe(() => requestSignOut());
  app.ports.requestSync?.subscribe(() => syncDatabase(app));
};
