const { openDB } = window.idb;

// --- YOUR EXISTING DB LOGIC ---
const DB_NAME = 'Dictionary';
const DB_VERSION = 1;
const NOTEBOOK_STORE_NAME = 'note';
const CN_STORE_NAME = 'cn';
const KR_STORE_NAME = 'ko';
const JP_STORE_NAME = 'jp';

const initDB = async () => {
  return openDB(DB_NAME, DB_VERSION, {
    upgrade(db) {
      if (!db.objectStoreNames.contains(NOTEBOOK_STORE_NAME)) {
        const options = { keyPath: 'id', autoIncrement: true };
        db.createObjectStore(CN_STORE_NAME, options);
        db.createObjectStore(JP_STORE_NAME, options);
        db.createObjectStore(KR_STORE_NAME, options);
        const nbStore = db.createObjectStore(NOTEBOOK_STORE_NAME, options);
        nbStore.createIndex('language', 'language', { unique: false });
        nbStore.createIndex('word_id', 'word_id', { unique: false });
      }
    },
  });
};

const dbPromise = initDB();

const getNotebookEntries = async () => {
  const db = await dbPromise;
  const notebookRecords = await db.getAll(NOTEBOOK_STORE_NAME);
  const joinedEntries = await Promise.all(notebookRecords.map(async (nb) => {
    let storeName;
    switch (nb.language) {
      case "cn": storeName = CN_STORE_NAME; break;
      case "ja": case "jp": storeName = JP_STORE_NAME; break; // handle both jp/ja safely
      case "ko": storeName = KR_STORE_NAME; break;
      default: return null;
    }
    const dictWord = await db.get(storeName, nb.word_id);
    if (!dictWord) return null;
    return {
      notebook_id: nb.id,
      memory_level: nb.memory_level,
      lang: nb.language,
      dict_data: dictWord,
      interval: nb.interval || 0,
      easeFactor: nb.easeFactor || 2.5,
      nextReview: nb.nextReview || 0
    };
  }));
  return joinedEntries.filter(entry => entry !== null);
};

async function updateCardStats(notebookIdStr, newLevel, interval, easeFactor, nextReview) {
  // Use your existing DB connection setup here
  const db = await dbPromise;
  const tx = db.transaction(NOTEBOOK_STORE_NAME, 'readwrite');
  const store = tx.objectStore(NOTEBOOK_STORE_NAME);

  const numericId = parseInt(notebookIdStr, 10);
  const record = await store.get(numericId);

  if (record) {
    record.memory_level = newLevel;
    record.interval = interval;
    record.easeFactor = easeFactor;
    record.nextReview = nextReview;

    await store.put(record);
  }

  await tx.done;
}


// Calculates the edit distance between two strings
const getEditDistance = (a, b) => {
    if (a.length === 0) return b.length;
    if (b.length === 0) return a.length;

    const matrix = [];
    for (let i = 0; i <= b.length; i++) matrix[i] = [i];
    for (let j = 0; j <= a.length; j++) matrix[0][j] = j;

    for (let i = 1; i <= b.length; i++) {
        for (let j = 1; j <= a.length; j++) {
            if (b.charAt(i - 1) === a.charAt(j - 1)) {
                matrix[i][j] = matrix[i - 1][j - 1];
            } else {
                matrix[i][j] = Math.min(
                    matrix[i - 1][j - 1] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j] + 1
                );
            }
        }
    }
    return matrix[b.length][a.length];
};

