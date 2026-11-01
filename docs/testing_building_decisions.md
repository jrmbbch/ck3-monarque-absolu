# Testing the four domain decisions

Version 1.0.6 prepared on November 1, 2026; not yet published. Restart CK3 after installing the local build, then load a copy of the affected save with Monarque Absolu enabled. Show the builder powers to reveal four domain decisions plus the separate Dream home decision.

The former combined action is split into:

| Decision | Expected action | Log BEGIN/END label |
| --- | --- | --- |
| Fortify and arm the domain | Building fill/upgrade passes in existing holdings only | `domain` |
| Found new holdings | Empty secondary baronies only | `foundation` |
| Convert holdings to castles | Eligible personal tribal/nomadic/herder holdings only | `conversion` |
| Grant secondary baronies | Eligible existing personal secondary holdings only | `grants` |
| Dream home | Existing domicile cancel/refund, upgrade, fill, upgrade behavior | `domicile` |

## Interface and independence

1. Open the decision screen, select each action and hover its confirmation button without confirming. The screen should remain fluid and emit no `MQA_BUILD` markers. Each description, tooltip and confirmation must exist in all nine languages. Showing/hiding the builder affects all four domain actions and the domicile action together; the domicile still requires an actual domicile.
2. Use separate copies of the same save to test each domain action independently. Confirm that improvements do not convert/found/donate; foundation does not run building improvement passes or custom donations; conversion does not found/upgrade/donate; grants do not construct/convert. Native foundation/conversion callbacks may initialize holdings, and the engine may automatically assign some new holders; these are distinct from the custom grant action.
3. Record both personal domain size and domain limit before and after each action, plus elapsed time. A decrease in personal holdings after explicit donations is expected. Investigate any unexplained limit change.

## Existing buildings

Test existing holdings in personally held counties, including vassal barons, and personally held baronies outside those counties. Four upgrade passes alternate with three fill passes, preserving fortifications, levies, then income priority. Lower-priority buildings may be replaced. Prerequisites apply; costs and times are skipped; no slots are added. Holdings with active construction must keep their buildings, type, owner and project.

## Foundation

Test a personally held county with several empty non-capital baronies. The missing government-appropriate temple comes first, then the missing city, then castles. Mandala uses temple-citadels; other governments use ordinary temples. Test each stage with its requirements met and unmet: a blocked required type leaves the spot empty instead of bypassing the requirement. Tribal and nomadic rulers are excluded. Empty baronies with active construction are protected. Founding does not automatically invoke the mod's improvement or donation action.

## Conversion

Test controlled personal tribal, nomadic and herder holdings, including county capitals, for a ruler who is neither tribal nor of the steppe. Eligible holdings become castles without a gold charge. Holdings outside those conditions or under active construction must remain untouched. County capitals can be converted, but the separate donation decision must never grant them away.

## Mandala rewards and epidemic load priority

The November 1 test ran conversions, foundations and grants within their respective single logged seconds; improvements ran from 10:05:31 to 10:05:32. All actions reached END, grants were verified without a failure marker, and no domain-limit change was recorded. However, improvements emitted 644 castle and 431 temple-citadel completion errors with a missing character. Startup also reported the epidemic event duplicated at priority 0. These are the pre-repair observations, not validation of the new fixes.

The initial repair removed the epidemic priority conflict and missing-character errors for castles/temple-citadels. The follow-up still recorded 22 ordinary-temple errors in the first improvement run and four native temple-citadel payments to dead characters outside the decision. The current repair covers eight callbacks in three native-path files, preserves a living payer, allows a missing payer to fall back to a living county holder, and skips a dead payer. Two reward-effect overrides additionally guard each actual recipient. See [the implementation and compatibility notes](mandala_completion_fix_2026-11-01.md).

