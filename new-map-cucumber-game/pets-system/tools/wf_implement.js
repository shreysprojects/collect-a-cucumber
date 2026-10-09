export const meta = {
  name: 'pets-implement',
  description: 'Implement each CONTRACTS.md work package on disk, adversarially review it, fix, then cross-check package seams',
  phases: [
    { title: 'Implement', detail: 'one agent per work package: src/ + patched/ files, compile checks, unit tests' },
    { title: 'Review', detail: 'two independent reviewers per package (correctness, integration)' },
    { title: 'Fix', detail: 'verify each finding, fix confirmed ones, rerun checks' },
    { title: 'Seams', detail: 'cross-package API consistency sweep + targeted fixes' },
  ],
}

const ROOT = 'C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\new-map-cucumber-game\\pets-system\\'
const LIVE = 'C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\new-map-cucumber-game\\live-2026-09-22\\'
const PKGS = args.packages
const COMMON = `You are part of a team implementing the user's pet-system plan for their Roblox game "New Map Cucumber Game".
Read ${ROOT}RULES.md FIRST (environment, Studio access rules, loopback file servers, hard user rules, code style), then ${ROOT}CONTRACTS.md (binding interfaces + your work package), then the parts of ${ROOT}PLAN.md and ${ROOT}research\\*.md relevant to your package.
Live sources (before any change) are local files in ${LIVE}. Studio (instance_id "instance:c9f-ksl") is READ-ONLY for you: loadstring compile checks and pure unit tests only; never write Sources or create instances there.`

const RESULT_SCHEMA = {
  type: 'object',
  properties: {
    package: { type: 'string' },
    files_written: { type: 'array', items: { type: 'string' } },
    compile_checks: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, ok: { type: 'boolean' }, detail: { type: 'string' } }, required: ['file', 'ok'] } },
    tests: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, passed: { type: 'boolean' }, detail: { type: 'string' } }, required: ['name', 'passed'] } },
    deviations: { type: 'array', items: { type: 'string' } },
    needs_from_other_packages: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['package', 'files_written', 'compile_checks', 'tests', 'deviations'],
}
const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: { type: 'object', properties: {
      file: { type: 'string' }, line: { type: 'number' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
      problem: { type: 'string' }, scenario: { type: 'string' }, fix: { type: 'string' } },
      required: ['file', 'severity', 'problem', 'scenario', 'fix'] } },
  },
  required: ['findings'],
}

function implementPrompt(p) {
  return `${COMMON}

YOUR WORK PACKAGE: ${p.id} — ${p.name}
Files you own (and ONLY these):
- new (write under ${ROOT}src\\): ${JSON.stringify(p.src)}
- patched existing (under ${ROOT}patched\\): ${JSON.stringify(p.patched)}
${p.extra ? 'Extra deliverables: ' + p.extra : ''}

Steps:
1. Read the contract section for ${p.id} and every contract section your files depend on or are depended on by. Read the live source of every script you patch in full, and of every live script whose behaviour you rely on.
2. For each patched file: copy the snapshot file from ${LIVE} into ${ROOT}patched\\ with the SAME file name (PowerShell Copy-Item), then edit that copy. Keep changes surgical: do not reformat or reorder untouched code (the diff is applied as unique-match hunks onto the live Source, possibly after other sessions edited elsewhere).
3. Write each new file under ${ROOT}src\\ with the exact file name the contract gives.
4. Compile-check EVERY file you wrote via the loopback servers (src :8793, patched :8794) with loadstring from an edit-peer execute_luau. Fix until all compile.
5. Unit tests: write ${ROOT}tests\\${p.id}_*.lua test chunks for all pure logic in your package (inject clocks/RNG/fakes; load the module under test from its source text via the loopback server + loadstring and pass fakes for requires as needed). Run them in Studio (read-only) and iterate until they pass. Tests must not create instances in the DataModel (use plain tables as fakes; if you must use Instance.new for a fake, never parent it). Record results.
6. Honour the contract exactly (names, signatures, attribute strings, remote payloads). If the contract is impossible or wrong against the live code, implement the minimal compatible interpretation and list it under deviations with the reason — other packages code against the contract.
Return the structured result.`
}

function reviewPrompt(p, impl, lens) {
  return `${COMMON}

You are an adversarial REVIEWER for work package ${p.id} — ${p.name}. Its files: new ${JSON.stringify(p.src)} under ${ROOT}src\\, patched ${JSON.stringify(p.patched)} under ${ROOT}patched\\ (compare each patched file with its original in ${LIVE} using a diff).
Implementer's report: ${JSON.stringify(impl).slice(0, 6000)}

LENS: ${lens}

Report only real defects with a concrete failure scenario (inputs/state -> wrong result/crash). Do not report style nits. Do not edit files. You may run read-only Studio compile checks/tests via the loopback servers to confirm a suspicion.`
}

