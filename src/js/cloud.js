import { database, getNotebook, overwriteNotebook } from './db.js';

const dbPromise = database;

const getGoogle = () => window.google;

const CLIENT_ID = '351621210963-5jvm93o4fbrkeadvkv4l9v89b119ohfl.apps.googleusercontent.com';
const SCOPES = 'https://www.googleapis.com/auth/drive.appdata';

const BACKUP_FILE_NAME = 'dictionary_backup.json';

const BACKUP_FILE = "https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=name='dictionary_backup.json'&fields=files(id,modifiedTime)";

// object cannot be stored
let tokenClient = null;

function tryGetToken() {
  const token = localStorage.getItem('access_token');
  const expiresAt = localStorage.getItem('expires_at');

  if (token && expiresAt && Date.now() < parseInt(expiresAt)) {
    return token;
  } else {
    return null;
  }
}

function ensureLogin() {
  let token = tryGetToken();
  if (!token) {
    tokenClient.requestAccessToken();
  }
  token = tryGetToken();
  return token;
}

export const init = (cb) => {
  // always set, so that we can issue registration anytime
  // tokenClient is an object with methods, so cannot be stored
  tokenClient = getGoogle().accounts.oauth2.initTokenClient({
    client_id: CLIENT_ID,
    scope: SCOPES,
    callback: (tokenResponse) => {
      if (tokenResponse && tokenResponse.access_token) {
        localStorage.setItem('access_token', tokenResponse.access_token);
        localStorage.setItem('expires_at', Date.now() + (tokenResponse.expires_in * 1000));
      }
    },
  });
}

const pushToCloud = async (app, db, fileId) => {
  let accessToken = ensureLogin();

    app.ports.syncStatus.send("Uploading...");
    const notebookData = await getNotebook();
    const fileContent = new Blob([JSON.stringify(notebookData)], { type: 'application/json' });

    const form = new FormData();

    const metadata = { name: BACKUP_FILE_NAME };

    if (!fileId) {
        metadata.parents = ['appDataFolder'];
    }

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

const pullFromCloud = async (app, db, fileId) => {
  let accessToken = ensureLogin();

    app.ports.syncStatus.send("Downloading...");
    const res = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`, {
        headers: { Authorization: `Bearer ${accessToken}` }
    });
    const remoteData = await res.json();

    await overwriteNotebook(remoteData);

    // Update local modified to match remote
    const metaRes = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?fields=modifiedTime`, {
        headers: { Authorization: `Bearer ${accessToken}` }
    });
    const meta = await metaRes.json();
    localStorage.setItem('local_modified', new Date(meta.modifiedTime).getTime().toString());

    app.ports.syncStatus.send("Synced successfully!");
};


export const requestSignIn = () => {
  if (tokenClient) tokenClient.requestAccessToken();
};

export const requestSignOut = () => {
  const token = localStorage.getItem('access_token');
  if (token && getGoogle()?.accounts?.oauth2) {
    getGoogle().accounts.oauth2.revoke(token, () => {});
  }
  localStorage.removeItem('access_token');
  localStorage.removeItem('expires_at');
};

export const syncDatabase = async (app) => {
  let accessToken = ensureLogin();
  if (!accessToken) {
    app.ports.syncStatus.send("Sign in required.");
    return;
  }

  app.ports.syncStatus.send("Syncing...");

  try {
    const db = await dbPromise;
    // Ensure localModified is a number
    const localModified = parseInt(localStorage.getItem('local_modified') || '0', 10);

    // A. Check for existing file in appDataFolder
    const searchRes = await fetch(
        BACKUP_FILE,
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
