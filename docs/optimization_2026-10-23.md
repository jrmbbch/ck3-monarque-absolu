> Historical analysis. Since November 1, the domain action is split into four independent decisions. See [the current test procedure](testing_building_decisions.md); the combined sequence below describes the earlier build.

# October 23: mass construction and epidemic tooltip fix

## Donations and performance

The October 22 test spent 67 seconds in foundation. The live command-thread sample includes repeated `CResolveTitleAndVassalChangeEffect`/`CTitleAndVassalChange::Execute`, recalculations and game-state lock waits, as well as character creation. The earlier helper resolved a title-change transaction for every individual donation.

The new sequence is conversion, foundation, the existing upgrade/fill passes, then donation. The actor's eligible personally held barony titles are collected into an execution-local list. If the candidate count is zero, no transaction or recipient is created. Otherwise, one shared `granted` transaction is created, one generated recipient is queued per title, all title/liege changes are staged, and the transaction is resolved once. A second local list retains the recipients and each recipient's temporary expected-title variable for verification after resolution; those variables are then removed.

Verification checks the expected title's actual holder, direct liege, culture, faith and rite. The relevant snapshot is completed before changing any owners. No recurring event, persistent task queue or background scheduler is added. The existing priorities and four upgrade/three fill passes remain unchanged. Character generation and the engine's automatic assignments still have costs; this change does not establish a specific new execution time without an in-game same-save comparison.

## Existing personal holdings

Eligibility now covers all personally held secondary cities, temples, castles and temple-citadels, including those built manually or converted in earlier mod versions. It does not require a provenance flag. County capitals, active constructions, already leased titles and church holdings reserved for clergy leasing are excluded. Existing vassal barons retain their titles. Newly created city holders that the engine has already assigned are not replaced by the personal-title snapshot.

These are deliberate title donations: the player's eligible personal domain size will decrease after resolution. The first run may now process more titles than the previous new-foundation-only policy. Compare both the elapsed time and the number of candidates rather than comparing executions with different work already completed.

## Epidemic error status

No epidemic fix had been applied before this change. The already verified decision-screen fix concerns saint consecration, a separate bottleneck.

The new `events/zz_mqa_epidemic_events.txt` overrides only vanilla event `epidemic_events.1110`. In option b, it wraps the infected-county traversal in an `exists = scope:epidemic_scope` guard. When the saved epidemic has expired, neither the realm traversal nor the invalid comparison is reached. When it still exists, the original infected-county logic is retained. The other option, rewards, stress effects, AI weights, presentation, trigger and immediate setup are preserved.

`tools/generate_epidemic_fix.ps1` extracts this one event from the installed game's source and inserts the guard. It fails if the expected event or traversal cannot be found, requiring review after an incompatible game update. Tests compare everything outside the guarded loop with the original and compare the committed override with regeneration from the installed version. This targets the specific expired-reference tooltip flood, not every disease-related error in CK3. The original game files are not modified. Other mods overriding the same event may conflict.

## Validation

Offline checks cover the frozen title list, one guarded transaction, no resolution inside the per-title helper, protection predicates, existing-holding inclusion, post-resolution verification and temporary-variable cleanup. Additional fixture/installed-game checks cover the epidemic guard and preservation of unrelated event behavior. All nine descriptions are updated.

In-game validation is still needed for the new batching and the expired-epidemic branch. Restart CK3, use the same pre-construction save for a timing comparison, run once, and preserve the BEGIN/PHASE/RESULT/END markers. No reduction from 67 seconds is claimed before that measurement. For the epidemic case, a pending common-graves event referencing an epidemic that has disappeared must no longer emit the invalid-reference storm when its second option is hovered.
