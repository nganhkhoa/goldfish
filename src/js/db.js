const { openDB } = window.idb;

export const DB_NAME = 'Dictionary';
export const DB_VERSION = 4;
export const NOTEBOOK_STORE_NAME = 'note';
export const CN_STORE_NAME = 'cn';
export const KR_STORE_NAME = 'ko';
export const JP_STORE_NAME = 'jp';

const LOCAL_STORAGE_DICTIONARY_KEY = 'dict_db_loaded';
const DICTIONARY_INSTALL_VERSION_KEY = 'dict_install_version';
const DICTIONARY_DATA_VERSION = '4';

const DICTIONARY_PATH_ROOT = '/goldfish/';
// Full dictionaries are generated from resources/ and served compressed.
const DICTIONARY_PATH_CHINESE = `${DICTIONARY_PATH_ROOT}/cn.json.gz`;
const DICTIONARY_PATH_JAPANESE = `${DICTIONARY_PATH_ROOT}/jp.json.gz`;
const DICTIONARY_PATH_KOREAN = `${DICTIONARY_PATH_ROOT}/ko.json.gz`;

const canonicalLanguage = (language) => language === 'ja' ? 'jp' : language;

const languageToDictionary = {
  'cn': CN_STORE_NAME,
  'jp': JP_STORE_NAME,
  'ja': JP_STORE_NAME,
  'ko': KR_STORE_NAME,
  'kr': KR_STORE_NAME,
};

const initDB = async () => {
  return openDB(DB_NAME, DB_VERSION, {
    upgrade(db, oldVersion, newVersion, transaction) {
      const options = { keyPath: 'id', autoIncrement: true };
      if (!db.objectStoreNames.contains(CN_STORE_NAME)) db.createObjectStore(CN_STORE_NAME, options);
      if (!db.objectStoreNames.contains(JP_STORE_NAME)) db.createObjectStore(JP_STORE_NAME, options);
      if (!db.objectStoreNames.contains(KR_STORE_NAME)) db.createObjectStore(KR_STORE_NAME, options);

      let nbStore;
      if (!db.objectStoreNames.contains(NOTEBOOK_STORE_NAME)) {
        nbStore = db.createObjectStore(NOTEBOOK_STORE_NAME, options);
      } else {
        nbStore = transaction.objectStore(NOTEBOOK_STORE_NAME);
      }
      if (!nbStore.indexNames.contains('language')) nbStore.createIndex('language', 'language', { unique: false });
      if (!nbStore.indexNames.contains('word_id')) nbStore.createIndex('word_id', 'word_id', { unique: false });
      if (!nbStore.indexNames.contains('language_word')) {
        nbStore.createIndex('language_word', ['language', 'word_id'], { unique: true });
      }
      if (!nbStore.indexNames.contains('language_word_id')) {
        nbStore.createIndex('language_word_id', ['language', 'word_id'], { unique: false });
      }
    },
  });
};

export const database = initDB();
const dbPromise = database;

export const overwriteNotebook = async (remoteData) => {
    const db = await database;
    const tx = db.transaction([NOTEBOOK_STORE_NAME], 'readwrite');
    const store = tx.objectStore(NOTEBOOK_STORE_NAME);

    await store.clear();
    for (const entry of remoteData) {
        await store.put(entry);
    }
    await tx.done;
};

export const getNotebook = async () => {
  const notebook = await db.getAll(NOTEBOOK_STORE_NAME);
  return notebook;
}