export const searchWords = async (query, targetLang) => {
  const db = await dbPromise;

  if (!query || !query.trim()) return [];
  const lowerQuery = query.toLowerCase().trim();

  // 1. Dynamically select the correct store
  let storeName;
  switch (targetLang) {
    case "cn":
          storeName = CN_STORE_NAME; break;
    case "ko":
          storeName = KR_STORE_NAME; break;
    case "jp":
          storeName = JP_STORE_NAME; break;
    default: throw new Error(`Unknown language store: ${targetLang}`);
  }

  // 2. Fetch all entries from the specific language store
  const allEntries = await db.getAll(storeName);

  // 3. Filter using language-specific logic
  const filteredWords = allEntries.filter(entry => {
    const meaning = entry.meaning?.toLowerCase() || "";

    switch (targetLang) {
      case "cn":
        return entry.simplified.includes(lowerQuery) ||
          entry.traditional.includes(lowerQuery);

      case "jp":
        return entry.word.includes(lowerQuery) ||
               (entry.alternatives && entry.alternatives.some(alt => alt.includes(lowerQuery)));

      case "ko":
        return entry.word.includes(lowerQuery);
    }
  });

  // 4. Sort by closest string match
  return filteredWords.sort((a, b) => {
    // Helper to get the best (lowest) distance score for a single entry
    const getBestScore = (entry) => {
      const meaningScore = getEditDistance(lowerQuery, (entry.meaning || "").toLowerCase());
      let wordScores = [];

      switch (targetLang) {
        case "cn":
          wordScores.push(getEditDistance(lowerQuery, entry.simplified));
          wordScores.push(getEditDistance(lowerQuery, entry.traditional));
          break;
        case "jp":
          wordScores.push(getEditDistance(lowerQuery, entry.word));
          if (entry.alternatives) {
            entry.alternatives.forEach(alt => wordScores.push(getEditDistance(lowerQuery, alt)));
          }
          break;
        case "ko":
          wordScores.push(getEditDistance(lowerQuery, entry.word));
          break;
      }

      // Return the lowest edit distance found across all valid fields
      return Math.min(meaningScore, ...wordScores);
    };

    // Compare the best score of entry A against entry B
    return getBestScore(a) - getBestScore(b);
  });
};

export const addToNotebook = async (language, wordId, referenceStringId = null) => {
  const db = await dbPromise;

  const entry = {
    language: language,
    word_id: wordId,
    reference_string_id: referenceStringId,
    memory_level: 0,
    date_added: new Date().toISOString(),
    tags: []
  };

  await db.add(NOTEBOOK_STORE_NAME, entry);
};

export const removeFromNotebookByWordId = async (language, wordId) => {
  const db = await dbPromise;

  // 1. Fetch all notebook records that have this word_id
  const records = await db.getAllFromIndex(NOTEBOOK_STORE_NAME, 'word_id', wordId);

  // 2. Find the specific record that also matches the requested language
  const targetRecord = records.find(record => record.language === language);

  // 3. Delete it using its true, auto-incremented primary key
  if (targetRecord && targetRecord.id !== undefined) {
    await db.delete(NOTEBOOK_STORE_NAME, targetRecord.id);
  }
};

export const removeFromNotebookById = async (notebookIdString) => {
  const db = await dbPromise;
  const id = parseInt(notebookIdString, 10);
  await db.delete(NOTEBOOK_STORE_NAME, id);
};

export const updateMemoryLevel = async (notebookIdString, newLevel) => {
  const db = await dbPromise;

  // 1. Convert the OCaml string ID back to an integer
  // (Because IndexedDB autoIncrement uses strict integers)
  const id = parseInt(notebookIdString, 10);

  // 2. Fetch the existing notebook entry using its primary key
  const entry = await db.get(NOTEBOOK_STORE_NAME, id);

  if (entry) {
    // 3. Update the memory level
    entry.memory_level = newLevel;

    // 4. Save the modified object back into the database
    await db.put(NOTEBOOK_STORE_NAME, entry);
    console.log(`[DB] Updated notebook entry ${id} to memory level ${newLevel}`);
  } else {
    console.warn(`[DB] Could not find notebook entry ${id} to update.`);
  }
};

// 1. Configuration
const CLIENT_ID = '351621210963-5jvm93o4fbrkeadvkv4l9v89b119ohfl.apps.googleusercontent.com';
const SCOPES = 'https://www.googleapis.com/auth/drive.appdata';
let tokenClient;
let accessToken = null;

const overwriteLocalDatabase = async (remoteData) => {
    const db = await dbPromise;

    // Start a transaction that covers all stores you want to update
    const tx = db.transaction([NOTEBOOK_STORE_NAME], 'readwrite');
    const store = tx.objectStore(NOTEBOOK_STORE_NAME);

    // Clear existing data to ensure a clean state from the cloud
    await store.clear();

    // Write the new data
    for (const entry of remoteData) {
        await store.put(entry);
    }

    await tx.done;
};

