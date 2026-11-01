> Historical analysis. Since November 1, the domain action is split into four independent decisions. See [the current test procedure](testing_building_decisions.md); the combined sequence below describes the earlier build.

# Live CPU diagnosis of the decision-screen freeze

## Evidence

The 23:11–23:13 session still froze on opening decisions despite moving the mod's action effects to one-shot events. Its only construction execution, at 23:12:25, began and ended in the same recorded second. The earlier epidemic tooltip error storm was absent. These logs could not explain the remaining UI freeze.

With the user reproducing the freeze, macOS `sample` captured CK3 PID 81550 for ten seconds on October 22, 2026 at 23:16:40 (Europe/Paris). Raw local diagnostic: `/tmp/mqa-ck3-decisions-freeze.sample.txt`. The startup reference is `/tmp/mqa-ck3-baseline.sample.txt`; it was taken during initialization and is not an idle in-game benchmark.

Of 4,598 main-thread samples, 4,569 (99.4%) were in:

```
CDecisionsView::Update
  CDecisionsView::OnDirtyUpdate
    CExecuteDecisionCommand::IsValid
      CDecisionType::IsValidForScope
        realm-province iterator
          neighboring-county iterator
            scripted trigger
              realm-province iterator
                CIsHolySiteOfTrigger
```

This locates the sampled bottleneck in decision validity checks, rather than construction execution or effect-tooltip expansion. Source inspection identifies the matching nested traversal in the vanilla `pam_has_free_adjacent_site_trigger` and `pam_county_has_actor_primary_site_trigger` in `common/scripted_triggers/pam_saint_triggers.txt`. The saint canonization/consecration decisions call those checks from their validity requirements.

For every candidate county neighboring a realm province, the original county trigger scans the actor's entire realm again to find a cathedral or holy site in that one county. For the holy-site branch, it even tests holy-site status before comparing the county. On a large realm this multiplies the traversal cost.

## Targeted override

`common/scripted_triggers/zz_mqa_pam_saint_performance_triggers.txt` overrides only `pam_county_has_actor_primary_site_trigger`. The game installation is not edited.

The override first enumerates the queried county's few provinces and tests whether each is an actual cathedral/holy-site candidate. Only a genuine candidate needs the native `any_realm_province` membership check. Counties without a site therefore do not initiate another whole-realm search.

The membership check deliberately retains the original native realm iterator instead of approximating realm membership with title-holder or top-liege comparisons. This preserves unusual realm layouts. The actor's own cathedral special case, faith-dependent cathedral/holy-site branches and use of occupied primary sites all remain. No saint is created, moved or removed by the trigger.

The override's benefit depends on the number of actual site candidates. It removes the identified repeated search for the common case of neighboring counties with no primary site; it does not promise constant cost for arbitrary numbers of cathedrals. A second mod overriding the same vanilla key can conflict. Review against vanilla changes after updates.

## Validation

Offline checks cover the local-site-first ordering, narrow native membership checks, both faith branches, the own-cathedral exception, absence of mutation and absence of extra occupancy restrictions. These checks do not execute the CK3 engine.

Restart CK3 so the script database reloads, load the same save and open the same decision screen without confirming a decision. Capture another sample if it still stalls; compare the main-thread stacks with the recorded bottleneck. A successful offline suite alone is not evidence that the in-game freeze is fixed.

After deployment and restart, a second live capture at 23:21:46 sampled PID 81782 for eight seconds (`/tmp/mqa-ck3-decisions-after.sample.txt`). The decision view is present in this capture. `CExecuteDecisionCommand::IsValid` now accounts for 200 of 3,175 main-thread samples (6.3%), compared with 4,568 of 4,598 (99.3%) during the freeze. The remaining stacks include normal rendering and other interface updates. The post-restart log does not report a parse error for the override.

This is live evidence that the sampled validity bottleneck was substantially reduced. The captures have different durations and do not establish an exact opening latency, frame rate or speedup factor. The user subsequently confirmed that the decision screen was fluid again. All 35 offline checks at that stage passed.