export const getNotebookEntries = async () => {
  const db = await dbPromise;
  const notebookRecords = await db.getAll(NOTEBOOK_STORE_NAME);
  const fallbackCaches = new Map();
  const findDictionaryWord = async (storeName, wordId) => {
    const direct = await db.get(storeName, wordId);
    if (direct) return direct;
    // Cache the promise immediately so concurrent notebook rows do not each
    // start a separate 100k+ record scan.
    if (!fallbackCaches.has(storeName)) fallbackCaches.set(storeName, db.getAll(storeName));
    const records = await fallbackCaches.get(storeName);
    return records.find(word =>
      String(word.id) === String(wordId)
      || (storeName === CN_STORE_NAME && (word.simplified === String(wordId) || word.traditional === String(wordId)))
    );
  };
  const joinedEntries = await Promise.all(notebookRecords.map(async (nb) => {
    let storeName = languageToDictionary[nb.language];
    if (!storeName) return null;

    const dictWord = await findDictionaryWord(storeName, nb.word_id);
    if (!dictWord) return null;

    return {
      notebook_id: nb.id,
      card_key: `${nb.language}:${nb.word_id}`,
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

export async function updateCardStats(notebookIdStr, newLevel, interval, easeFactor, nextReview) {
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

const normalizeSearch = (value) => String(value || '').toLowerCase().trim();

// Pinyin sources commonly store syllable separators and tone numbers
// (for example, "hui4 he2"). Users naturally type "huihe", so compare a
// compact form as well as the original text.
const compactSearch = (value) => normalizeSearch(value)
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .replace(/[0-9\s'\-·]/g, '');

// Convert Japanese kana to a searchable romaji form. This intentionally keeps
// the conversion local and dependency-free so the app remains offline.
const kanaToRomaji = (value) => {
  const table = {
    'あ':'a','い':'i','う':'u','え':'e','お':'o','か':'ka','き':'ki','く':'ku','け':'ke','こ':'ko','さ':'sa','し':'shi','す':'su','せ':'se','そ':'so','た':'ta','ち':'chi','つ':'tsu','て':'te','と':'to','な':'na','に':'ni','ぬ':'nu','ね':'ne','の':'no','は':'ha','ひ':'hi','ふ':'fu','へ':'he','ほ':'ho','ま':'ma','み':'mi','む':'mu','め':'me','も':'mo','や':'ya','ゆ':'yu','よ':'yo','ら':'ra','り':'ri','る':'ru','れ':'re','ろ':'ro','わ':'wa','を':'wo','ん':'n','が':'ga','ぎ':'gi','ぐ':'gu','げ':'ge','ご':'go','ざ':'za','じ':'ji','ず':'zu','ぜ':'ze','ぞ':'zo','だ':'da','ぢ':'ji','づ':'zu','で':'de','ど':'do','ば':'ba','び':'bi','ぶ':'bu','べ':'be','ぼ':'bo','ぱ':'pa','ぴ':'pi','ぷ':'pu','ぺ':'pe','ぽ':'po','ー':'-','っ':'','ゃ':'ya','ゅ':'yu','ょ':'yo'
  };
  const pairs = { 'きゃ':'kya','きゅ':'kyu','きょ':'kyo','しゃ':'sha','しゅ':'shu','しょ':'sho','ちゃ':'cha','ちゅ':'chu','ちょ':'cho','にゃ':'nya','にゅ':'nyu','にょ':'nyo','ひゃ':'hya','ひゅ':'hyu','ひょ':'hyo','みゃ':'mya','みゅ':'myu','みょ':'myo','りゃ':'rya','りゅ':'ryu','りょ':'ryo','ぎゃ':'gya','ぎゅ':'gyu','ぎょ':'gyo','じゃ':'ja','じゅ':'ju','じょ':'jo','びゃ':'bya','びゅ':'byu','びょ':'byo','ぴゃ':'pya','ぴゅ':'pyu','ぴょ':'pyo' };
  let result = '';
  for (let i = 0; i < value.length; i += 1) {
    const pair = value.slice(i, i + 2);
    if (pairs[pair]) { result += pairs[pair]; i += 1; continue; }
    result += table[value[i]] || value[i];
  }
  return result;
};

// Revised-Romanization-style conversion for Hangul syllables.
const koreanToRoman = (value) => {
  const initials = ['g','kk','n','d','tt','r','m','b','pp','s','ss','','j','jj','ch','k','t','p','h'];
  const vowels = ['a','ae','ya','yae','eo','e','yeo','ye','o','wa','wae','oe','yo','u','wo','we','wi','yu','eu','ui','i'];
  const finals = ['','k','k','ks','n','nj','nh','t','l','lk','lm','lb','ls','lt','lp','lh','m','p','ps','t','t','ng','t','k','t','p','h'];
  return [...value].map(char => {
    const code = char.charCodeAt(0) - 0xac00;
    if (code < 0 || code > 11171) return char;
    return initials[Math.floor(code / 588)] + vowels[Math.floor((code % 588) / 28)] + finals[code % 28];
  }).join('');
};

const searchableFields = (entry, targetLang, includeEnglish) => {
  if (targetLang === 'cn') return [entry.simplified, entry.traditional, entry.pinyin].concat(includeEnglish ? [entry.meaning] : []);
  if (targetLang === 'jp' || targetLang === 'ja') return [entry.word, entry.furigana, ...(entry.alternatives || []), kanaToRomaji(entry.furigana)].concat(includeEnglish ? [entry.meaning] : []);
  return [entry.word, koreanToRoman(entry.word)].concat(includeEnglish ? [entry.meaning] : []);
};

export const searchWords = async (query, targetLang, includeEnglish = false) => {
  const db = await dbPromise;

  if (!query || !query.trim()) return [];
  const lowerQuery = normalizeSearch(query);

  // 1. Dynamically select the correct store
  let storeName = languageToDictionary[targetLang];
  if (!storeName) {
    throw new Error(`Unknown language store: ${targetLang}`);
  }

  const allEntries = await db.getAll(storeName);
  const compactQuery = compactSearch(query);
  const filteredWords = allEntries.filter(entry =>
    searchableFields(entry, targetLang, includeEnglish).some(field => {
      const value = normalizeSearch(field);
      return value.includes(lowerQuery) || compactSearch(value).includes(compactQuery);
    })
  );

  // 4. Sort by closest string match
  return filteredWords.sort((a, b) => {
    // Helper to get the best (lowest) distance score for a single entry
    const getBestScore = (entry) => {
      const scores = searchableFields(entry, targetLang, includeEnglish)
        .filter(Boolean)
        .flatMap(field => [
          getEditDistance(lowerQuery, normalizeSearch(field)),
          getEditDistance(compactQuery, compactSearch(field))
        ]);
      return Math.min(...scores);
    };

    // Compare the best score of entry A against entry B
    return getBestScore(a) - getBestScore(b);
  });
};

export const addToNotebook = async (language, wordId, referenceStringId = null) => {
  const db = await dbPromise;
  language = canonicalLanguage(language);
  const existing = await db.getFromIndex(NOTEBOOK_STORE_NAME, 'language_word', [language, wordId]);
  if (existing) return existing.id;

  const entry = {
    language: language,
    word_id: wordId,
    reference_string_id: referenceStringId,
    memory_level: 0,
    date_added: new Date().toISOString(),
    tags: []
  };

  return db.add(NOTEBOOK_STORE_NAME, entry);
};

export const removeFromNotebookByWordId = async (language, wordId) => {
  const db = await dbPromise;
  language = canonicalLanguage(language);

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

// Helper to strip quotes (matches your OCaml strip_quotes)
const stripQuotes = (s) => {
    let clean = s.trim();
    if (clean.length >= 2 && clean.startsWith('"') && clean.endsWith('"')) {
        return clean.substring(1, clean.length - 1);
    }
    return clean;
};

// Translating your OCaml Parsers
const fetchCompressedJson = async (path) => {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`Failed to fetch dictionary ${path}: ${response.status}`);

  // Some production servers serve .gz as a raw file without the
  // Content-Encoding header, while development servers transparently decode
  // it. Inspect the magic bytes so both configurations work.
  const bytes = new Uint8Array(await response.arrayBuffer());
  const isGzip = bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
  if (isGzip) {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
    return JSON.parse(await new Response(stream).text());
  }
  return JSON.parse(new TextDecoder().decode(bytes));
};

const parseChinese = (rawText) => {
    return rawText.split('\n').reduce((acc, line) => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('simplified')) return acc;

        const parts = trimmed.split('\t');
        let hsk;
        if (parts[4] === "7-9") {
          hsk = 7;
        } else {
          hsk = parseInt(parts[4], 10);
        }

        if (parts.length >= 5) {
            acc.push({
                id: parts[0],
                simplified: parts[0],
                traditional: parts[1],
                pinyin: parts[2],
                zhuyin: null,
                meaning: parts[3],
                hsk: hsk
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
    const cnData = await fetchCompressedJson(DICTIONARY_PATH_CHINESE);

    reportProgress("Fetching Japanese (JMdict)...");
    const jpData = await fetchCompressedJson(DICTIONARY_PATH_JAPANESE);

    reportProgress("Fetching Korean dictionary...");
    const koData = await fetchCompressedJson(DICTIONARY_PATH_KOREAN);

    reportProgress("Installing to Database. This may take a moment...");
    const db = await dbPromise;

    // Large dictionaries must be written in separate transactions. A single
    // transaction for all three stores can be aborted by the browser due to
    // its size or inactivity timeout, leaving the UI looking stuck.
    const installStore = async (storeName, records, label) => {
      const chunkSize = 1000;
      let firstChunk = true;
      for (let offset = 0; offset < records.length; offset += chunkSize) {
        const chunk = records.slice(offset, offset + chunkSize);
        const tx = db.transaction(storeName, 'readwrite');
        const store = tx.objectStore(storeName);
        if (firstChunk) {
          await store.clear();
          firstChunk = false;
        }
        chunk.forEach(record => store.put(record));
        await tx.done;
        reportProgress(`${label}: ${Math.min(offset + chunk.length, records.length).toLocaleString()} / ${records.length.toLocaleString()}`);
      }
    };

    await installStore(CN_STORE_NAME, cnData, "Chinese");
    await installStore(JP_STORE_NAME, jpData, "Japanese");
    await installStore(KR_STORE_NAME, koData, "Korean");

    localStorage.setItem(LOCAL_STORAGE_DICTIONARY_KEY, "true");
    localStorage.setItem(DICTIONARY_INSTALL_VERSION_KEY, DICTIONARY_DATA_VERSION);
    reportProgress("Complete");
};

const getWordsByLevel = async (language, level) => {
  const db = await dbPromise;

  // 1. Setup the right dictionary store and level key
  let storeName;
  let levelKey;
  switch (language) {
    case "cn": storeName = CN_STORE_NAME; levelKey = "hsk"; break;
    case "ja": case "jp": storeName = JP_STORE_NAME; levelKey = "jlpt"; break;
    case "ko": storeName = KR_STORE_NAME; levelKey = "topik"; break;
    default: return null;
  }

  // 2. "I have a full word list, say chinese words"
  const fullWordList = await db.getAll(storeName);

  // 3. "I want to get out specific level words, full word -> filter by level"
  const specificLevelWords = fullWordList.filter(word => word[levelKey] === level);

  // 4. Get the notebook records
  const notebookRecords = await db.getAll(NOTEBOOK_STORE_NAME);

  // (Optional but highly recommended): Create a quick lookup map of { word_id: notebook_id }
  // so we don't have to loop through the entire notebook for every single word.
  const savedWordsMap = new Map();
  for (const nb of notebookRecords) {
    const isMatchingLang = nb.language === language ||
                           (language === "ja" && nb.language === "jp") ||
                           (language === "jp" && nb.language === "ja");
    if (isMatchingLang) {
      savedWordsMap.set(nb.word_id, nb.id);
    }
  }

  // 5. "Extend the entry with a notebook id if it is already in the notebook"
  const entries = specificLevelWords.map(word => {
    return {
      ...word,
      // If word.id is in the notebook, attach the notebook entry's id, otherwise null
      notebook_id: savedWordsMap.has(word.id) ? savedWordsMap.get(word.id) : null
    };
  });

  return {
    lang: language,
    level: level,
    entries: entries
  };
};

export const getWordsByLevelAsNotebookEntries = async (language, level) => {
  console.log("filter language " + language + " " + level);
  const db = await dbPromise;

  // 1. Setup the right dictionary store and level key
  let storeName;
  let levelKey;
  switch (language) {
    case "cn": storeName = CN_STORE_NAME; levelKey = "hsk"; break;
    case "ja": case "jp": storeName = JP_STORE_NAME; levelKey = "jlpt"; break;
    case "ko": storeName = KR_STORE_NAME; levelKey = "topik"; break;
    default: return null;
  }

  // 2. Get the full word list and filter by level
  const fullWordList = await db.getAll(storeName);
  const specificLevelWords = fullWordList.filter(word => word[levelKey] === level);

  // 3. Get the notebook records
  const notebookRecords = await db.getAll(NOTEBOOK_STORE_NAME);

  // 4. Map word_id -> FULL notebook record (so we get memory_level, interval, etc.)
  const savedWordsMap = new Map();
  for (const nb of notebookRecords) {
    const isMatchingLang = nb.language === language ||
                           (language === "ja" && nb.language === "jp") ||
                           (language === "jp" && nb.language === "ja");
    if (isMatchingLang) {
      savedWordsMap.set(nb.word_id, nb);
    }
  }

  // Dictionary IDs are stable within their language. Unsaved words must not
  // masquerade as notebook records: use the dictionary ID only for the UI.
  const entries = specificLevelWords.map(dictWord => {
    const nb = savedWordsMap.get(dictWord.id);

    return {
      notebook_id: nb ? nb.id : 0,
      card_key: `${canonicalLanguage(language)}:${dictWord.id}`,
      memory_level: nb ? nb.memory_level : 0,       // Default to 0
      lang: language,
      dict_data: dictWord,                          // Store the full dict word object here
      interval: (nb && nb.interval) ? nb.interval : 0,
      easeFactor: (nb && nb.easeFactor) ? nb.easeFactor : 2.5,
      nextReview: (nb && nb.nextReview) ? nb.nextReview : 0
    };
  });

  console.log("found words of " + language + " " + level + " count:" + entries.length);
  return entries;
};
