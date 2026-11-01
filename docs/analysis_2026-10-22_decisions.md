> Historical analysis. Since November 1, the domain action is split into four independent decisions. See [the current test procedure](testing_building_decisions.md); the combined sequence below describes the earlier build.

# Decision performance: October 22 follow-up

Sources: the local CK3 `debug.log`, `error.log` and `multiplayer.log` from the session started at 19:47 and ended at 19:54, plus the installed vanilla event script and the current mod sources. These logs contain script traces, not CPU profiles. UI-opening time cannot be measured from them.

## Confirmed construction stages

| Confirmed execution | BEGIN → END | Domain size changes | Domain limit changes |
| --- | --- | --- | --- |
| 19:48:07 | Same recorded second | None detected | None detected |
| 19:48:30 | Same recorded second | None detected | None detected |
| 19:50:22 | Ends 19:50:42 | Feudalization and foundation | None detected |

For the last run, foundation begins at 19:50:22 and the following size-change marker appears at 19:50:41. The first upgrade starts at 19:50:41 and the remaining passes end at 19:50:42. Foundation therefore accounts for approximately 19 of the 20 recorded seconds. These are timestamps rounded to seconds, not precise benchmarks.

The mod deliberately changes holding types and founds new temples/cities in empty baronies before improving buildings. Both stages changed the engine's `domain_size` in this run. The upgrade/fill stages did not produce a further size-change marker; no domain-limit change was detected. This identifies why the owned-domain counter can change without a title-seizure interaction. The log does not include numeric deltas or ownership lists, so it cannot identify every affected barony.

Each of the three runs has one matching END. No recurring construction event appears in these traces. This is evidence against a self-scheduling loop in these runs, not proof that every engine callback is correct. There are 110 vanilla mandala completion errors during castle upgrades across these runs (5 in the first, 105 in the third).

## Decision screen

The building decisions already dispatched one-shot events. The other action decisions still exposed realm, family, house, councillor and de jure title traversals directly through their effect tree, some inside `hidden_effect`. Merely hiding generated text did not provide the same separation as event dispatch. These traversals are a plausible cause of decision UI latency on a large realm, but these logs do not establish their CPU cost or show exactly when the user opened the screen.

All eight remaining action decisions now dispatch immediate hidden events. Their original effect content was compared during extraction to ensure that it was preserved. Together with the two building actions, all ten actions now expose only a static summary plus their event trigger. All decision titles, descriptions, selection/confirmation strings and summary aliases are checked for dynamic expressions in all nine languages. The unused live construction-count localization was removed. Eligibility checks and show/hide flags remain necessary UI checks.

`MQA_DECISION BEGIN/END <decision>` markers now locate actual execution of the eight migrated actions. They must not appear when merely opening the decision screen. The council's existing monthly maintenance remains intentional and unchanged.

## Separate vanilla tooltip failure

`error.log` contains 34,131 error blocks, of which 126 reference the mod (125 completion errors plus one missing-BOM warning). Of the remaining errors, **33,216** originate at `events/dlc/ce1/epidemic_events.txt:4865`, option `epidemic_events.1110`, explicitly marked **while building tooltip/description**.

That vanilla option scans every sub-realm county and its epidemics while comparing them to an invalid saved `epidemic_scope`. This repeatedly logs an invalid epidemic scope. The burst includes thousands of errors per second around 19:53:38–19:53:43, well after construction ended at 19:50:42. It can add substantial UI and logging work, but there is no mod stack reference or evidence here establishing that the mod caused the saved epidemic to become invalid.

The decision UI change does not patch this vanilla event. If its window or tooltip remains open, it may continue to slow the interface. Testing the mod's decision screen separately from that event is necessary to distinguish the two costs.

## Scope of the correction

- All action code is isolated from the mod decision tooltip tree; UI summaries are static.
- Existing foundation/feudalization behavior is retained. A confirmed construction can still spend significant time founding holdings and can change owned domain size.
- Diagnostic script encoding is now UTF-8 BOM. Change markers no longer interpolate a parameter inside a quoted string; their preceding PHASE identifies the stage.
- The vanilla epidemic option and mandala completion scripts remain unchanged. No game files were patched.

In-game validation is still required. First test opening/selecting decisions without confirming; then separately measure a single confirmed construction and inspect the PHASE markers. Compare both sides of the domain counter.
