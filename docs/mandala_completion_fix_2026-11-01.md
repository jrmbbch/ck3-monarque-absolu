# Mandala completion rewards, living recipients and payment audit — November 1, 2026

## Observations and scope

The first separated-decision test completed all actions, but improvements emitted 644 missing-character errors from `castle_04:on_complete` and 431 from `temple_citadel_04:on_complete`. Startup also reported a duplicate epidemic event at equal priority 0. The first repair supplied a missing payer inside five callbacks and assigned event override priority 1.

The following restarted session loaded the epidemic override without a priority conflict. Missing-character errors disappeared for castles and temple-citadels, but 22 remained in `temple_04:on_complete` during the 10:52:31–10:52:32 improvement. Four `add_piety` errors in the native temple reward helper targeted deceased characters during ordinary play, outside the decision. Later improvement runs at 11:00:06–11:00:07 and 11:14:42–11:14:43 completed without completion errors, but no logged piety snapshots or mutation summaries existed to prove absence of repeat rewards.

Those are pre-extension observations. The current audit was subsequently tested in a restarted paused session: see the validation result below. Offline checks alone do not prove CK3 callback execution.

## Callback repair

The installed `_buildings.info` specifies a new province-root context for completion, with `scope:character` being the payer **if available**. A saved character in the decision caller's context does not supply it to the engine callback. The native reward helpers already fall back to the county holder, but unguarded outer character scopes prevented entering those helpers.

`tools/generate_mandala_completion_fix.ps1` reproduces three installed native files at their exact mod-relative paths:

| File | Changed completion blocks |
| --- | --- |
| `common/buildings/00_castle_buildings.txt` | `castle_03`, `castle_04` |
| `common/buildings/00_temple_buildings.txt` | `temple_02`, `temple_03`, `temple_04` |
| `common/buildings/temple_citadel_buildings.txt` | `temple_citadel_02`, `temple_citadel_03`, `temple_citadel_04` |

If no payer exists, a valid living county holder is saved as the completion character. An existing living payer is preserved. A dead payer is skipped, not replaced by the current county holder. If no living character is available, the character-specific reward block is skipped; the rest of the completion callback is preserved. A living callback emits `MQA_REWARD CALLBACK <building key>`; this is not evidence of a payment because native reward conditions may not be met.

## Protecting both recipients

The same generator extracts and overrides only two native effect keys into `common/scripted_effects/zz_mqa_mandala_reward_effects.txt`:

- `mandala_upgraded_temple_holding_effect`;
- `creator_mandala_upgraded_regular_holding_piety_effect`.

The helper entry also requires a living payer; a missing payer may fall back only to a living county holder. Each original `add_piety` is guarded by `is_alive = yes` on its actual recipient. This includes the secondary county-holder allocation in the temple helper, and callers outside the eight patched blocks, such as the castle level 2 callback. The existing government, house, aspect, house-head, branch conditions and reward amounts are preserved. No extra manual reward is added. No permanent per-building reward flag suppresses legitimate future upgrades.

For a dead payer, the entire character-specific helper path is skipped. For a living payer with a dead secondary recipient, only that secondary allocation is skipped. These are deliberate behavior changes while the mod is active, including ordinary construction, not merely error-message suppression.

## Payment and no-op audit

Each of the four original payment sites across the two effects retains exactly one `add_piety`, preceded by a piety snapshot and followed by a literal marker naming the effect and native allocation number:

```
MQA_REWARD PAYMENT mandala_upgraded_temple_holding_effect allocation=1
MQA_REWARD PIETY_INCREASED
```

A following scope dump saves `mqa_reward_recipient` and exposes the engine callback's root province. `PIETY_NOT_INCREASED` is used if no positive change occurred. `PAYMENT` establishes that the guarded add-piety call executed; it is not by itself proof of a positive gain. Skipped paths emit `MQA_REWARD SKIPPED ...` without executing or counting a payment.

