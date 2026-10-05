import test from 'node:test';
import assert from 'node:assert/strict';
import { RecognizerClient } from '../src/client.mjs';

test('slow initialization forwards progress without the inference deadline or a second worker', async () => {
  const saved = { Worker:globalThis.Worker, OffscreenCanvas:globalThis.OffscreenCanvas, setTimeout:globalThis.setTimeout };
  let worker, workers = 0;
  const timers = [], progress = [];
  try {
    globalThis.OffscreenCanvas = class {};
    globalThis.Worker = class { constructor(){ worker=this;workers++; } postMessage(message){this.last=message;} };
    globalThis.setTimeout = (...args) => {timers.push(args[1]);return saved.setTimeout(...args);};
    const client = new RecognizerClient('https://device.test/', p=>progress.push(p));
    const ready = client.initialize();
    worker.onmessage({data:{id:worker.last.id,progress:{phase:'downloading',loaded:1024,total:2048}}});
    assert.deepEqual(timers, []);
    assert.equal(progress[0].loaded,1024);
    worker.onmessage({data:{id:worker.last.id,value:{model_version:'v'}}});
    assert.equal((await ready).mode,'worker');
    assert.equal(workers,1);
    const inference = client.call('features',{});
    assert.deepEqual(timers,[120000]);
    worker.onmessage({data:{id:worker.last.id,value:{ok:true}}});
    assert.deepEqual(await inference,{ok:true});
  } finally {Object.assign(globalThis,saved);}
});