1. Completely restart CK3. Check startup errors: `epidemic_events.1110` must no longer have two definitions at the same priority. The mod's definition explicitly uses priority 1; vanilla defaults to 0.
2. On a copy of a save from before improvements, test castles reaching levels 3/4, ordinary temples reaching levels 2/3/4 and temple-citadels reaching levels 2/3/4. Confirm buildings actually reach the permitted levels and the missing-character errors disappear. Test own holdings and vassal barons in personally held counties.
3. Record piety before/after while paused and compare with the original reward conditions (government, house/aspect, house-head status and relevant game values). A missing payer falls back to the county holder. The original reward helper remains responsible for eligibility and amounts; do not expect a fixed reward in every case. Repeat improvements with nothing left to upgrade: no upgrade reward should be generated again.
4. Verify ordinary paid construction still attributes the reward to the real payer, including a payer different from the county holder. Also test non-mandala recipients, an ownerless holding, a deceased recorded payer, and a deceased secondary beneficiary. No invalid-character or dead-recipient payment error should occur. Do not substitute a new recipient for an existing dead payer. Valid ordinary construction must keep its original payer and rewards.
5. For the epidemic, test a pending common-graves second option both with a valid saved epidemic and after it disappears. The valid case must retain its native effects; the expired case must not traverse infected counties or flood errors. Restart instead of relying on hot reload: the game's event documentation says hot reload ignores override priority.

The 44 offline checks cover preserved callback content, one audit pair per original payment, living-recipient guards, unchanged native definitions/allocations outside the patches, source-change rejection, explicit event priority, no-op audit markers and exact regeneration from installed CK3 1.20.1.2. Runtime rewards, actual callback execution and the expired-epidemic scenario remain to be verified in game.


### Repeat audit: proving no extra reward

Keep the game paused throughout two consecutive improvement actions. Start from a copy of a pre-improvement save; do not change ownership, government, culture, innovations or prerequisites between the two actions. Do not issue another construction order. Separate each BEGIN/END domain block; events outside it are not payments made by that decision.

The first run should report `MQA_BUILD RESULT building_changes` when it does work. Actual payments from the two repaired native reward effects have this sequence:

```
MQA_REWARD PAYMENT <effect name> allocation=<native branch number>
MQA_REWARD PIETY_INCREASED
[scope dump including mqa_reward_recipient and the root province]
```

`PIETY_NOT_INCREASED` instead records an executed call that did not produce a positive gain; do not count such a call as a confirmed positive payment. `MQA_REWARD CALLBACK <building key>` identifies an alive-builder callback, not a payment: eligibility may result in no reward. `MQA_REWARD SKIPPED no_living_builder ...` and `SKIPPED dead_recipient ...` must not have a corresponding PAYMENT for that skipped path.

Temple allocations 1 and 2 are the native first branch's payer/secondary county-holder payments; allocation 3 is the alternative primary-payer branch. Two distinct native allocations for an eligible upgrade are not automatically a duplicate. Keep their roles and recipient scope dumps separate. The repair does not alter the game's allocation conditions or suppress legitimate subsequent upgrades.

For the unchanged repeat, require all of:

- `MQA_BUILD RESULT no_building_changes`;
- `MQA_BUILD RESULT actor_piety_unchanged`;
- `MQA_BUILD RESULT actor_no_reward_payments`;
- no `MQA_REWARD PAYMENT` between that BEGIN and END, including payments to other recipients;
- no new missing-character or dead-recipient errors.

If these do not all hold, the repeat is not established as reward-free: inspect new prerequisites/construction, reward allocation contexts and other piety changes instead of declaring a pass. No-op checks remain static summaries after execution, never UI traversal. There is no scheduled audit event and no gameplay change that masks duplicate payouts.

The actor keeps `mqa_b_piety_before` and `mqa_b_reward_payments_before` for the last builder action. Each actual recipient keeps `mqa_reward_payments_total` (monotonic executed-payment count), `mqa_reward_piety_before`, `mqa_reward_piety_after` and `mqa_reward_last_gain` for their latest audited payment. These are not reset globally between actions: a recipient may receive more than one legitimate native allocation. Inspect variables in debug mode/debug saves when exact amounts are needed; log markers use no dynamic numeric localization. Auditing covers these two repaired reward effects, not every source of piety in CK3.
## Donations

Include existing personal cities, temples, castles and temple-citadels: manually built, newly founded and converted in earlier runs. Each eligible secondary title should go to one generated noble of the ruler's culture, faith and rite as a direct vassal. Verify actual ownership and liege after the shared transaction.

County capitals, active construction, leased titles and church holdings reserved for clergy leasing must remain protected. Test a clergy-leasing faith/rite separately. Other barons must keep their titles. Repeat the grant decision: already granted titles must not receive another recipient. With no candidates, there must be no new noble or title-change transaction. Temporary `mqa_b_expected_title` variables on recipients must be removed.

## Timing and diagnostics

