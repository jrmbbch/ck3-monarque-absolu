# Changelog

## 1.0.4

- **New decision, Gather the realm.** Takes back, without war, every county, duchy and kingdom that belongs de jure to the duchies, kingdoms, empires and hegemonies you hold but is held from outside your realm. Counties come with their barons; your own vassals keep what they hold, and nothing outside your titles is touched.
- **New decision, An exceptional council** (and An ordinary council to revoke it). Each councillor gets +100 in the skill of their position: chancellor, marshal, steward, spymaster and court chaplain, plus the administrative ministers. A hidden monthly event gives it to new councillors; it is removed when a councillor leaves, is fired or swaps position, when the decision is revoked and when the ruler dies. The mod now has an `events` folder, copied by `tools/build_release.sh`.
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
