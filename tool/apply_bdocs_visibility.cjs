// Approved sibling-repository edit. No database records are changed.
const fs = require('node:fs');
const root = 'C:/Projects/philgeps-editor/';
function edit(file, change) {
  const before = fs.readFileSync(root + file, 'utf8');
  fs.writeFileSync(root + file, change(before));
}
edit('src/lib/projectFormatters.js', s => s.includes('export function isBiddingProjectClosed') ? s : s + `
// Unknown deadlines stay visible; hiding a card never deletes saved data.
export function isBiddingProjectClosed(project, now = Date.now()) {
  if (['closed', 'expired'].includes(String(project.status ?? '').trim().toLowerCase())) return true
  return getTimeRemaining(getDeadline(project), now) === 'Expired'
}
`);
edit('src/pages/ProjectListPage.jsx', s => {
  if (s.includes('const activeProjects =')) return s;
  return s.replace("import ProjectCard from '../components/ProjectCard'", "import ProjectCard from '../components/ProjectCard'\nimport { isBiddingProjectClosed } from '../lib/projectFormatters'")
    .replace('    async function initialLoad() {', '    async function initialLoad() {\n      setNow(Date.now())')
    .replace('  const visibleProjects = projects.filter', '  const activeProjects = projects.filter(project => !isBiddingProjectClosed(project, now))\n  const visibleProjects = activeProjects.filter')
    .replace('projects.length === 0 &&', 'activeProjects.length === 0 &&')
    .replace('projects.length > 0 &&', 'activeProjects.length > 0 &&')
    .replace('No projects selected for bidding document preparation.', 'No open projects for bidding document preparation.')
    .replace('Select a project using the thumbs-up button in the PhilGEPS monitoring app. It will appear here automatically.', 'Select an open project using the thumbs-up button in the PhilGEPS monitoring app. Closed projects are hidden; their saved documents are retained.');
});
console.log('Updated React BDocs visibility; saved records and selections are retained.');