If performing all actions, the suggested order is conversion, foundation, improvements, then grants. This ensures newly created holdings receive improvements before they leave personal ownership. There is no combined decision and no automatic chaining. Each action resets the last-run counters; preserve its results before executing another.

Preserve `Documents/Paradox Interactive/Crusader Kings III/logs/debug.log` and `error.log` before restarting CK3: startup rewrites them. Logging depends on the game's debug configuration. Search `debug.log` for `MQA_BUILD`. Each confirmation must have one matching BEGIN/END pair for its action, with no automatic repeat.

- `domain`: count_constructions, pass=1, pass=2, pass=3, final_upgrade.
- `foundation`: found, result markers, end.
- `conversion`: feudalize, end.
- `grants`: prepare_grants, optionally resolve_grants exactly once, result markers, end.
- `domicile`: upgrade=1, construct, upgrade=2.

Domain changes emit literal `MQA_BUILD DOMAIN_SIZE_CHANGED` and `MQA_BUILD DOMAIN_LIMIT_CHANGED` markers. Outcomes include `holdings_founded`, `grants_verified`, `foundation_requirements_blocked`, `grant_failed` and `grant_skipped`. Numeric values are retained as character variables, not interpolated into logs:

| Variables | Meaning |
| --- | --- |
| `mqa_b_run` | Monotonic number of confirmed builder actions |
| `mqa_b_holdings`, `mqa_b_skipped` | Eligible existing holdings and existing holdings under construction (building action) |
| `mqa_b_added`, `mqa_b_upgraded`, `mqa_b_removed` | Admitted building mutation calls |
| `mqa_b_founded`, `mqa_b_feudalized`, `mqa_b_foundation_blocked` | Foundation/conversion calls and blocked foundation spots |
| `mqa_b_grant_candidates`, `mqa_b_granted`, `mqa_b_grant_failed`, `mqa_b_grant_skipped` | Queued, verified, failed and protected/skipped grants |
| `mqa_b_domain_after` | Latest personal domain size; initialized at BEGIN, compared and updated after the action |
| `mqa_b_domain_limit_after` | Latest domain limit; initialized at BEGIN, compared and updated after the action |
| `mqa_b_domicile_changes`, `mqa_b_cancelled` | Domicile mutation/cancellation calls |

The historical October 22 run spent 67 seconds in foundation with per-title donations, before transaction batching and before the split. It is not a measurement of this build. Compare the total time of all four new actions on the same untouched save, and record each duration and candidate count. Repeating on an already built/granted domain is not comparable. Splitting actions alone does not prove a performance gain.

## Latest paused validation and diagnostic cleanup

The restarted November 1 session contains two complete improvement runs. At 13:43:10 the first run changed buildings and recorded 142 payment allocations, all with a positive piety-change marker and no repeated building/effect/allocation/province/recipient key. At 13:43:17–13:43:18 the repeat reported no building changes, unchanged actor piety and no actor payments; there was no PAYMENT marker for any recipient inside that second action. No completion errors, dead-character payment errors or epidemic-priority conflict appeared in this session. This validates the observed repeat, not all future saves or the expired-epidemic scenario.

Six startup warnings represented three unused variables reported twice. Version 1.0.6 removes the unused `mqa_b_domain_before` and `mqa_b_domain_limit_before` assignments. The still-useful `mqa_b_skipped` counter is now consumed by `MQA_BUILD RESULT active_constructions_skipped` when it is positive. The last-measurement variables and domain-change markers remain intact. Offline regression checks cover this cleanup; confirm warning disappearance at the next complete game restart. Unrelated game errors are outside this claim.

## Other pending regression checks

The saint decision validity optimization previously restored UI fluidity, confirmed by CPU sampling and the user. Keep checking that opening decisions remains fluid; see [the CPU analysis](analysis_2026-10-22_decision_cpu.md).

The separate epidemic override still needs the runtime checks above. Other choices and rewards should be preserved. The event, saint trigger, three building-file replacements and two reward-effect overrides may conflict with mods editing the same definitions/files.

Smoke-test the other one-shot decisions (money, culture, faith/rite, realm recovery, council on/off and both healing actions). Offline tests do not validate CK3 engine behavior. Historical reports remain in [the October 22 analysis](analysis_2026-10-22_decisions.md) and [the October 23 optimization notes](optimization_2026-10-23.md).
