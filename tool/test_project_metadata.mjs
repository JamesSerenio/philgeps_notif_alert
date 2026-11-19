import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {projectMetadataPatch,assertSharedMetadata,firstProjectText} from 'file:///C:/Projects/philgeps-editor/src/lib/projectMetadata.js';
import {getDeadline,formatDateTime,formatPeso,getTimeRemaining} from 'file:///C:/Projects/philgeps-editor/src/lib/projectFormatters.js';
const setup={projectTitle:'SUPPLY AND DELIVERY OF WATER METER AND FITTINGS',referenceNumber:'132124',procuringEntity:'MUNICIPALITY OF SUMILAO, BUKIDNON',municipality:'SUMILAO',province:'BUKIDNON',closingDate:'2026-11-19',date:'2026-11-16',bidderName:'Keep company'};
test('canonical shared mapping excludes company, publication and document-only fields',()=>{
 const patch=projectMetadataPatch(setup,{is_manual:true});
 assert.equal(patch.reference_number,'132124');assert.equal(patch.manual_deadline,'2026-11-19');
 for(const key of ['posting_date','date','bidderName','is_manual','id'])assert.equal(Object.hasOwn(patch,key),false);
 assert.throws(()=>assertSharedMetadata({is_manual:true},setup),/shared project information was not saved/);
 assert.equal(firstProjectText({title:' ',projectTitle:'Saved title'},['title','projectTitle']),'Saved title');
});
test('date-only deadline and missing budget are displayed without fabricated values',()=>{
 const value=getDeadline({manual_deadline:'2026-11-19',closing_date:'2026-11-20T01:00:00Z'});
 assert.equal(value,'2026-11-19');assert.equal(formatDateTime(value),'Nov 19, 2026');
 assert.match(getTimeRemaining(value,Date.parse('2026-11-19T12:00:00+08:00')),/Closes in 11h/);
 for(const missing of [null,undefined,'','PHP']) assert.equal(formatPeso(missing),'Not available');
 assert.match(formatPeso(0),/0\.00/);assert.equal(getDeadline({} ),null);
});
async function service(db){
 const context=vm.createContext({console,Date,JSON,Object,Array,String,Error,Set});
 const supabase={from(table){const state={table,op:'read',filters:{}};return{
  select(){return this;},eq(key,value){state.filters[key]=value;return this;},
  update(payload){state.op='update';state.payload=payload;return this;},
  insert(payload){state.op='insert';state.payload=payload;return this;},
  async maybeSingle(){return{data:db.editor??null,error:null};},
  async single(){
   if(table==='philgeps_posts')return{data:db.project,error:null};
   if(state.op==='read')return{data:db.editor,error:null};
   if((state.op==='update'&&state.filters.updated_at!==db.editor?.updated_at)||(state.op==='insert'&&db.editor))return{data:null,error:{code:'PGRST116'}};
   db.version=(db.version||0)+1;
   db.editor={...db.editor,...state.payload,updated_at:`2026-11-19T00:00:0${db.version}.000001+00:00`};
   if(db.trigger&&state.payload.bid_security?.documentSetup)db.project={...db.project,...projectMetadataPatch(state.payload.bid_security.documentSetup,db.project)};
   return{data:db.editor,error:null};
  },
 };}};
 const dependencies={
  '../supabase':new vm.SyntheticModule(['supabase'],function(){this.setExport('supabase',supabase)},{context}),
  '../lib/projectMetadata':new vm.SyntheticModule(['assertSharedMetadata'],function(){this.setExport('assertSharedMetadata',assertSharedMetadata)},{context}),
 };
 const module=new vm.SourceTextModule(await readFile('C:/Projects/philgeps-editor/src/services/editorStateService.js','utf8'),{context});
 await module.link(name=>dependencies[name]);await module.evaluate();return module.namespace;
}
test('actual save service rejects false Saved, retries metadata repair and rejects stale writes',async()=>{
 const db={project:{id:'fc066763-84a8-4423-bbd8-eada9101c201',is_manual:true,title:'',manual_deadline:null},editor:{updated_at:'original',bid_security:{documentSetup:setup},technical_specs:[{price:123,selected:true}]},trigger:false};
 const api=await service(db);
 assert.equal((await api.getEditorState(db.project.id)).__metadataPending,true);
 let revision;
 try{await api.saveEditorState(db.project.id,{bid_security:{documentSetup:setup}},{expectedUpdatedAt:'original'});assert.fail('must reject unverified metadata');}
 catch(error){assert.match(error.message,/shared project information was not saved/);revision=error.savedRevision;}
 assert.ok(revision);assert.equal(db.project.title,'');
 db.trigger=true;
 const saved=await api.saveEditorState(db.project.id,{bid_security:{documentSetup:setup}},{expectedUpdatedAt:revision});
 assert.equal(db.project.title,setup.projectTitle);assert.equal(db.project.reference_number,'132124');
 assert.equal(db.project.id,'fc066763-84a8-4423-bbd8-eada9101c201');
 assert.deepEqual(db.editor.technical_specs,[{price:123,selected:true}]);
 assert.equal(db.project.posting_date,undefined);
 assert.ok(saved.updated_at);
 await assert.rejects(api.saveEditorState(db.project.id,{bid_security:{documentSetup:{...setup,projectTitle:'stale'}}},{expectedUpdatedAt:'original'}),/another tab|UPDATE access/);
 assert.equal(db.project.title,setup.projectTitle);
});
test('new blank editor and older saved project retain IDs, document settings and original dates',async()=>{
 for(const manual of [true,false]){
  const selected=manual?{projectTitle:'',referenceNumber:'',procuringEntity:'',municipality:'',province:'',closingDate:'',date:'2026-11-16'}:setup;
  const db={trigger:true,project:{id:manual?'new-blank':'older',is_manual:manual,title:manual?'':'Keep title',posting_date:'2026-10-01T00:00:00Z'},editor:manual?null:{updated_at:'older',bid_security:{settings:{keep:true}}}};
  const api=await service(db);
  await api.saveEditorState(db.project.id,{bid_security:{documentSetup:selected,settings:{keep:true}}},{expectedUpdatedAt:manual?null:'older'});
  assert.equal(db.project.id,manual?'new-blank':'older');assert.equal(db.project.posting_date,'2026-10-01T00:00:00Z');
  assert.equal(db.editor.bid_security.settings.keep,true);
  if(manual){assert.equal(db.project.title,'');assert.equal(db.project.manual_deadline,null);}
 }
});
