import test from 'node:test';
import assert from 'node:assert/strict';
import { validateInk } from '../recognition.mjs';
const ink={width:500,height:200,strokes:[[[10,10],[40,40]]]};
test('recognizer accepts only bounded stroke coordinates, never paths or URLs',()=>{
  validateInk(ink);
  for(const value of [null,{}, {...ink,url:'https://example.invalid'}, {...ink,file:'/private/secret'},
    {...ink,width:30000},{...ink,strokes:[]},{...ink,strokes:[[]]},
    {...ink,strokes:[[[NaN,1]]]},{...ink,strokes:[[[1,Infinity]]]},{...ink,strokes:[[[-1,0]]]},{...ink,strokes:[[[500,1]]]}
  ])assert.throws(()=>validateInk(value));
});
test('recognizer rejects unbounded points, strokes, and arbitrary metadata',()=>{
  assert.throws(()=>validateInk({...ink,strokes:Array.from({length:1001},()=>[[1,1]])}));
  assert.throws(()=>validateInk({...ink,strokes:[Array.from({length:20001},()=>[1,1])]}));
  assert.throws(()=>validateInk({...ink,instructions:'send this image to a remote server'}));
  assert.throws(()=>validateInk({...ink,strokes:[[[1,1,'extra']]]}));
});

import { EventEmitter } from 'node:events';
import { LocalRecognizer } from '../recognition.mjs';
const deferred = () => {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
};
function fixture(overrides = {}) {
  const calls = [];
  const child = new EventEmitter();
  child.stdout = new EventEmitter(); child.stdout.setEncoding = () => {};
  child.stderr = new EventEmitter(); child.stdin = new EventEmitter();
  child.stdin.end = input => { calls.push(['input', JSON.parse(input)]); };
  child.kill = () => { calls.push(['kill']); queueMicrotask(() => child.emit('close', null)); };
  const filesystem = {};
  for (const name of ['mkdir', 'copyFile', 'chmod', 'writeFile', 'rm']) {
    filesystem[name] = async (...args) => { calls.push([name, ...args]); };
  }
  filesystem.mkdtemp = async () => '/private/tmp/synthetic-ocr';
  Object.assign(filesystem, overrides);
  const started = deferred();
  const recognizer = new LocalRecognizer('/synthetic/worker', {
    filesystem, spawnWorker: (...args) => { calls.push(['spawn', ...args]); started.resolve(); return child; },
  });
  return { recognizer, calls, child, started };
}

test('async setup and cleanup keep polling responsive and reserve the single job', async () => {
  const setup = deferred(), cleanup = deferred(), cleaning = deferred();
  const f = fixture({
    copyFile: () => setup.promise,
    rm: () => { cleaning.resolve(); return cleanup.promise; },
  });
  const accepted = f.recognizer.start(ink);
  assert.equal(accepted.status, 'running');
  assert.throws(() => f.recognizer.start(ink), { status: 409 });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.recognizer.state().status, 'running');
  assert.equal(f.calls.some(c => c[0] === 'spawn'), false);
  setup.resolve(); await f.started.promise;
  assert.deepEqual(f.calls.find(c => c[0] === 'input')[1], ink);
  f.child.stdout.emit('data', JSON.stringify({ text: 'Hello', confidence: 0.9 }));
  f.child.emit('close', 0);
  await cleaning.promise;
  assert.throws(() => f.recognizer.start(ink), { status: 409 });
  await new Promise(resolve => setImmediate(resolve));
  cleanup.resolve(); await f.recognizer.task;
  assert.equal(f.recognizer.state().text, 'Hello');
  assert.equal(f.recognizer.busy, false);
  await f.recognizer.close();
});

test('setup and cleanup failures are contained without exposing paths or retaining the busy slot', async () => {
  for (const operation of ['copyFile', 'rm']) {
    const f = fixture({ [operation]: async () => { throw new Error('/private/sensitive-path'); } });
    f.recognizer.start(ink);
    if (operation === 'rm') {
      await f.started.promise;
      f.child.stdout.emit('data', '{"text":"Hello","confidence":1}');
      f.child.emit('close', 0);
    }
    await f.recognizer.task;
    assert.equal(f.recognizer.state().status, 'failed');
    assert.equal(JSON.stringify(f.recognizer.state()).includes('sensitive'), false);
    assert.equal(f.recognizer.busy, false);
    if (operation === 'copyFile') assert.ok(f.calls.some(c => c[0] === 'rm'));
    await f.recognizer.close();
  }
});

test('closing during setup prevents spawn and awaits cleanup without resurrecting a job', async () => {
  const setup = deferred();
  const f = fixture({ copyFile: () => setup.promise });
  f.recognizer.start(ink);
  await new Promise(resolve => setImmediate(resolve));
  const closed = f.recognizer.close();
  setup.resolve(); await closed;
  assert.equal(f.calls.some(c => c[0] === 'spawn'), false);
  assert.ok(f.calls.some(c => c[0] === 'rm'));
  assert.equal(f.recognizer.expiry, null);
  assert.deepEqual(f.recognizer.state(), { status: 'idle' });
  assert.throws(() => f.recognizer.start(ink), { status: 503 });
});

test('worker failure, excessive output, and shutdown clean up asynchronously', async () => {
  for (const outcome of ['error', 'overflow', 'shutdown']) {
    const f = fixture();
    f.recognizer.start(ink); await f.started.promise;
    if (outcome === 'error') f.child.emit('error', new Error('spawn failed'));
    if (outcome === 'overflow') f.child.stdout.emit('data', 'x'.repeat(100001));
    if (outcome === 'shutdown') await f.recognizer.close();
    await f.recognizer.task;
    assert.ok(f.calls.some(c => c[0] === 'rm'));
    assert.equal(f.recognizer.busy, false);
    assert.equal(f.recognizer.state().status, outcome === 'shutdown' ? 'idle' : 'failed');
    await f.recognizer.close();
  }
});
