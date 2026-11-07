---
name: add-song
description: Add a new song (or a chart fix) to DDR MD over the air through the release console — scrape it from Zenius-I-vanisher, prepare it in DDR-BPM-prep, draft and stage a release, and make it live once the user signs it off. Use when the user says "add <song>", "push <song> to the app", "new WORLD song", or asks to ship a chart fix without a store release.
---

# Add a song

Everything goes through the release console in `~/repos/ddr-md/DDR-BPM-prep`: `poetry run python -m admin <command>` from there (the page, `make admin`, runs the same code). Never copy files into `~/repos/ddr-md-content` or push it yourself: CI refuses content without the console's `release.json`. The song `name` is the ID everything keys on: never rename one that's already live.

## Steps

1. **Find it.** `python -m admin inbox` lists songs in the game with no simfile yet. If it isn't on disk (`ls data/*/ | grep -i "<name>"`), find its Zenius simfile id (the `simfileid=` in its viewsimfile URL; ask the user if you can't) and add it from the console's inbox (Scrape), or `python -m admin seed-add songs "<id>\t<VERSION>\t<title>" --why "scrape <title>"` then `python -m admin job scrape_song simfile_id=<id> version=<VERSION>`.
2. **Prepare.** `python -m admin job prepare` (several minutes; run it in the background). For one song already parsed, `python -m admin job song song="<name>"` rebuilds just its sync, arcade data, tiers and jacket.
3. **Link its Konami ID.** `python -m admin job konami_relink` (a song new to Konami needs `job konami_fetch`, which uses the user's cookie from the Keychain). If it's still unlinked, link it on its song page, then rebuild its data.
4. **Check the diff.** `python -m admin diff "<name>"` shows what changes for players. A warning like missing Konami ID or arcade sync: fix it or tell the user before going on.
5. **Draft and check.** `python -m admin draft "<name>" --title "<name> (<VERSION>)" --kind add` (use `--kind fix` for a chart fix), then `python -m admin checks`. Fix anything it reports.
6. **Show the user** title, artist, version, chart levels and the diff, and get a yes before staging.
7. **Stage.** `python -m admin stage` pushes the release to the content repo's `staging` branch and opens its PR. CI publishes it to `https://staging.ddr-md-content.pages.dev` in about 5 minutes (`python -m admin status`).
8. **Sign off is the user's.** They test on a phone following staging (long-press Song Updates) and sign off in the console, or tell you how they tested and you run `python -m admin signoff "<their words>"`. That fast-forwards `master` and goes live to every installed app.
9. **Confirm.** `python -m admin status` shows `confirmed: true` once the live id equals the one tested. Tell the user to sync from Settings → Song Updates on the phone to see it.

Several songs: prepare once and draft them in one release.
