/* AMQM production attendance domain */
(function(window){
'use strict';
const STATUS=Object.freeze({PRESENT:'P',LATE:'L',ABSENT:'A',EXCUSED:'E',MEDICAL:'M',PERMISSION:'PERMISSION',EARLY_DEPARTURE:'EARLY'});
const TYPE=Object.freeze({STUDENT:'student',STAFF:'staff'});
const MODE=Object.freeze({QR:'qr',MANUAL:'manual',OFFLINE_QR:'offline_qr',ADMIN:'admin'});
function parseTime(value){
  const m=String(value||'').match(/^([01]\d|2[0-3]):([0-5]\d)$/);
  return m?Number(m[1])*60+Number(m[2]):600;
}
function classify(timestamp,deadline,grace){
  const d=new Date(timestamp); if(Number.isNaN(d.getTime())) return STATUS.PRESENT;
  const mins=d.getHours()*60+d.getMinutes(), cut=parseTime(deadline), g=Math.max(0,Number(grace)||0);
  return mins<=cut+g?STATUS.PRESENT:STATUS.LATE;
}
function identity(type,identifier){type=String(type||'').toLowerCase();identifier=String(identifier||'').trim();
  if(!identifier||(type!==TYPE.STUDENT&&type!==TYPE.STAFF))return null;return {type,identifier};
}
function record(input){
  const id=identity(input&&input.type,input&&input.identifier);if(!id)throw new Error('Invalid attendance identity');
  const at=input.at||new Date().toISOString();
  return Object.freeze({identity:id,status:input.status||classify(at,input.deadline,input.grace),at,mode:input.mode||MODE.QR,
    officerId:input.officerId||null,reason:input.reason||'',location:input.location||'',synced:input.synced!==false});
}
window.AMQMAttendance=Object.freeze({STATUS,TYPE,MODE,parseTime,classify,identity,record});
})(window);
