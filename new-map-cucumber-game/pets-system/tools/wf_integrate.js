export const meta = {
  name: 'pets-integrate',
  description: 'Install the pet system into Studio stage by stage (backup, surgical patch, playtest checks, fix loop), stopping at the first blocker',
  phases: [
    { title: 'Stages', detail: 'one integration agent per stage, strictly sequential' },
  ],
}

const ROOT = 'C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\new-map-cucumber-game\\pets-system\\'
const STAGES = args.stages
const SCHEMA = {
  type: 'object',
  properties: {
    stage: { type: 'string' },
    blocked: { type: 'boolean' },
    blocked_reason: { type: 'string' },
    installed: { type: 'array', items: { type: 'string' } },
    checks: { type: 'array', items: { type: 'object', properties: {
      name: { type: 'string' }, pass: { type: 'boolean' }, evidence: { type: 'string' } }, required: ['name', 'pass'] } },
    fixes: { type: 'array', items: { type: 'string' } },
    open_issues: { type: 'array', items: { type: 'string' } },
    report_file: { type: 'string' },
    playtest_stopped: { type: 'boolean' },
  },
  required: ['stage', 'blocked', 'installed', 'checks', 'fixes', 'open_issues', 'report_file', 'playtest_stopped'],
}

phase('Stages')
const done = []
for (const s of STAGES) {
  const r = await agent(`You are the INTEGRATION AGENT for stage ${s.id} of the pet-system build for the user's Roblox game "New Map Cucumber Game" (Studio instance_id "instance:c9f-ksl").
Read, in order: ${ROOT}RULES.md, ${ROOT}INTEGRATION.md (your procedure — it supersedes CONTRACTS 10.2 where they differ), ${ROOT}CONTRACTS.md sections 0, 8, 10, 11 and the sections for the files your stage installs, then every earlier report ${ROOT}tests\\S*_report.md.
Previous stages this run: ${JSON.stringify(done.map(d => ({ stage: d.stage, blocked: d.blocked, failed: (d.checks || []).filter(c => !c.pass).map(c => c.name), open: d.open_issues })), null, 1).slice(0, 8000)}

STAGE ${s.id}: ${s.what}
${s.extra || ''}

Do the whole stage: backup, stage, dry run, apply, verify the write, mark_pushed, playtest checks, fix loop (root causes, minimal contract-consistent fixes, re-run the affected unit tests), report file ${ROOT}tests\\${s.id}_report.md. Be thorough on the checks — they are the only runtime verification this code gets. Evidence = numbers and log lines, not impressions. Before returning: stop any playtest you started and confirm it is stopped; leave ServerStorage.PetTestProfileKey = "PetTest" set; remove every other dev attribute/test instance you created.
Return the structured result. Set blocked=true only if the stage cannot be completed (Studio unreachable, a failure you could not fix that makes later stages meaningless).`,
    { label: `stage:${s.id}`, phase: 'Stages', schema: SCHEMA })
  if (!r) { log(`stage ${s.id}: agent returned nothing — stopping`); break }
  done.push(r)
  const fails = (r.checks || []).filter(c => !c.pass)
  log(`stage ${s.id}: ${r.checks.length - fails.length}/${r.checks.length} checks pass, ${r.fixes.length} fixes, blocked=${r.blocked}`)
  if (r.blocked) break
}
return { stages: done }
