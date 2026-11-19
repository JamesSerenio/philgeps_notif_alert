// Applies reviewed changes to the sibling React repo; requires filesystem approval.
const fs=require('node:fs');
const path=require('node:path');
const root='C:/Projects/philgeps-editor';
if(process.argv.includes('--draft-revision')) {
 const file=path.join(root,'src/hooks/useEditorPersistence.js');
 let s=fs.readFileSync(file,'utf8');
 s=s.replace('ctx.remoteUpdatedAt = remote?.updated_at ?? backup?.remoteUpdatedAt ?? null',`// A recovered draft must retain the revision it was edited against.
      // Otherwise reopening an old tab could silently overwrite a newer save.
      ctx.remoteUpdatedAt = Object.keys(backup?.pending || {}).length && Object.hasOwn(backup,'remoteUpdatedAt')
        ? backup.remoteUpdatedAt
        : remote?.updated_at ?? backup?.remoteUpdatedAt ?? null`);
 fs.writeFileSync(file,s);
 process.exit(0);
}
if(process.argv.includes('--section-fields')) {
 const file=path.join(root,'src/hooks/useEditorPersistence.js');
 let s=fs.readFileSync(file,'utf8');
 s=s.replace('Object.entries(patch).map(([key, value]) => [',`Object.entries(patch).filter(([key]) => SECTIONS.includes(key)).map(([key, value]) => [`);
 fs.writeFileSync(file,s);
 process.exit(0);
}
if(process.argv.includes('--finalize')) {
 const target=file=>path.join(root,file);
 function change(file,fn){const before=fs.readFileSync(target(file),'utf8').replace(/\r\n/g,'\n');fs.writeFileSync(target(file),fn(before));}
 change('src/services/editorStateService.js',s=>s.replace('  return restored',`  const setup = restored.bid_security?.documentSetup
  if (setup) {
    try {
      const result = await supabase.from('philgeps_posts').select('*').eq('id',String(projectId)).single()
      if (result.error || !result.data) throw Error('Shared project information could not be verified.')
      assertSharedMetadata(result.data,setup)
    } catch (error) {
      restored.__metadataPending = true
      restored.__metadataError = error.message
    }
  }
  return restored`));
 change('src/hooks/useEditorPersistence.js',s=>s.replace('      const pending = {\n        ...(backup?.pending || {}),\n      }',`      const pending = {
        ...(backup?.pending || {}),
      }
      if (remote?.__metadataPending && remote?.bid_security && !Object.hasOwn(pending,'bid_security')) pending.bid_security=remote.bid_security`));
 change('src/pages/ProjectListPage.jsx',s=>s.replace('    } finally {\n      setLoading(false)','    } finally {\n      if (version === requestVersion.current) setLoading(false)').replace("      setError(\u0060Unable to load projects: \u0024{err.message || 'Failed to load projects'}\u0060)","      if (version === requestVersion.current) setError(\u0060Unable to load projects: \u0024{err.message || 'Failed to load projects'}\u0060)"));
 change('src/lib/projectMetadata.js',s=>s+`\nexport function firstProjectText(project,keys,fallback='') {
  for (const key of keys) { const value=String(project[key] ?? '').trim(); if(value) return value }
  return fallback
}\n`);
 change('src/components/ProjectCard.jsx',s=>s
  .replace("import DashboardIcon from './DashboardIcon'","import DashboardIcon from './DashboardIcon'\nimport { firstProjectText } from '../lib/projectMetadata'")
  .replace("project.title || project.project_title || project.projectTitle || 'Untitled Project'","firstProjectText(project,['title','project_title','projectTitle'],'Untitled Project')")
  .replace("project.reference_number || project.reference_no || project.referenceNumber || '—'","firstProjectText(project,['reference_number','reference_no','referenceNumber'],'—')")
  .replace("project.procuring_entity || project.entity || '—'","firstProjectText(project,['procuring_entity','procuringEntity','entity'],'—')")
  .replace("value: project.lgu,","value: firstProjectText(project,['lgu','municipality']),")
  .replace("value: project.area_of_delivery,","value: firstProjectText(project,['area_of_delivery','areaOfDelivery','province','location']),"));
 change('src/lib/projectFormatters.js',s=>s
  .replace('return project.manual_deadline || project.manualDeadline || project.closing_date || project.closingDate || null',"return [project.manual_deadline,project.manualDeadline,project.closing_date,project.closingDate].find(value => String(value ?? '').trim()) || null")
  .replace("  const amount = typeof value === 'number' ? value : Number(String(value).replace(/PHP|₱|,/gi, '').trim())", "  const numeric = typeof value === 'number' ? value : String(value).replace(/PHP|₱|,/gi, '').trim()\n  if (numeric === '') return 'Not available'\n  const amount = Number(numeric)"));
 fs.copyFileSync(path.join(__dirname,'../supabase/project_metadata_sync.sql'),target('supabase/project_metadata_sync.sql'));
 console.log('Applied load verification, canonical card fallbacks, stale-list protection, and migration copy.');
 process.exit(0);
}
function edit(file,change){const target=path.join(root,file);const before=fs.readFileSync(target,'utf8').replace(/\r\n/g,'\n');const after=change(before);if(after===before)throw Error('No change: '+file);fs.writeFileSync(target,after);}
function replace(text,old,next){if(!text.includes(old))throw Error('Expected code not found: '+old.slice(0,70));return text.replace(old,next);}
fs.writeFileSync(path.join(root,'src/lib/projectMetadata.js'),`// Shared post fields only. Company/document settings remain in editor JSON.
export function projectMetadataPatch(setup = {}, project = {}) {
  const mapping = { title:'projectTitle', reference_number:'referenceNumber', procuring_entity:'procuringEntity', lgu:'municipality', area_of_delivery:'province' }
  const patch = {}
  for (const [column,key] of Object.entries(mapping)) {
    if (Object.hasOwn(setup,key) && (String(setup[key] ?? '').trim() || project.is_manual === true)) patch[column] = String(setup[key] ?? '').trim()
  }
  if (project.is_manual === true && Object.hasOwn(setup,'closingDate')) {
    const value = String(setup.closingDate ?? '').trim()
    if (value && !/^\\d{4}-\\d{2}-\\d{2}$/.test(value)) throw Error('Deadline must be YYYY-MM-DD.')
    patch.manual_deadline = value || null
  }
  return patch
}
export function assertSharedMetadata(project,setup) {
  const expected=projectMetadataPatch(setup,project)
  const missing=Object.keys(expected).filter(key => String(project[key] ?? '').trim() !== String(expected[key] ?? '').trim())
  if (missing.length) throw Error('Document data saved, but shared project information was not saved ('+missing.join(', ')+'). Apply supabase/project_metadata_sync.sql in this Supabase project, then retry. Your inputs are retained.')
}
`);
edit('src/services/editorStateService.js',s=>{
 s=replace(s,"import { supabase } from '../supabase'","import { supabase } from '../supabase'\nimport { assertSharedMetadata } from '../lib/projectMetadata'");
 s=replace(s,'export async function saveEditorState(\n  projectId,\n  patch\n)', 'export async function saveEditorState(\n  projectId,\n  patch,\n  options = {}\n)');
 const start=s.indexOf('  const { error } = await supabase\n    .from(TABLE)\n    .upsert(');
 const end=s.indexOf('\n}\n',start);
 if(start<0||end<0)throw Error('Save boundary not found');
 return s.slice(0,start)+`  let expected = options.expectedUpdatedAt
  if (!Object.hasOwn(options,'expectedUpdatedAt')) expected = (await getEditorState(projectId))?.updated_at ?? null
  const request = expected == null
    ? supabase.from(TABLE).insert(payload)
    : supabase.from(TABLE).update(payload).eq('project_id',String(projectId)).eq('updated_at',expected)
  const { data, error } = await request.select('*').single()
  if (error || !data) throw Error(error?.code === 'PGRST116' || error?.code === '23505'
    ? 'No editor row updated: another tab changed it or UPDATE access is missing. Your draft is retained. Reload the saved version and check editor permissions before retrying.'
    : error?.message || 'No editor row was saved. Check this project’s editor INSERT/UPDATE permissions.')
  try { if (payload.bid_security?.documentSetup) {
    const result = await supabase.from('philgeps_posts').select('*').eq('id',String(projectId)).single()
    if (result.error || !result.data) throw Error('Document data saved, but the shared project row could not be verified. Check project read permissions and retry.')
    assertSharedMetadata(result.data,payload.bid_security.documentSetup)
  } } catch (error) { error.savedRevision=data.updated_at; throw error }
  if (typeof window !== 'undefined') window.dispatchEvent(new Event('project-metadata-saved'))
  return data`+s.slice(end);
});
edit('src/hooks/useEditorPersistence.js',s=>{
 s=replace(s,'      values: cleanPatch(data.values),','      remoteUpdatedAt: data.remoteUpdatedAt ?? data.values?.updated_at ?? null,\n      values: cleanPatch(data.values),');
 s=replace(s,'        version: 4,','        version: 4,\n        remoteUpdatedAt: ctx.remoteUpdatedAt,');
 s=replace(s,'          await saveEditorState(ctx.id, patch)',`          const saved = await saveEditorState(ctx.id, patch, {expectedUpdatedAt:ctx.remoteUpdatedAt})
          ctx.remoteUpdatedAt = saved.updated_at`);
 s=replace(s,'        } catch (error) {\n          ctx.pending', '        } catch (error) {\n          if (error.savedRevision) ctx.remoteUpdatedAt = error.savedRevision\n          ctx.pending');
 // A metadata-verification failure can occur after the JSON row has saved.
 // Carry its revision forward so retry can repair metadata without a false conflict.
 s=replace(s,'      ctx.loaded = true','      ctx.remoteUpdatedAt = remote?.updated_at ?? backup?.remoteUpdatedAt ?? null\n      ctx.loaded = true');
 return s;
});
edit('src/pages/ProjectEditorPage.jsx',s=>{
 s=replace(s,'  const blankProjectSyncRef = useRef(null)\n','');
 s=replace(s,'  useEffect(() => () => clearTimeout(blankProjectSyncRef.current), [])\n','');
 const start=s.indexOf('  // Save project-card information and manual');
 const end=s.indexOf('  const next = {',start);
 if(start<0||end<0)throw Error('Manual sync block not found');
 return s.slice(0,start)+'  // Shared fields commit atomically with editor JSON through the database trigger.\n\n'+s.slice(end);
});
edit('src/lib/projectFormatters.js',s=>{
 s=replace(s,'return project.closing_date || project.closingDate || null','return project.manual_deadline || project.manualDeadline || project.closing_date || project.closingDate || null');
 s=replace(s,"  const time = new Intl.DateTimeFormat", "  if (/^\\d{4}-\\d{2}-\\d{2}$/.test(String(value).trim())) return day\n  const time = new Intl.DateTimeFormat");
 s=replace(s,'  const remaining = date.getTime() - now',"  const end = /^\\d{4}-\\d{2}-\\d{2}$/.test(String(value).trim()) ? date.getTime()+86400000-1 : date.getTime()\n  const remaining = end - now");
 return s;
});
edit('src/pages/ProjectListPage.jsx',s=>{
 s=replace(s,"import { useEffect, useState } from 'react'","import { useEffect, useRef, useState } from 'react'");
 s=replace(s,'  const navigate = useNavigate()','  const navigate = useNavigate()\n  const requestVersion = useRef(0)');
 s=replace(s,'  async function loadProjects() {','  async function loadProjects() {\n    const version = ++requestVersion.current');
 s=replace(s,'      setProjects(data ?? [])','      if (version === requestVersion.current) setProjects(data ?? [])');
 s=replace(s,'    async function initialLoad() {','    async function initialLoad() {\n      const version = ++requestVersion.current');
 s=s.replaceAll('if (!cancelled)', 'if (!cancelled && version === requestVersion.current)');
 s=replace(s,'    initialLoad()','    initialLoad()\n    window.addEventListener(\'focus\', initialLoad)\n    window.addEventListener(\'project-metadata-saved\', initialLoad)');
 s=replace(s,'      cancelled = true','      cancelled = true\n      window.removeEventListener(\'focus\', initialLoad)\n      window.removeEventListener(\'project-metadata-saved\', initialLoad)');
 return s;
});
console.log('Applied shared-metadata persistence, revision checks, and card deadline fixes.');
