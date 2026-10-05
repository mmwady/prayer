import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sequenceReport } from '../src/sequence.mjs';
test('96 golden cases match the preserved Python raw sequence validator',()=>{
 const cases=JSON.parse(readFileSync(new URL('fixtures/sequence.json',import.meta.url),'utf8'));
 for(const fixture of cases){const r=sequenceReport(fixture.prayer,fixture.events);
  const projected={overall_result:r.overall_result,observed_rakahs:r.observed_rakahs,
   rakahs:r.rakahs.map(row=>({result:row.result,stations:row.stations.map(s=>({station:s.station,status:s.status,event_id:s.event_id}))})),
   unexpected:r.unexpected_movements.map(e=>({event_id:e.event_id,reason:e.reason}))};
  assert.deepEqual(projected,fixture.expected,fixture.prayer);
 }
});
