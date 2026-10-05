import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { featuresFromLandmarks, softmax, averageProbabilities, decision, CLASSES, SEEDS, SCHEMA_VERSION, ensembleResult, failedResult, validResult, readSession, saveSession, StableCapture } from '../src/core.mjs';
import { stations, temporal, sequenceReport, POSES } from '../src/sequence.mjs';
const json = file => JSON.parse(readFileSync(new URL(file, import.meta.url), 'utf8'));
const unit = { mean: Array(165).fill(0), std: Array(165).fill(1) };
const landmarks = Array.from({ length: 33 }, (_, i) => ({ x: i / 33, y: i < 23 ? .2 : .7, z: -.1, visibility: .9, presence: .8 }));
const context = { model_version: 'test-v1', recovery_method: 'standard', mean_visibility: .9, inference_ms: 10 };
const logits = [[8,0,0,0,0,0,0,0],[0,9,0,0,0,0,0,0],[7,0,0,0,0,0,0,0]];
const result = () => ensembleResult(logits, context);
test('166 features: hip origin, XY scale, XYZ/visibility/presence ordering and valid flag', () => {
  const x = featuresFromLandmarks(landmarks, unit); assert.equal(x.length, 166); assert.equal(x[165], 1);
  assert.ok(Math.abs(x[23*3] + x[24*3]) < 1e-6); assert.equal(x[2], 0);
  assert.equal(x[99], Math.fround(.9)); assert.equal(x[132], Math.fround(.8));
});
test('invalid, nonfinite, degenerate and missing landmarks rejected', () => {
  assert.equal(featuresFromLandmarks([], unit), null);
  assert.equal(featuresFromLandmarks(Array(33).fill({ x: 0, y: 0, z: 0 }), unit), null);
  for (const field of ['x', 'y', 'z', 'visibility', 'presence']) { const copy = structuredClone(landmarks); copy[0][field] = NaN; assert.equal(featuresFromLandmarks(copy, unit), null); }
});
test('standardization uses float32 at each operation', () => {
  const raw = featuresFromLandmarks(landmarks, unit), p = { mean: Array(165).fill(.123456789), std: Array(165).fill(.234567891) };
  const x = featuresFromLandmarks(landmarks, p);
  assert.equal(x[0], Math.fround(Math.fround(raw[0] - Math.fround(p.mean[0])) / Math.fround(p.std[0])));
});
test('softmax is stable on extreme logits and sums to one', () => {
  const p = softmax([1000, 999, -1000, 0, 0, 0, 0, 0]); assert.ok(Math.abs(p.reduce((a,b)=>a+b)-1)<1e-12); assert.ok(p[0]>p[1]);
  assert.throws(() => softmax([NaN]));
});
test('ensemble is arithmetic mean of separate softmax arrays; disagreement retained', () => {
  const r = result(); assert.equal(r.individual_models.length, 3); assert.equal(r.class_index, 0); assert.equal(r.individual_models[1].class_index, 1); assert.equal(r.classifier_disagreement, true);
  CLASSES.forEach((c, i) => assert.equal(r.probabilities[c], logits.map(softmax).reduce((s,p)=>s+p[i],0)/3));
  assert.equal(r.predicted_action, CLASSES[r.class_index]); assert.deepEqual(r.individual_models.map(m=>m.seed), SEEDS);
  assert.throws(() => averageProbabilities([[1],[1]]));
});
test('class ordering exact and all individual top3 decisions present', () => {
  const r = result(); assert.deepEqual(Object.keys(r.probabilities), CLASSES); r.individual_models.forEach(m => assert.equal(m.top3.length,3));
  assert.equal(CLASSES[6],'7_Salam_Right'); assert.equal(CLASSES[7],'8_Salam_Left');
});
test('invalid pose has exactly three explicit unavailable decisions', () => {
  const r = failedResult(context); assert.equal(r.individual_models.length,3); assert.ok(r.warning); assert.ok(validResult(r,context.model_version));
});
test('cached decisions require unit-sum distributions, valid visibility and fully empty unavailable slots',()=>{
  for(const distribution of [Array(8).fill(0),Array(8).fill(.25)]){
    const invalid={...result(),...decision(distribution),individual_models:SEEDS.map(seed=>({seed,...decision(distribution)}))};
    assert.equal(validResult(invalid,context.model_version),false);
  }
  for(const field of ['class_index','confidence','probabilities','top3']){
    const invalid=failedResult(context);invalid.individual_models[0]={...invalid.individual_models[0],[field]:field==='class_index'?0:field==='confidence'?.2:field==='probabilities'?{[CLASSES[0]]:1}:[{action:CLASSES[0],probability:1}]};
    assert.equal(validResult(invalid,context.model_version),false);
  }
  for(const invalid of [{...result(),mean_visibility:NaN},{...result(),mean_visibility:1.1},{...result(),inference_ms:Infinity},{...result(),recovery_method:'unknown'},{...failedResult(context),warning:null}])assert.equal(validResult(invalid,context.model_version),false);
});
test('schema/model version and absent individual results invalidate cached sessions', () => {
  let value; const storage = { getItem:()=>value, setItem:(_,v)=>{value=v;}, removeItem:()=>{value=null;} };
  saveSession(storage,context.model_version,[result()]); assert.equal(readSession(storage,context.model_version).length,1);
  assert.deepEqual(readSession(storage,'new-model'),[]); assert.equal(value,null);
  for (const r of [{...result(),schema_version:'old'}, {...result(),individual_models:undefined}, {...result(),individual_models:result().individual_models.slice(1)}]) {
    value=JSON.stringify({schema_version:SCHEMA_VERSION,model_version:context.model_version,results:[r]}); assert.deepEqual(readSession(storage,context.model_version),[]); assert.equal(value,null);
  }
});
test('three confident matches, cooldown, dedup and low-confidence reset preserved', () => {
  const stable = new StableCapture(.7), r = {...result(),confidence:.9};
  assert.equal(stable.update(r,5),false); assert.equal(stable.update(r,5.3),false); assert.equal(stable.update(r,5.6),true); assert.equal(stable.update(r,10),false);
  const other={...r,predicted_action:CLASSES[1]}; stable.update(other,11); stable.update({...r,confidence:.2},11.2);
  assert.equal(stable.update(other,12),false); assert.equal(stable.update(other,12.3),false); assert.equal(stable.update(other,12.6),true);
});
test('strict local sequence preserves all mandatory stations and uncertainty', () => {
  for (const prayer of ['fajr','dhuhr','asr','maghrib','isha','demo']) assert.equal(stations(prayer).at(-1).at(-1),'salam_left');
  const poses=['takbir','standing','ruku','standing','sujood','sitting','sujood','sitting','salam_right','salam_left'];
  const events=poses.map((pose,i)=>({pose,event_id:String(i),observation_status:'detected',start_ms:i*500,end_ms:i*500,confidence:.9}));
  assert.equal(sequenceReport('demo',events).overall_result,'OBSERVED_COMPLETE');
  assert.equal(sequenceReport('demo',events.filter(e=>e.pose!=='ruku')).overall_result,'REVIEW_REQUIRED');
  assert.equal(sequenceReport('demo',events.filter(e=>e.pose==='sujood').slice(0,1)).rakahs[0].stations.filter(s=>s.status==='DETECTED').length,0);
});
test('temporal gaps and low confidence remain uncertain',()=>{
  const r={...result(),confidence:.9}; const events=temporal([{timestamp_ms:1,result:r},{timestamp_ms:200,result:r},{timestamp_ms:1500,result:{...r,confidence:.2}}]);
  assert.equal(events.length,3); assert.equal(events[1].observation_status,'uncertain');
});
test('Python identical-landmark reference fixtures',()=>{
  const cases=json('fixtures/landmarks.json'), preprocessing=json('../assets/preprocessing.json');
  for(const c of cases){const actual=featuresFromLandmarks(c.landmarks,preprocessing); c.features.forEach((expected,i)=>assert.ok(Math.abs(actual[i]-expected)<=2e-5+2e-6*Math.abs(expected),`feature ${i}: ${actual[i]} vs ${expected}`));}
});