const pushToCloud = async (app, db, fileId) => {
    app.ports.syncStatus.send("Uploading...");
    const notebookData = await db.getAll(NOTEBOOK_STORE_NAME);
    const fileContent = new Blob([JSON.stringify(notebookData)], { type: 'application/json' });

    const form = new FormData();

    // --- THE FIX IS HERE ---
    const metadata = { name: 'dictionary_backup.json' };

    // Only set the 'parents' folder if we are CREATING a new file
    if (!fileId) {
        metadata.parents = ['appDataFolder'];
    }
    // -----------------------

    form.append('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }));
    form.append('file', fileContent);

    const url = fileId
        ? `https://www.googleapis.com/upload/drive/v3/files/${fileId}?uploadType=multipart`
        : `https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart`;

    const res = await fetch(url, {
        method: fileId ? 'PATCH' : 'POST',
        headers: { Authorization: `Bearer ${accessToken}` },
        body: form
    });

    if (!res.ok) {
        const errText = await res.text();
        throw new Error(`Upload failed: ${res.status} - ${errText}`);
    }

    const result = await res.json();
    const finalId = fileId || result.id;

    const metaRes = await fetch(`https://www.googleapis.com/drive/v3/files/${finalId}?fields=modifiedTime`, {
        headers: { Authorization: `Bearer ${accessToken}` }
    });

    if (!metaRes.ok) throw new Error("Failed to fetch modifiedTime");

    const meta = await metaRes.json();

    localStorage.setItem('local_modified', new Date(meta.modifiedTime).getTime().toString());
    app.ports.syncStatus.send("Synced successfully!");
};

// PULL logic
const pullFromCloud = async (app, db, fileId) => {
    app.ports.syncStatus.send("Downloading...");
    const res = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`, {
        headers: { Authorization: `Bearer ${accessToken}` }
    });
    const remoteData = await res.json();

    await overwriteLocalDatabase(remoteData);

    // Update local modified to match remote
    const metaRes = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?fields=modifiedTime`, {
        headers: { Authorization: `Bearer ${accessToken}` }
    });
    const meta = await metaRes.json();
    localStorage.setItem('local_modified', new Date(meta.modifiedTime).getTime().toString());

    app.ports.syncStatus.send("Synced successfully!");
};


// 4. The Sync Logic
const syncDatabase = async (app) => {
  if (!accessToken) return;

  app.ports.syncStatus.send("Syncing...");

  try {
    const db = await dbPromise;
    // Ensure localModified is a number
    const localModified = parseInt(localStorage.getItem('local_modified') || '0', 10);

    // A. Check for existing file in appDataFolder
    const searchRes = await fetch(
      "https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=name='dictionary_backup.json'&fields=files(id,modifiedTime)",
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );

    if (!searchRes.ok) throw new Error("Failed to search Drive");

    const searchData = await searchRes.json();
    const driveFile = searchData.files?.[0] || null;
    const remoteModified = driveFile ? new Date(driveFile.modifiedTime).getTime() : 0;

    // CASE 1: No file in Drive -> Push local immediately (if we have data)
    if (!driveFile) {
        if (localModified > 0) {
            app.ports.syncStatus.send("Pushing initial backup...");
            await pushToCloud(app, db, null); // POST
        } else {
            app.ports.syncStatus.send("No data to sync.");
        }
        return;
    }

    // CASE 2: Drive file exists -> Compare Timestamps
    if (localModified > remoteModified) {
        // Local is newer -> Push
        app.ports.syncStatus.send("Uploading changes...");
        await pushToCloud(app, db, driveFile.id); // PATCH
    }
    else if (remoteModified > localModified) {
        // Remote is newer -> Pull
        app.ports.syncStatus.send("Downloading updates...");
        await pullFromCloud(app, db, driveFile.id);
    }
    else {
        app.ports.syncStatus.send("Everything is up to date!");
        return;
    }

    app.ports.syncStatus.send("Synced successfully");

  } catch (error) {
    console.error("Sync Error:", error);
    app.ports.syncStatus.send("Sync failed.");
  }
};

