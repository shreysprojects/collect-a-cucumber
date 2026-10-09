export const meta = {
  name: 'pets-fix-and-finish',
  description: 'Fix the confirmed review findings (parallel, disjoint files, each fix independently checked), then install S5-S9 stage by stage',
  phases: [
    { title: 'Fix', detail: 'one fixer per file group, verify-then-fix, re-run unit tests' },
    { title: 'Check', detail: 'independent reviewer per fix group' },
    { title: 'Stages', detail: 'sequential integration agents: refresh, S5 buffs, S6 combat, S7 menu, S8 regression/load/real key, S9 balance + handoff' },
  ],
}

const ROOT = 'C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\new-map-cucumber-game\\pets-system\\'
const LIVE = 'C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\new-map-cucumber-game\\live-2026-09-22\\'
const COMMON = `You are working on the user's new pet system for their Roblox game "New Map Cucumber Game" (Luau). Read ${ROOT}RULES.md, then ${ROOT}CONTRACTS.md (interfaces; section 12 has amendments), ${ROOT}PLAN.md (spec), ${ROOT}review\\CONFIRMED.md (confirmed defects), and the stage reports ${ROOT}tests\\S*_report.md (what is installed and verified so far: S0a-S4 are LIVE in Studio).
New scripts: ${ROOT}src\\. Edited existing scripts: ${ROOT}patched\\ (originals ${LIVE}; ${ROOT}pushed\\ = the version currently live for already-pushed patched files).`

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    group: { type: 'string' },
    items: { type: 'array', items: { type: 'object', properties: {
      finding: { type: 'string' }, verdict: { type: 'string', enum: ['fixed', 'already-fixed', 'rejected'] }, detail: { type: 'string' } },
      required: ['finding', 'verdict', 'detail'] } },
    files_changed: { type: 'array', items: { type: 'string' } },
    tests: { type: 'array', items: { type: 'string' } },
  },
  required: ['group', 'items', 'files_changed', 'tests'],
}
const CHECK_SCHEMA = {
  type: 'object',
  properties: { ok: { type: 'boolean' }, problems: { type: 'array', items: { type: 'string' } } },
  required: ['ok', 'problems'],
}
const STAGE_SCHEMA = {
  type: 'object',
  properties: {
    stage: { type: 'string' }, blocked: { type: 'boolean' }, blocked_reason: { type: 'string' },
    installed: { type: 'array', items: { type: 'string' } },
    checks: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, pass: { type: 'boolean' }, evidence: { type: 'string' } }, required: ['name', 'pass'] } },
    fixes: { type: 'array', items: { type: 'string' } },
    open_issues: { type: 'array', items: { type: 'string' } },
    report_file: { type: 'string' }, playtest_stopped: { type: 'boolean' },
  },
  required: ['stage', 'blocked', 'installed', 'checks', 'fixes', 'open_issues', 'report_file', 'playtest_stopped'],
}

phase('Fix')
const fixes = await pipeline(args.fixGroups,
  g => agent(`${COMMON}

You are FIXER for group "${g.id}". You own ONLY these files: ${JSON.stringify(g.files)}.
Items to handle (numbers refer to review\\CONFIRMED.md unless stated): ${g.items}

For each item: re-verify it against the CURRENT file (S4 already changed PetService to Atomic streaming; other fixes may already cover an item); fix it if still real (minimal, contract-consistent; if the contract itself must change, append a line to CONTRACTS.md section 12 "INTEGRATION AMENDMENTS"); otherwise mark already-fixed/rejected with the reason. Do NOT write to Studio (read-only loadstring compile checks + unit tests via the loopback servers only). Re-run every tests\\<WP>_*.lua suite that covers the files you changed and add test cases for the fixed behaviour where the logic is testable. Return the structured result.`,
    { label: `fix:${g.id}`, phase: 'Fix', schema: FIX_SCHEMA }),
  (r, g) => agent(`${COMMON}

You are an independent CHECKER. Fixer "${g.id}" changed ${JSON.stringify(g.files)} to resolve: ${g.items}
Fixer report: ${JSON.stringify(r).slice(0, 6000)}
Diff each changed file against its previous version (for patched files: ${ROOT}pushed\\<file> if it exists, else ${LIVE}<file>; for src files there is no saved previous version — read the fix areas carefully). Verify each claimed fix actually resolves the defect's scenario, introduces no regression, and keeps the contract. Compile-check via loopback. Read-only: do not edit files. Report problems with evidence (empty list if none).`,
    { label: `check:${g.id}`, phase: 'Check', schema: CHECK_SCHEMA }).then(c => ({ group: g.id, fix: r, check: c })))

