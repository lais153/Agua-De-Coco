export function parseCash(value:string):number|null {
 const text=value.trim();
 if(!/^(?:\d+(?:[.,]\d{1,2})?|\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?)$/.test(text))return null;
 const normalized=text.includes(',')?text.replaceAll('.','').replace(',','.'):/^\d{1,3}(?:\.\d{3})+$/.test(text)?text.replaceAll('.',''):text;
 const [whole,fraction='']=normalized.split('.');
 const cents=Number(whole)*100+Number(fraction.padEnd(2,'0'));
 return Number.isSafeInteger(cents)&&cents>=0&&cents<=100000000?cents:null;
}
