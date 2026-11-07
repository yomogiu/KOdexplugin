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
