import { readFileSync, realpathSync } from 'node:fs';
import assert from 'node:assert/strict';
import { LocalRecognizer } from '../recognition.mjs';
const strokes=[];
const line=(...p)=>strokes.push(p);
line([40,40],[40,140]);line([100,40],[100,140]);line([40,90],[100,90]);
line([130,40],[130,140]);line([130,40],[190,40]);line([130,90],[180,90]);line([130,140],[190,140]);
line([220,40],[220,140],[280,140]);line([310,40],[310,140],[370,140]);
strokes.push(Array.from({length:49},(_,i)=>[420+35*Math.cos(i*2*Math.PI/48),90+50*Math.sin(i*2*Math.PI/48)]));
const recognizer=new LocalRecognizer(realpathSync('.private/ocr-worker'));
try {
  recognizer.start({width:500,height:200,strokes});
  while(recognizer.state().status==='running')await new Promise(r=>setTimeout(r,100));
  assert.equal(recognizer.state().status,'complete');
  assert.equal(recognizer.state().text,'HELLO');
  console.log('Local no-network handwriting test passed: synthetic strokes → HELLO; no Codex turn involved.');
} finally {recognizer.close();}