// Helper to strip quotes (matches your OCaml strip_quotes)
const stripQuotes = (s) => {
    let clean = s.trim();
    if (clean.length >= 2 && clean.startsWith('"') && clean.endsWith('"')) {
        return clean.substring(1, clean.length - 1);
    }
    return clean;
};

// Translating your OCaml Parsers
const parseChinese = (rawText) => {
    return rawText.split('\n').reduce((acc, line) => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('simplified')) return acc;

        const parts = trimmed.split('\t');
        if (parts.length >= 5) {
            const hskLevel = parseInt(parts[4], 10);
            acc.push({
                id: parts[0],
                simplified: parts[0],
                traditional: parts[1],
                pinyin: parts[2],
                zhuyin: null,
                meaning: parts[3],
                hsk: isNaN(hskLevel) ? 0 : hskLevel
            });
        }
        return acc;
    }, []);
};

const parseJapanese = (rawText) => {
    return rawText.split('\n').reduce((acc, line) => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('expression')) return acc;

        const parts = trimmed.split(',');
        if (parts.length >= 3) {
            const expr = parts[0];
            const reading = parts[1];
            // Extract meaning and tags from the remaining parts
            const meaningRaw = parts.slice(2, parts.length - 1).join(',');
            const tagsStr = parts[parts.length - 1];

            // Extract JLPT
            let jlptLevel = 0;
            if (tagsStr.includes("JLPT_1")) jlptLevel = 1;
            else if (tagsStr.includes("JLPT_2")) jlptLevel = 2;
            else if (tagsStr.includes("JLPT_3")) jlptLevel = 3;
            else if (tagsStr.includes("JLPT_4")) jlptLevel = 4;
            else if (tagsStr.includes("JLPT_5")) jlptLevel = 5;

            acc.push({
                id: expr,
                word: expr,
                furigana: reading,
                alternatives: [],
                meaning: stripQuotes(meaningRaw),
                jlpt: jlptLevel
            });
        }
        return acc;
    }, []);
};

const parseKorean = (rawText) => {
    return rawText.split('\n').reduce((acc, line) => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('id')) return acc;

        const parts = trimmed.split('\t');
        if (parts.length >= 5 && parts[1] && parts[0]) {
            let topikLevel = 0;
            if (parts[4] === "A") topikLevel = 1;
            else if (parts[4] === "B") topikLevel = 2;

            acc.push({
                id: parts[0],
                word: parts[1],
                hanja: parts[2] === "" ? null : parts[2],
                meaning: parts[3],
                topik: topikLevel
            });
        }
        return acc;
    }, []);
};

// The Main Bootstrap Engine
export const bootstrapDatabase = async (dbPromise, reportProgress) => {
    reportProgress("Fetching Chinese (HSK)...");
    const cnRes = await fetch('/goldfish/hsk.tsv');
    const cnData = parseChinese(await cnRes.text());

    reportProgress("Fetching Japanese (JLPT)...");
    const jpRes = await fetch('/goldfish/jlpt.csv');
    const jpData = parseJapanese(await jpRes.text());

    reportProgress("Fetching Korean (Kengdic)...");
    const koRes = await fetch('/goldfish/kengdic.tsv');
    const koData = parseKorean(await koRes.text());

    reportProgress("Installing to Database. This may take a moment...");
    const db = await dbPromise;

    // Batch Insert to prevent freezing the browser
    const tx = db.transaction(['cn', 'jp', 'ko'], 'readwrite');

    cnData.forEach(entry => tx.objectStore('cn').put(entry));
    jpData.forEach(entry => tx.objectStore('jp').put(entry));
    koData.forEach(entry => tx.objectStore('ko').put(entry));

    await tx.done;

    localStorage.setItem("dict_db_loaded", "true");
    reportProgress("Complete");

    window.location.reload();
};

