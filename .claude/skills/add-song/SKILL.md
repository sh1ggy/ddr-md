---
name: add-song
description: Add a new song (or a chart fix) to DDR MD over the air — scrape it from Zenius-I-vanisher, parse it in DDR-BPM-prep, copy it into the ddr-md-content repo, push, and confirm the publish is live. Use when the user says "add <song>", "push <song> to the app", "new WORLD song", or asks to ship a chart fix without a store release.
---

# Add a song

Adds one song end to end. Paths: prep is `~/repos/ddr-md/DDR-BPM-prep` (nested repo, poetry), content is `~/repos/ddr-md-content` (private, pushes to `master` publish to every installed app via CI). The song `name` is the ID everything keys on: never rename one that's already live.

Prep ships every scraped folder unless `data/removed.txt` names it, so a scraped song needs no list edit.

## Steps

1. **Find it.** Check whether the simfile is already on disk: `ls DDR-BPM-prep/data/*/ | grep -i "<name>"`. If not, find the Zenius simfile id (the `simfileid=` in its viewsimfile URL — ask the user if you can't find it) and the version folder (e.g. `WORLD`), add `<id>\t<VERSION>\t<title>` to `scripts/scrape/songs.txt`, and run `bash scripts/scrape/zenius_song.sh <id> <VERSION>` from the prep repo with `SEED_DIR=./data`.
2. **Check it isn't excluded.** `data/removed.txt` mustn't name it, and `data/title_map.csv` mustn't already cover it under another spelling.
3. **Parse.** `poetry run python src/parse_simfiles.py > <scratchpad>/parse.log 2>&1` from the prep repo (several minutes; run it in the background). Confirm `build/songs/<name>.json` and `build/steps/<name>.json` exist and grep the log for errors on that song. Then put the cabinet data back (the parse rewrites every song JSON without it): `poetry run python src/arcade_sync.py "<name>"` and `poetry run python src/arcade_timesigs.py "<name>"` (needs the dump in `data/arcade/`; see CODEBASE.md §6).
4. **Jackets.** `src="data/<VERSION>/<name>/<name>-jacket.png"`; copy it to `build/jackets/<name>.png` and `magick "$src" -resize 160x160 -quality 100 "build/jackets-160/<name>.png"`.
5. **Sanity-check the shape** against a live song: `diff <(jq -c 'paths|map(if type=="number" then 0 else . end)' build/songs/<name>.json | sort -u) <(jq -c '...same...' ~/repos/ddr-md-content/songs/<any>.json | sort -u)`. Missing `sync`/`arcade_sync`/`time_signatures` is fine (optional; `time_signatures` only appears on songs that aren't plain 4/4); anything else missing, stop and tell the user.
6. **Show the user** title, artist, version and chart levels, and get a yes before pushing — a push to content `master` goes live to every installed app within minutes.
7. **Publish.** In `~/repos/ddr-md-content`: copy the four files (`songs/`, `steps/`, `jackets/`, `jackets-160/`), `git add -A`, commit `content: <name> (<VERSION>)`, push. If the user wants to try it on a phone first, commit on the content repo's `staging` branch instead (`git switch staging && git merge master`), push that, and check `https://staging.ddr-md-content.pages.dev` in step 8; the phone needs a build with `--dart-define=CONTENT_URL=https://staging.ddr-md-content.pages.dev`. Once they're happy, merge `staging` into `master` and push.
8. **Confirm live.** Watch the run (`gh run list -R sh1ggy/ddr-md-content -L 1`, then `gh run watch <id> -R sh1ggy/ddr-md-content --exit-status`, ~2½ min), then check `curl -s https://ddr-md-content.pages.dev/manifest.json | jq '[.files|keys[]|select(test("<name>"))]'` lists its files.
9. **Wrap up.** Commit the `songs.txt` edit in the prep repo. Tell the user to sync from Settings → Song Updates on the phone to see it.

Several songs: run steps 1–5 for each, parse once, and publish them in one content commit.