const checkProblems = fixes.filter(Boolean).filter(f => f.check && !f.check.ok)
for (const p of checkProblems) {
  const g = args.fixGroups.find(x => x.id === p.group)
  const again = await agent(`${COMMON}

You are FIXER for group "${g.id}" (files ${JSON.stringify(g.files)}). An independent checker rejected parts of the previous fix. Verify each problem and resolve the real ones; re-run the unit tests. Read-only on Studio.
CHECKER PROBLEMS: ${JSON.stringify(p.check.problems, null, 1)}
PREVIOUS FIX REPORT: ${JSON.stringify(p.fix).slice(0, 5000)}`, { label: `refix:${g.id}`, phase: 'Fix', schema: FIX_SCHEMA })
  p.refix = again
}
const changed = [...new Set(fixes.filter(Boolean).flatMap(f => [...((f.fix && f.fix.files_changed) || []), ...((f.refix && f.refix.files_changed) || [])]))]
log(`fix groups done; files changed: ${changed.length}`)

phase('Stages')
const done = []
for (const s of args.stages) {
  const r = await agent(`You are the INTEGRATION AGENT for stage ${s.id} of the pet-system build for the user's Roblox game "New Map Cucumber Game" (Studio instance_id "instance:c9f-ksl").
Read, in order: ${ROOT}RULES.md, ${ROOT}INTEGRATION.md (your procedure; it supersedes CONTRACTS 10.2 where they differ), ${ROOT}CONTRACTS.md sections 0, 8, 10, 11, 12 and the sections for the files your stage installs, ${ROOT}review\\CONFIRMED.md, then EVERY earlier report ${ROOT}tests\\S*_report.md (they contain tool quirks you must reuse, e.g. the two-step snapshot/restore through the PetTestTransfer DataStore, and that a Studio Stop is a normal leave).
Files changed by the review-fix round just before the stages (some are already LIVE from earlier stages and must be re-pushed before relying on them): ${JSON.stringify(changed)}
Fix-round summary: ${JSON.stringify(fixes.filter(Boolean).map(f => ({ group: f.group, items: f.fix && f.fix.items.map(i => i.finding + ': ' + i.verdict), check: f.check, refix: f.refix && f.refix.items.map(i => i.finding + ': ' + i.verdict) })), null, 1).slice(0, 9000)}
Previous stages this run: ${JSON.stringify(done.map(d => ({ stage: d.stage, blocked: d.blocked, failed: (d.checks || []).filter(c => !c.pass).map(c => c.name), open: d.open_issues })), null, 1).slice(0, 9000)}

STAGE ${s.id}: ${s.what}
${s.extra || ''}

Do the whole stage per INTEGRATION.md: backup, stage, dry run, apply, verify the write, mark_pushed, playtest checks, fix loop (root causes, minimal contract-consistent fixes, re-run affected unit tests), report file ${ROOT}tests\\${s.id}_report.md. Evidence = numbers and log lines. Before returning: stop any playtest you started and confirm it is stopped; leave ServerStorage.PetTestProfileKey = "PetTest" set unless your stage says otherwise; remove every other dev attribute/test instance you created; restore the test profile after destructive checks.
Return the structured result. blocked=true only if the stage cannot be completed.`,
    { label: `stage:${s.id}`, phase: 'Stages', schema: STAGE_SCHEMA })
  if (!r) { log(`stage ${s.id}: no result — stopping`); break }
  done.push(r)
  const fails = (r.checks || []).filter(c => !c.pass)
  log(`stage ${s.id}: ${r.checks.length - fails.length}/${r.checks.length} pass, ${r.fixes.length} fixes, blocked=${r.blocked}`)
  if (r.blocked) break
}
return { fixes, changed, stages: done }
