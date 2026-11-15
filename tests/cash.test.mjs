import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import ts from 'typescript';
const js=ts.transpile(fs.readFileSync('lib/cash.ts','utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022});
const {parseCash}=await import('data:text/javascript;base64,'+Buffer.from(js).toString('base64'));
test('Dinheiro convertido para centavos sem arredondamento de ponto flutuante',()=>{for(const [text,cents] of [['0',0],['0,00',0],['50',5000],['10,1',1010],['0,29',29],['1.234,56',123456],['1234.56',123456],['1.234',123400]])assert.equal(parseCash(text),cents)});
test('Recusa valor ausente, negativo, centavos extras e formato inválido',()=>{for(const text of ['', ' ', '-10', '1,234','1.2.3','abc','Infinity','1000001'])assert.equal(parseCash(text),null)});
