import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {temporal,sequenceReport} from '../src/sequence.mjs';
test('72 complete temporal, candidate frame and review placement cases match Python raw defaults',()=>{
 const cases=JSON.parse(readFileSync(new URL('fixtures/local_report.json',import.meta.url),'utf8'));
 for(const item of cases){
  const report=sequenceReport(item.prayer,temporal(item.samples)),expected=item.expected;
  assert.equal(report.overall_result,expected.overall_result);assert.equal(report.observed_rakahs,expected.observed_rakahs);
  assert.deepEqual(report.rakahs,expected.rakahs,item.prayer+' station confidence/timestamps');
  const fields=['event_id','pose','start_ms','end_ms','confidence','representative_frame_id','candidate_pose','candidate_confidence','candidate_timestamp_ms','observation_status','evidence_id','review_rakah_number','review_before_station_index'];
  const project=events=>events.map(event=>Object.fromEntries(fields.map(field=>[field,event[field]??null])));
  assert.deepEqual(project(report.events),project(expected.events),item.prayer+' temporal/candidate/review');
  assert.deepEqual(report.unexpected_movements,expected.unexpected_movements,item.prayer+' ambiguous review placement');
 }
});