Temple allocations 1 and 2 are the payer and secondary county-holder allocations of the first native branch. Allocation 3 belongs to its alternative branch. Preserve these distinctions when searching for duplicate upgrades: two native allocations are not automatically an unintended double reward, even if their recipient IDs coincide under the original conditions. Eligibility and allocation logic are intentionally not redesigned here.

Every actual recipient retains their latest `mqa_reward_piety_before`, `mqa_reward_piety_after`, `mqa_reward_last_gain` and a monotonic `mqa_reward_payments_total`. The counter records executed calls, not confirmed positive gains. These measurements do not pay rewards or depend on the decision's saved actor surviving into the callback context.

At BEGIN, the builder snapshots actor piety and the actor's payment counter. Immediately before END domain, the improvement action reports:

- `building_changes` or `no_building_changes` from its admitted mutation counters;
- `actor_piety_increased`, `actor_piety_decreased` or `actor_piety_unchanged`;
- `actor_reward_payments` or `actor_no_reward_payments`.

For a repeat with nothing left to improve while paused, the expected result is no building changes, unchanged actor piety, no actor payments **and no PAYMENT marker for any recipient inside that action's BEGIN/END interval**. This checks beneficiary rewards as well as the actor's balance. Numeric amounts remain on the characters because dynamic numeric localization failed in earlier logging; static markers and scope dumps do not need ROOT localization. The audit covers these two native reward effects, not unrelated sources of piety.

## Generation, compatibility and tests

The generator validates all three building inputs and both native reward definitions before writing any outputs. It rejects missing callbacks, changed helper names, unexpected character scopes, fallback shape changes or changed payment counts. Generated contents outside guard/audit edits are compared back to their installed source. Identical payment expressions in separate branches are patched by source position, preserving each original allocation once.

`-OutputPath` specifies the building output directory. The reward output defaults to its sibling `scripted_effects/zz_mqa_mandala_reward_effects.txt`; `-RewardOutputPath` overrides that file location. The separate mass-construction effects are not regenerated by this tool and their priorities are unchanged.

The game installation is untouched. However, the mod replaces three **complete building files**, so mods changing any of those files can conflict even outside the eight patched callbacks. Mods redefining either reward effect may conflict too. Regenerate and review after game updates; do not assume stale native copies are compatible with a newer game.

44 offline tests pass, including fixture and installed-source reversal checks, all native payment expressions/allocations preserved exactly once, living guards on both recipient paths, static no-op markers, output BOM/LF/braces and no timed event loop. These are script checks, distinct from the paused runtime result below. See [the current procedure](testing_building_decisions.md).

## Paused runtime result and 1.0.6 cleanup

On November 1, the restarted paused test produced two complete improvement actions. The first (13:43:10) recorded building changes and 142 positive payment allocations without repeated allocation/province/recipient keys. The second (13:43:17–13:43:18) recorded no building changes, unchanged player piety, no actor payments and no PAYMENT marker for any recipient. No completion/dead-character payment errors or epidemic-priority conflicts were present. This establishes absence of repeat rewards in that tested sequence; it does not cover every possible construction situation.

The remaining six mod diagnostic warnings were three unused-variable messages repeated twice. Version 1.0.6 removes the two unused initial domain snapshots and makes the skipped-construction counter drive a useful static result marker. Domain-change detection and reward audits are retained. The source cleanup has regression coverage; its startup warning result still needs the next game restart.

## Epidemic priority

The native `events/_events.info` documents default priority 0, highest-priority selection and different priorities for duplicate IDs. The generated override uses `id_override_priority = 1`; regeneration rejects a source event that gains an explicit priority. The restarted session confirmed disappearance of the earlier duplicate-priority error. Another mod at priority 1 can still conflict; higher-priority definitions supersede ours. Hot reload ignores priority according to the native documentation, so test with a complete restart.

The expired-epidemic branch still needs its own in-game validation; disappearance of the load conflict alone does not establish that scenario's behavior.