// --- ELM-LAND INTEROP BRIDGE ---
export const onReady = ({ app }) => {
  if (!app.ports) return;

  const isLoaded = localStorage.getItem("dict_db_loaded") === "true";
  if (app.ports.dbStatusReceived) {
    // We wrap in setTimeout to ensure Elm has initialized its subscriptions
    setTimeout(() => app.ports.dbStatusReceived.send(isLoaded), 10);
  }

  // 2. Listen for Elm's command to start installation
  if (app.ports.startDbInstall) {
    app.ports.startDbInstall.subscribe(async () => {
      try {
        await bootstrapDatabase(dbPromise, (msg) => {
          if (app.ports.installProgress) app.ports.installProgress.send(msg);
        });
        app.ports.dbStatusReceived.send(true);
      } catch (error) {
        console.error("Bootstrap failed:", error);
        if (app.ports.installProgress) app.ports.installProgress.send("Error installing database.");
      }
    });
  }

  let tokenClient = google.accounts.oauth2.initTokenClient({
    client_id: CLIENT_ID,
    scope: SCOPES,
    callback: (tokenResponse) => {
      if (tokenResponse && tokenResponse.access_token) {
        accessToken = tokenResponse.access_token;
        app.ports.authStatusChanged.send(true);
        // Automatically trigger a sync upon login

        syncDatabase(app);
      }
    },
  });

  // 3. Listen for Elm Commands
  if (app.ports.requestSignIn) {
    app.ports.requestSignIn.subscribe(() => {
      tokenClient.requestAccessToken();
    });
  }

  if (app.ports.requestSignOut) {
    app.ports.requestSignOut.subscribe(() => {
      if (accessToken) {
        google.accounts.oauth2.revoke(accessToken, () => {
          accessToken = null;
          app.ports.authStatusChanged.send(false);
        });
      }
    });
  }

  if (app.ports.requestSync) {
    app.ports.requestSync.subscribe(() => {
      syncDatabase(app);
    });
  }

  // 1. Handle Search Requests
  if (app.ports.requestSearch) {
    app.ports.requestSearch.subscribe(async (req) => {
      try {
        const results = await searchWords(req.query, req.lang);
        if (app.ports.receiveSearchResults) {
            app.ports.receiveSearchResults.send(results.slice(0, 50));
        }
      } catch (err) {
        console.error("Search failed", err);
        if (app.ports.receiveSearchResults) app.ports.receiveSearchResults.send([]);
      }
    });
  }

  // 2. Handle Notebook Fetch Requests
  if (app.ports.requestNotebook) {
    app.ports.requestNotebook.subscribe(async () => {
      const entries = await getNotebookEntries();
      if (app.ports.receiveNotebook) {
        app.ports.receiveNotebook.send(entries);
      }
    });
  }

  // 3. Handle Mutations (Add, Remove, Update)
  if (app.ports.mutateNotebook) {
    app.ports.mutateNotebook.subscribe(async (mutation) => {
      console.log("notebook change", mutation);
      try {
        switch (mutation.action) {
          case "ADD":
            await addToNotebook(mutation.lang, mutation.wordId, mutation.refId);
            break;
          case "REMOVE":
            await removeFromNotebookById(mutation.notebookIdString);
            break;
          case "REMOVE_BY_WORD_ID":
            // Pass the language down to the DB function!
            await removeFromNotebookByWordId(mutation.lang, mutation.wordId);
            break;
          case "UPDATE_LEVEL":
            await updateMemoryLevel(mutation.notebookIdString, mutation.newLevel);
            break;
          case "UPDATE_STATS":
            await updateCardStats(
              mutation.notebookIdString,
              mutation.newLevel,
              mutation.interval,
              mutation.easeFactor,
              mutation.nextReview
            );
            break;
        }

        localStorage.setItem('local_modified', new Date().getTime().toString());

        // Auto-refresh the Elm UI by sending the updated notebook back
        const updatedEntries = await getNotebookEntries();
        if (app.ports.receiveNotebook) {
          app.ports.receiveNotebook.send(updatedEntries);
        }

      } catch (err) {
        console.error("Mutation failed", err);
      }
    });
  }
};
