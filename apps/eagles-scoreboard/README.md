# Sacred Heart Eagles Scoreboard

Latest score and next game for every East Grand Forks Sacred Heart sport that's
in season, on a 192x32 Glance Scroll strip.

| Page | Shows |
| --- | --- |
| `title` | Eagle + school name, plus the season record of each sport in season. On a game day it shows **GAME DAY** and the start times instead. |
| `scores` | One row per sport in season: sport, W/L, score, opponent, date. Newest first. |
| `upcoming` | One row per sport in season: sport, day, date, opponent, start time. Soonest first; **TODAY** in green on game day. |

A sport counts as **in season** while it has a result in the last 14 days or a
game in the next 14 days, so fall, winter and spring switch over on their own.
Each page shows at most 3 sports (three rows is all 32 pixels holds). If four
are in season, SCORES drops the one that played longest ago and UPCOMING drops
the one whose next game is furthest off.

With no schedule link set, the app shows demo data labelled **DEMO**.

## The schedule file

The app reads one JSON file that you keep up to date. `sample-schedule.json`
in this folder is a starting point (its games and scores are made up).

```json
{
  "school": "Sacred Heart",
  "mascot": "Eagles",
  "games": [
    {"sport": "VB", "date": "2026-10-15", "where": "away", "opp": "Bagley", "us": 1, "them": 3},
    {"sport": "VB", "date": "2026-10-22", "where": "home", "opp": "Red Lake County", "time": "7:00 PM"},
    {"sport": "XC", "date": "2026-10-14", "where": "away", "opp": "Pine to Prairie Meet", "result": "3rd of 9"}
  ]
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `sport` | yes | A short code, 3 letters or fewer fits best: `FB`, `VB`, `BBB`, `GBB`, `BHK`, `GHK`, `WR`, `BSB`, `SB`, `XC`, `TR`, `GLF`. Whatever you type is what shows. |
| `date` | yes | `YYYY-MM-DD`. |
| `opp` | yes | Opponent or meet name. Keep it short - around 14 characters fits without being cut (`Stephen-Argyle`, not `Stephen-Argyle Central`). |
| `where` | no | `home`, `away` or `neutral`. Away games show as `@ BAGLEY`. |
| `time` | upcoming games | Shown as typed, tidied up (`7:00 PM` shows as `7PM`). |
| `us`, `them` | results | Our score first. Volleyball is sets (`3`, `1`). Add both after the game and it moves from UPCOMING to SCORES. |
| `note` | no | Short tag after a score, like `OT` or `2OT`. |
| `result` | meets | For meets with no head-to-head score: `3rd of 9`, `1st`. Not counted in the record. |

A game with a score (or a `result`) is a result; a game without one is
upcoming. A past game with no score yet is simply skipped until you add it.
Records count results since August 1 of the current school year. Other fields
(like `_note`) are ignored.

## Hosting it on GitHub (free)

1. Create a public repository on github.com (for example `eagles-schedule`) and
   add a file named `schedule.json` with the contents of `sample-schedule.json`.
2. Open the file on GitHub, click **Raw**, and copy that address. It looks like
   `https://raw.githubusercontent.com/<you>/eagles-schedule/main/schedule.json`.
3. Paste it into the app's **Schedule file URL** setting.

To add a score, open the file on GitHub (the phone browser works), click the
pencil, add `"us"` and `"them"` to the game, and commit. The sign picks it up
within about 20 minutes (15-minute refresh plus GitHub's own caching).

Pasting the ordinary GitHub page link (`github.com/.../blob/...`) also works;
the app rewrites it to the raw link. Links that redirect, like Google Drive or
Dropbox share links, won't work because the panel's fetcher doesn't follow
redirects.

## Where the scores come from

Minnesota schools post their scores on their team pages at mshsl.org (for
example mshsl.org/schools/sacred-heart-school/volleyball-girls), which is also
where most of minnesota-scores.net's data comes from. Those sites have no feed
the panel can read directly, which is why this app uses a file you control.

## Settings

| Setting | What it does |
| --- | --- |
| Schedule file URL | Link to the JSON file. Blank shows demo data. |
| Time zone | Decides what "today" is (game day, TODAY, the 14-day window). Daylight saving is automatic. |
