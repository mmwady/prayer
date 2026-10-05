import { SCHEMA_VERSION } from './core.mjs';
import { SESSION_SCHEMA_VERSION, validStoredSession } from './session.mjs';

const TABLES = ['meta','sessions','evidence','references'];
export const STORAGE_LIMITS = Object.freeze({ max_sessions: 10, max_evidence_bytes: 128 * 1024 * 1024 });
export class IndexedDbDriver {
  async open() {
    if (!globalThis.indexedDB) throw Error('LOCAL_STORAGE_UNAVAILABLE');
    this.db = await new Promise((resolve,reject) => {
      const request = indexedDB.open('iqtadi-local-prayer',1);
      request.onupgradeneeded = () => { for (const table of TABLES) if (!request.result.objectStoreNames.contains(table)) request.result.createObjectStore(table); };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(Error('LOCAL_STORAGE_BLOCKED: close older application tabs'));
    });
    this.db.onversionchange = () => this.db.close();
  }
  read(table,key) {
    return new Promise((resolve,reject) => { const transaction = this.db.transaction(table,'readonly');
      const request = key === undefined ? transaction.objectStore(table).getAll() : transaction.objectStore(table).get(key);
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
  }
  commit(operations) {
    return new Promise((resolve,reject) => {
      const transaction = this.db.transaction([...new Set(operations.map(o => o.table))],'readwrite');
      transaction.oncomplete = () => resolve(); transaction.onerror = () => reject(transaction.error); transaction.onabort = () => reject(transaction.error ?? Error('LOCAL_STORAGE_ABORTED'));
      for (const op of operations) { const table = transaction.objectStore(op.table);
        if (op.action === 'clear') table.clear(); else if (op.action === 'delete') table.delete(op.key); else table.put(op.value,op.key); }
    });
  }
  close() { this.db?.close(); }
}

// Injected only by unit tests; production explicitly reports denied persistent storage.
export class MemoryDriver {
  constructor() { this.tables = Object.fromEntries(TABLES.map(t => [t,new Map()])); }
  async open() {}
  async read(table,key) { return structuredClone(key === undefined ? [...this.tables[table].values()] : this.tables[table].get(key)); }
  async commit(operations) { for (const op of operations) { const table = this.tables[op.table];
    if (op.action === 'clear') table.clear(); else if (op.action === 'delete') table.delete(op.key); else table.set(op.key,structuredClone(op.value)); } }
  close() {}
}

export class LocalSessionStore {
  constructor(driver = new IndexedDbDriver()) { this.driver = driver; }
  async initialize(version) {
    if (!version) throw Error('MODEL_VERSION_REQUIRED');
    await this.driver.open(); this.version = version;
    const meta = await this.driver.read('meta','version');
    if (meta?.model_version !== version || meta?.schema_version !== SESSION_SCHEMA_VERSION || meta?.prediction_schema_version !== SCHEMA_VERSION) {
      await this.driver.commit([{table:'sessions',action:'clear'},{table:'evidence',action:'clear'},
        {table:'meta',key:'version',value:{model_version:version,schema_version:SESSION_SCHEMA_VERSION,prediction_schema_version:SCHEMA_VERSION}}]);
    }
    // Also invalidate corrupted/legacy objects even when their version headers survived.
    for (const session of await this.driver.read('sessions')) if (!validStoredSession(session,version)) await this.deleteSession(session.id);
    return {storage_available:true,storage_limits:STORAGE_LIMITS};
  }
  async saveSession(input) {
    if (!this.version) throw Error('LOCAL_STORAGE_NOT_INITIALIZED');
    if (!/^[a-zA-Z0-9_-]{1,128}$/.test(input.id ?? '')) throw Error('INVALID_SESSION_ID');
    const existing = await this.driver.read('sessions',input.id);
    const session = { id:input.id,model_version:input.model_version,report:input.report,
      predictions:input.predictions ?? input.report?.predictions,schema_version:SCHEMA_VERSION,storage_schema_version:SESSION_SCHEMA_VERSION,report_schema_version:'1.0',
      prediction_schema_version:SCHEMA_VERSION,created_at:existing?.created_at ?? new Date().toISOString(),
      evidenceIds:[],evidence_bytes:0 };
    if (!validStoredSession(session,this.version)) throw Error('INVALID_PREDICTION_SCHEMA: cannot persist missing individual models or incompatible versions');
    const evidence = input.evidence ?? [], ids = new Set();
    for (const item of evidence) {
      if (!/^[a-zA-Z0-9_-]{1,64}$/.test(item.id ?? '') || ids.has(item.id)) throw Error('INVALID_EVIDENCE_ID');
      ids.add(item.id);
      const bytes = item.bytes instanceof Uint8Array ? item.bytes : new Uint8Array(item.bytes);
      if (!bytes.byteLength) throw Error('EMPTY_EVIDENCE');
      session.evidenceIds.push(item.id); session.evidence_bytes += bytes.byteLength;
    }
    const all = await this.driver.read('sessions');
    if (!existing && all.length >= STORAGE_LIMITS.max_sessions) throw Error('LOCAL_SESSION_LIMIT: export or delete a saved session first');
    if (session.evidence_bytes + all.filter(s => s.id !== input.id).reduce((n,s) => n + s.evidence_bytes,0) > STORAGE_LIMITS.max_evidence_bytes) throw Error('LOCAL_STORAGE_LIMIT: export or delete evidence first');
    const operations = (existing?.evidenceIds ?? []).map(id => ({table:'evidence',action:'delete',key:input.id+'/'+id}));
    for (const item of evidence) operations.push({table:'evidence',key:input.id+'/'+item.id,value:{session_id:input.id,id:item.id,bytes:new Uint8Array(item.bytes)}});
    operations.push({table:'sessions',key:input.id,value:session});
    await this.driver.commit(operations); return session;
  }
  async listSessions() {
    const sessions = await this.driver.read('sessions');
    return sessions.filter(s => validStoredSession(s,this.version)).sort((a,b) => b.created_at.localeCompare(a.created_at))
      .map(s => ({...s,prayer:s.report.prayer,overall_result:s.report.overall_result}));
  }
  async loadSession(id) {
    const session = await this.driver.read('sessions',id);
    if (!session) return null;
    if (!validStoredSession(session,this.version)) { await this.deleteSession(id); return null; }
    return session;
  }
  async loadEvidence(id,evidenceId) {
    const session = await this.loadSession(id);
    if (!session?.evidenceIds.includes(evidenceId)) throw Error('EVIDENCE_UNAVAILABLE');
    const item = await this.driver.read('evidence',id+'/'+evidenceId);
    if (!item) throw Error('EVIDENCE_UNAVAILABLE'); return new Uint8Array(item.bytes);
  }
  async deleteSession(id) {
    const session = await this.driver.read('sessions',id);
    const operations = (session?.evidenceIds ?? []).map(e => ({table:'evidence',action:'delete',key:id+'/'+e}));
    operations.push({table:'sessions',action:'delete',key:id}); await this.driver.commit(operations);
  }
  async exportSession(id) {
    const session = await this.loadSession(id); if (!session) throw Error('SESSION_NOT_FOUND');
    const evidence = [];
    for (const evidenceId of session.evidenceIds) {
      const bytes = await this.loadEvidence(id,evidenceId); let binary='';
      for (let offset=0; offset<bytes.length; offset+=8192) binary += String.fromCharCode(...bytes.subarray(offset,offset+8192));
      evidence.push({id:evidenceId,jpeg_base64:btoa(binary)});
    }
    return JSON.stringify({...session,evidence},null,2);
  }
  close() { this.driver.close(); }
}
