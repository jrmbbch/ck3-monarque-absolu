# Changelog

## 1.0.6

- **Four independent domain decisions.** Fortify and arm the domain now only fills and upgrades existing buildings. Found new holdings, Convert holdings to castles and Grant secondary baronies are separate choices, each with its own one-shot event, static description and diagnostics. All nine translations are updated; Dream home remains separate.
- **Decision-screen freeze fixed.** Optimize the native saint-consecration site lookup by checking local cathedral/holy-site candidates before realm membership. Preserve the original eligibility branches. All ten former action decisions, plus the three new domain actions, execute their work only after confirmation through one-shot events; descriptions and tooltips no longer calculate live construction totals.
- **Correct holding foundations.** In empty non-capital baronies of personally held counties, found the missing government-appropriate temple (temple-citadel for mandala), the missing city, then castles. Check the game's first-level requirements for each type. Tribal and nomadic governments are excluded; unmet prerequisites leave the spot empty.
- **Controlled conversion and donations.** Conversion retains the existing eligible personal tribal/nomadic/herder-to-castle rules and may include county capitals. The separate grant decision covers all eligible personally held secondary cities, temples, castles and temple-citadels, including old/manual holdings and earlier conversions. Each recipient is generated with the ruler's culture, faith and rite as a direct vassal. County capitals, leased titles and clergy-reserved temples are protected from donation; other barons retain their holdings.
- **Batched title grants.** Snapshot candidates and resolve a single shared title-change transaction rather than one per barony. Verify recipient ownership, liege and identity after resolution. No candidate means no transaction or new recipient. There is no recurring construction loop or automatic chaining between the four actions.
- **Active construction protected.** Skip holdings under construction during domain building, foundation, conversion and donations, including personally held baronies outside personally held counties. Building requirements, priorities, available slots and the existing cost/time bypass remain; lower-priority buildings may be replaced. Dream home's existing cancellation/refund behavior is unchanged.
- **Mandala completion rewards repaired.** Guard eight castle, ordinary-temple and temple-citadel callbacks against missing or deceased payers. A missing payer can fall back to a living county holder; an existing dead payer is skipped. Guard both primary and secondary recipients in two native reward effects while preserving original eligibility, allocations and piety amounts. No extra manual reward is added.
- **Targeted epidemic fix.** The common-graves event checks whether its saved epidemic still exists before traversing infected counties. Explicit override priority 1 avoids the former conflict with vanilla priority 0. Other event choices and rewards remain unchanged.
- **Usable diagnostics.** Log action phases, domain-size/limit changes, actual piety-payment allocations and recipient contexts. Improvement runs distinguish building changes from a no-op, actor piety changes and audited payments. Remove two unused initial domain snapshots and report protected active constructions through the skipped counter, addressing the six repeated variable warnings.
- **Validation and maintenance.** Add PowerShell generators, fixtures, regression tests and game-test documentation for the fixes. The November 1 paused test confirmed 142 positive audited payments without repeated allocation/province/recipient keys on the first run, then no building changes, no payment and unchanged actor piety on the repeat. No completion or epidemic-priority errors appeared in that session. Exact performance and compatibility still depend on the save and other mods; the specific expired-epidemic scenario remains a separate runtime check.
- **Compatibility note.** In addition to the saint trigger and epidemic event, this version replaces three native building files and two reward-effect definitions. Game updates and mods touching those files/definitions require review; the game installation itself is not modified.

## 1.0.5

- **New interaction, Claim all their lands.** Grants pressed claims on the target's personal titles or their entire realm, including indirect vassals. Baronies, noble family titles, landless titles and titles already held by the actor are excluded. Titles and vassals stay with their current owners.
- **Whole realm selected by default** in both Seize all their titles and Claim all their lands; the personal domain remains available as an exclusive alternative.

## 1.0.4

- **New decision, Gather the realm.** Takes back, without war, every county, duchy and kingdom that belongs de jure to the duchies, kingdoms, empires and hegemonies you hold but is held from outside your realm. Counties come with their barons; your own vassals keep what they hold, and nothing outside your titles is touched.
- **New decision, An exceptional council** (and An ordinary council to revoke it). Each councillor gets +100 in the skill of their position: chancellor, marshal, steward, spymaster and court chaplain, plus the administrative ministers. A hidden monthly event gives it to new councillors; it is removed when a councillor leaves, is fired or swaps position, when the decision is revoked and when the ruler dies. The mod now has an `events` folder, copied by `tools/build_release.ps1`.
- **Louis XIV**: scheme phase duration -400 days for every category (contract schemes and skill-based modifiers included), which always reaches the game's 10-day minimum; 10 more hostile, personal, political and contract schemes.
- **Fortify and arm the domain** feudalizes the tribal, nomadic and herder holdings of your domain first, as the game's own feudalize holding action does (gold cost skipped), when your government is neither tribal nor of the steppe.
- **Seize interactions clarified**, with exclusive options and explicit labels:
  - Seize a title: the title alone, or the title and its vassals. The game moves a title's de jure vassals with it; with the title alone, they are handed back to their former lord if the lord still outranks them. Landless titles are listed with the others.
  - Seize all their titles (formerly Seize domain or realm): their domain, or their whole realm. The two options that made you a vassal of their liege are removed.

## 1.0.3

- **Building decisions follow the manual construction rules.** Fortify and arm the domain and Dream home only build what you could build by hand: innovations, holding levels and every other requirement of the game apply. Buildings go straight to the highest level allowed; costs and construction times are still skipped.
- **Fortify and arm the domain**:
  - also covers baronies you hold outside your own counties;
  - fills and upgrades three times, so buildings unlocked by another one at a high level (farm estates by pastures 4...) are built in a single click;
  - adds each building in one step instead of level by level, which slowed the game down on large domains;
  - upgrades duchy capital and special buildings with `replace_building_effect` (the game refused `add_building` for the examination hall);
  - warns about constructions underway in your domain: no script effect can cancel them, so they keep their slot until you cancel them by hand.
- **Dream home** cancels the domicile's ongoing construction first, refunded as by the game, and only attempts buildings whose requirements are met (no more refusals in the error log).
- **One realm, one faith** converts characters with `set_character_faith`: the conversion with checks refused some of them (Confucian lowborn barons, for instance).

## 1.0.2

- **Fixed a crash when right-clicking a character** with other mods installed. The mod's own interaction category used index 16, which other mods use too, and a duplicate index crashes the game. The mod no longer adds a category: its Monarque Absolu menu now reuses the slot of an unused base game debug category, so it cannot clash with other mods.
- Nicer icons for the interactions that revoke Louis XIV and all powers.

## 1.0.1

- **One realm, one faith** now also converts to your **rite** (By God Alone subdivides faiths into rites). Counties and characters that already shared your faith but followed another rite are converted too. Deceased children are no longer touched.
- The decision's description mentions the rite in every language.

## 1.0.0

First release on the Steam Workshop and Paradox Mods, for CK3 1.20 with every DLC up to By God Alone, in 9 languages.