const LENSES = [
  'CORRECTNESS: logic errors vs CONTRACTS.md and PLAN.md (numbers, formulas, rules, lifecycle steps), Luau runtime errors (nil indexing, wrong method calls, table.remove misuse, integer/float, string vs number attribute types), yields where the contract forbids them, deferred-signal hazards, missing cleanup/disconnects, unbounded loops, and behaviour the patch accidentally removed from the original script.',
  'INTEGRATION: every call into another package or live script matches the pinned contract/live API exactly (names, argument order, return shapes, BindableFunction Invoke vs Event); remote payloads match the contract; attribute names/types match what producers/consumers use; patched hunks keep the original behaviour intact and would still apply if unrelated lines changed; startup ordering (Init/Start, WaitForChild of remotes/modules that another package creates); Studio-only/admin-gated test hooks; performance (no per-frame world scans, no per-pet forever loops).',
]

phase('Implement')
const results = await pipeline(PKGS,
  p => agent(implementPrompt(p), { label: `impl:${p.id}`, phase: 'Implement', schema: RESULT_SCHEMA }),
  (impl, p) => parallel(LENSES.map((lens, i) => () =>
      agent(reviewPrompt(p, impl, lens), { label: `review:${p.id}:${i === 0 ? 'correct' : 'integr'}`, phase: 'Review', schema: FINDINGS_SCHEMA, effort: 'high' })))
    .then(rs => ({ impl, findings: rs.filter(Boolean).flatMap(r => r.findings) })),
  (r, p) => {
    if (!r.findings.length) return { package: p.id, impl: r.impl, fixed: [], rejected: [], note: 'no findings' }
    return agent(`${COMMON}

You own work package ${p.id} — ${p.name} (files: new ${JSON.stringify(p.src)}, patched ${JSON.stringify(p.patched)}). Two reviewers reported the findings below. For EACH: verify it against the code, contract and live sources (reviewers can be wrong); fix it if real; reject it with a reason if not. Only edit your own files. Re-run the compile checks and your ${p.id}_* tests afterwards.
FINDINGS: ${JSON.stringify(r.findings, null, 1)}
Return JSON-ish text: lists "fixed" and "rejected" (id/problem + reason), and final compile/test status.`,
      { label: `fix:${p.id}`, phase: 'Fix' }).then(t => ({ package: p.id, impl: r.impl, findings: r.findings, fixReport: t }))
  })

phase('Seams')
const seam = await agent(`${COMMON}

You are the SEAM CHECKER. All work packages are now written: new files in ${ROOT}src\\, patched files in ${ROOT}patched\\. For every cross-package call, require, remote, BindableFunction/Event, attribute and saved-data field, check producer and consumer agree (names, argument order, types, return shapes, timing assumptions). Check Init/Start wiring in the bootstrap script covers every stateful module exactly once, no cyclic requires, every remote is created by exactly one owner before use, and every patched file still compiles. Compile-check ALL files via the loopback servers in one or two evals.
Package results so far: ${JSON.stringify(results.map(r => r && { package: r.package, deviations: r.impl && r.impl.deviations, needs: r.impl && r.impl.needs_from_other_packages }), null, 1).slice(0, 12000)}
Return findings (file, line, problem, which side should change, fix).`, { label: 'seams', phase: 'Seams', schema: FINDINGS_SCHEMA, effort: 'high' })

const byFile = {}
for (const f of (seam && seam.findings) || []) {
  const owner = PKGS.find(p => p.src.includes(f.file) || p.patched.includes(f.file) || p.src.some(s => f.file.includes(s)) || p.patched.some(s => f.file.includes(s)))
  const key = owner ? owner.id : 'unowned'
  ;(byFile[key] = byFile[key] || []).push(f)
}
const seamFixes = await parallel(Object.entries(byFile).filter(([k]) => k !== 'unowned').map(([id, fs]) => () => {
  const p = PKGS.find(x => x.id === id)
  return agent(`${COMMON}

You own work package ${p.id} (files: new ${JSON.stringify(p.src)}, patched ${JSON.stringify(p.patched)}). The seam checker found cross-package mismatches touching your files. Verify each; fix the ones where YOUR side should change (per CONTRACTS.md); for ones where the other side should change, just report them. Re-run compile checks + your tests.
FINDINGS: ${JSON.stringify(fs, null, 1)}`, { label: `seamfix:${id}`, phase: 'Seams' })
}))

return { results, seam, unowned: byFile.unowned || [], seamFixes }
