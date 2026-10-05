import { createHash } from 'node:crypto';
// tasks-vision 0.10.32 drops field 5 (presence) in its public JS converter,
// although PoseLandmarker emits it in NormalizedLandmarkList. Preserve it before
// conversion; never approximate presence with visibility or a constant.
// See upstream landmark_result.ts and framework/formats/landmark.proto.
export function preservePresence(source) {
  const hash = createHash('sha256').update(source).digest('hex');
  if (hash !== 'de83c48ff329717a27aeb528d5ef5f47f077c628a5302dc483aca5b513e7464b') throw Error('MediaPipe source changed: inspect and validate the presence adapter before updating');
  const original = 'function Yo(t){const e=[];for(const n of An(t,Ls,1))e.push({x:Fn(n,1)??0,y:Fn(n,2)??0,z:Fn(n,3)??0,visibility:Fn(n,4)??0});return e}';
  if (source.split(original).length !== 2) throw Error('Normalized landmark converter not found exactly once');
  return source.replace(original, original.replace('visibility:Fn(n,4)??0', 'visibility:Fn(n,4)??0,presence:Fn(n,5)??0'));
}
