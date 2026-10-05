import test from 'node:test';
import assert from 'node:assert/strict';
import {ensembleResult,failedResult,CLASSES} from '../src/core.mjs';
import {stations,POSES,temporal} from '../src/sequence.mjs';
import {buildLocalReport,validStoredSession} from '../src/session.mjs';
import {LocalSessionStore,MemoryDriver,STORAGE_LIMITS} from '../src/storage.mjs';

const version='local-test-1';
const context={model_version:version,recovery_method:'standard',mean_visibility:.9,inference_ms:10};
function decision(classIndex,disagreement=false){return ensembleResult([0,1,2].map((_,seed)=>Array.from({length:8},(_,i)=>i===(disagreement&&seed===1?(classIndex+1)%8:classIndex)?8:0)),context);}
function sample(pose,index){const classIndex=POSES.indexOf(pose);return {frame_id:'frame_'+index,timestamp_ms:index*250,sequence_index:index,result:decision(classIndex)};}
const stationPoses={standing_after_ruku:'standing',sujood_first:'sujood',sujood_second:'sujood',intermediate_sitting:'sitting',final_sitting:'sitting'};
const samples=prayer=>stations(prayer).flat().map((station,i)=>sample(stationPoses[station]??station,i));
const input=(id='session_1')=>{const report=buildLocalReport('demo',samples('demo'),{analysis_id:id});return {id,model_version:version,report,predictions:report.predictions,evidence:[{id:'frame_0',bytes:new Uint8Array([255,216,255,217])}]};};

test('all six local reports retain backend schema, raw sequence, evidence selection and all three predictions',()=>{
 for(const prayer of ['fajr','dhuhr','asr','maghrib','isha','demo']){
  const report=buildLocalReport(prayer,samples(prayer));
  assert.equal(report.schema_version,'1.0');assert.equal(report.analysis_mode,'local');assert.equal(report.synthetic,false);assert.equal(report.status,'COMPLETED');
  assert.equal(report.overall_result,'OBSERVED_COMPLETE');assert.equal(report.observed_rakahs,report.expected_rakahs);
  assert.equal(report.metrics.processed_frames,samples(prayer).length);
  for(const event of report.events){assert.equal(event.evidence_id,event.representative_frame_id);assert.equal(report.predictions[event.evidence_id].individual_models.length,3);}
  for(const row of report.rakahs)for(const station of row.stations){assert.ok(report.predictions[station.evidence_id]);assert.ok(station.event_id);}
 }
});
test('temporal selection keeps first maximum tie and explicit gaps; sorts timestamps and validates sequence indexes',()=>{
 const first=sample('standing',0),second={...sample('standing',1),result:decision(0)},third=sample('ruku',2);
 const events=temporal([third,second,first]);assert.equal(events[0].representative_frame_id,'frame_0');assert.equal(events[0].candidate_timestamp_ms,0);
 const gaps=temporal([first,{...third,timestamp_ms:1501}]);assert.equal(gaps[1].observation_status,'uncertain');assert.equal(gaps[1].representative_frame_id,null);
 assert.throws(()=>temporal([first,{...second,sequence_index:0}]),/INVALID_TIMESTAMP_ORDER/);
 assert.throws(()=>temporal([first,{...second,timestamp_ms:0}]),/INVALID_TIMESTAMP_ORDER/);
});
test('local reports retain uncertainty and differing individual decisions without inventing validity',()=>{
 const list=samples('demo');list[0].result=decision(1,true);
 const report=buildLocalReport('demo',list);
 assert.deepEqual(report.uncertainty.classifier_disagreements,['frame_0']);assert.equal(report.predictions.frame_0.individual_models[1].predicted_action,CLASSES[2]);
 list[2].result=failedResult(context);const uncertain=buildLocalReport('demo',list);
 assert.equal(uncertain.overall_result,'REVIEW_REQUIRED');assert.equal(uncertain.rakahs[0].stations.find(s=>s.station==='ruku').status,'UNCONFIRMED');
 assert.deepEqual(uncertain.uncertainty.unavailable_individual_results,['frame_2']);assert.equal(uncertain.predictions.frame_2.individual_models.length,3);
 assert.equal(uncertain.events.find(e=>e.start_ms===500).evidence_id,null);
 const broken=samples('demo');delete broken[0].result.individual_models;assert.throws(()=>buildLocalReport('demo',broken),/INVALID_PREDICTION_SCHEMA/);
});
test('IndexedDB service contract persists typed evidence, exports locally, and deletes metadata and evidence together',async()=>{
 const driver=new MemoryDriver(),store=new LocalSessionStore(driver);await store.initialize(version);await store.saveSession(input());
 const session=await store.loadSession('session_1');assert.ok(validStoredSession(session,version));assert.deepEqual(session.evidenceIds,['frame_0']);
 assert.deepEqual(await store.loadEvidence('session_1','frame_0'),new Uint8Array([255,216,255,217]));assert.equal((await store.listSessions()).length,1);
 const exported=JSON.parse(await store.exportSession('session_1'));assert.equal(exported.evidence[0].jpeg_base64,'/9j/2Q==');
 await store.deleteSession('session_1');assert.equal(await store.loadSession('session_1'),null);assert.equal((await driver.read('evidence')).length,0);
});
test('model/schema changes invalidate sessions and evidence, including stale objects lacking individual_models',async()=>{
 const driver=new MemoryDriver(),store=new LocalSessionStore(driver);await store.initialize(version);await store.saveSession(input());
 const record=await driver.read('sessions','session_1');delete record.predictions.frame_0.individual_models;await driver.commit([{table:'sessions',key:'session_1',value:record}]);
 await store.initialize(version);assert.equal((await store.listSessions()).length,0);assert.equal((await driver.read('evidence')).length,0);
 await store.saveSession(input());await store.initialize('new-model');assert.equal((await store.listSessions()).length,0);assert.equal((await driver.read('evidence')).length,0);
 await assert.rejects(store.saveSession(input()),/INVALID_PREDICTION_SCHEMA/);
});
test('local history quotas reject saving without deleting existing sessions or evidence',async()=>{
 const driver=new MemoryDriver(),store=new LocalSessionStore(driver);await store.initialize(version);
 for(let i=0;i<STORAGE_LIMITS.max_sessions;i++)await store.saveSession(input('session_'+i));
 await assert.rejects(store.saveSession(input('overflow')),/LOCAL_SESSION_LIMIT/);assert.equal((await store.listSessions()).length,10);
 const record=await driver.read('sessions','session_0');record.evidence_bytes=STORAGE_LIMITS.max_evidence_bytes;await driver.commit([{table:'sessions',key:record.id,value:record}]);
 await assert.rejects(store.saveSession(input('session_1')),/LOCAL_STORAGE_LIMIT/);assert.equal((await store.listSessions()).length,10);assert.equal((await driver.read('evidence')).length,10);
});
