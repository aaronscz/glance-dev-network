# Sacred Heart Eagles Scoreboard (192x32, 3 pages).
#
# DESIGN. A purple-and-gold strip for East Grand Forks Sacred Heart that
# answers two questions from across the room: "how did we do?" and "when do
# we play next?". TITLE carries the identity (eagle + school name) and either
# a GAME DAY banner or the season records of the sports in season. SCORES is
# one row per sport in season - sport, W/L, score, opponent, date. NEXT is one
# row per sport in season - sport, day, date, opponent, time. Black ground,
# white for live data, gold for sport codes, green/red only for W/L.
#
# DATA. Everything comes from one JSON file the user keeps (a GitHub file is
# the suggested home - see README.md). A game with a score is a result; a game
# without one is upcoming. "In season" is worked out from the dates: a sport
# is shown while it has a result in the last ACTIVE_DAYS days or a game in the
# next ACTIVE_DAYS days, so fall/winter/spring switch over on their own.
#
# Glance pages are a fixed list, so instead of one page per sport (which would
# leave blank pages in a two-sport season) each page lists up to MAX_ROWS
# sports as rows.

FEED_TTL = 900        # seconds; matches refresh: 900 in manifest.yaml
ACTIVE_DAYS = 14      # a two-week window also spans the basketball holiday break
MAX_ROWS = 3          # three 7px rows is all 32px holds with a gap between them

# Safe zone for a 192-wide scroll app: other apps play right before and after.
X0 = 10
X1 = 181

PURPLE = "#7521F9"
GOLD = "#FFC20E"
WIN = "green"
LOSS = "red"
TIE = "amber"
LABEL = "gray"
ERR_HEAD = "#E8B04A"
ERR_SUB = "#6A7090"

DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

# ---------------------------------------------------------------- dates ----

def _dfc(y, m, d):
    """Days since 1970-01-01 (Howard Hinnant's days_from_civil)."""
    yy = y - 1 if m <= 2 else y
    era = (yy if yy >= 0 else yy - 399) // 400
    yoe = yy - era * 400
    mp = m - 3 if m > 2 else m + 9
    doy = (153 * mp + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468

def _civil(days):
    """Inverse of _dfc: day number -> (year, month, day)."""
    z = days + 719468
    era = (z if z >= 0 else z - 146096) // 146097
    doe = z - era * 146097
    yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp = (5 * doy + 2) // 153
    d = doy - (153 * mp + 2) // 5 + 1
    m = mp + 3 if mp < 10 else mp - 9
    y = yoe + era * 400
    return (y + 1 if m <= 2 else y, m, d)

def _weekday(days):
    """0 = Sunday. 1970-01-01 was a Thursday."""
    return (days + 4) % 7

# zone -> standard offset in minutes. All four observe US daylight saving:
# 2nd Sunday in March 02:00 -> 1st Sunday in November 02:00 (same rule as
# binary-clock, so no time API is needed and a dead API can't shift "today").
US_ZONES = {"EASTERN": -300, "CENTRAL": -360, "MOUNTAIN": -420, "PACIFIC": -480}

def _nth_sunday(y, m, n):
    wd = _weekday(_dfc(y, m, 1))
    return 1 + (7 - wd) % 7 + 7 * (n - 1)

def _today(ctx):
    """The viewer's local date as a day number."""
    zone = str(ctx.inputs.get("timezone", "CENTRAL") or "CENTRAL").strip().upper()
    std = US_ZONES.get(zone, -360)
    t = ctx.now.unix // 60
    y = ctx.now.year
    start = _dfc(y, 3, _nth_sunday(y, 3, 2)) * 1440 + 120 - std
    end = _dfc(y, 11, _nth_sunday(y, 11, 1)) * 1440 + 120 - std - 60
    off = std + 60 if (t >= start and t < end) else std
    return (ctx.now.unix + off * 60) // 86400

def _school_year_start(today):
    """Records count games since Aug 1 of the current school year."""
    y, m, d = _civil(today)
    return _dfc(y if m >= 8 else y - 1, 8, 1)

def _parse_date(s):
    """'2026-10-17' (anything after the first 10 chars is ignored) -> day number, or None."""
    s = str(s).strip()
    if len(s) < 10 or s[4] != "-" or s[7] != "-":
        return None
    yy, mm, dd = s[0:4], s[5:7], s[8:10]
    if not (yy.isdigit() and mm.isdigit() and dd.isdigit()):
        return None
    y, m, d = int(yy), int(mm), int(dd)
    if m < 1 or m > 12 or d < 1 or d > 31:
        return None
    return _dfc(y, m, d)

def _md(days):
    y, m, d = _civil(days)
    return "%d/%d" % (m, d)

# --------------------------------------------------------------- the feed ----

def _num(v):
    """A score from JSON: int, float, or digit string -> int; anything else -> None."""
    t = type(v)
    if t == "int":
        return v
    if t == "float":
        return int(v)
    if t == "string":
        s = v.strip()
        if s.isdigit():
            return int(s)
    return None

def _clean_time(s):
    """'7:00 PM' -> '7PM', '6:30 pm' -> '6:30PM'. Anything else is shown as typed."""
    s = str(s).strip().upper().replace(" ", "")
    s = s.replace(":00PM", "PM").replace(":00AM", "AM")
    return s

def _parse_games(feed):
    raw = feed.get("games", [])
    if type(raw) != "list":
        return []
    out = []
    for i in range(len(raw)):
        g = raw[i]
        if type(g) != "dict":
            continue
        sport = str(g.get("sport", "") or "").strip().upper()
        day = _parse_date(g.get("date", ""))
        if sport == "" or day == None:
            continue
        where = str(g.get("where", "") or "").strip().lower()
        us = _num(g.get("us"))
        them = _num(g.get("them"))
        # Meets (cross country, track, golf) have no head-to-head score; a
        # "result" string like "3RD OF 9" stands in for one.
        result = str(g.get("result", "") or "").strip().upper()
        numbered = us != None and them != None
        out.append({
            "i": i,
            "sport": sport,
            "day": day,
            "opp": str(g.get("opp", "") or "TBA").strip().upper(),
            "where": where,
            "time": _clean_time(g.get("time", "") or ""),
            "note": str(g.get("note", "") or "").strip().upper(),
            "us": us,
            "them": them,
            "numbered": numbered,
            "result": result,
            "scored": numbered or result != "",
        })
    return out

def _result(g):
    """('W', 'green') etc. for a scored game."""
    if g["us"] > g["them"]:
        return ("W", WIN)
    if g["us"] < g["them"]:
        return ("L", LOSS)
    return ("T", TIE)

def _versus(g):
    """Newspaper style: '@ FOSSTON' away, plain 'FOSSTON' at home or a neutral
    site. Dropping 'VS ' buys 3 characters: 'RED LAKE COUNTY' only fits the
    UPCOMING row's 74px at 4x7 without it."""
    if g["where"] == "away":
        return "@ " + g["opp"]
    return g["opp"]

def _sports(games, today):
    """Per sport in season: last result, next game, and season record."""
    sy = _school_year_start(today)
    names = []
    for g in games:
        if g["sport"] not in names:
            names.append(g["sport"])
    out = []
    for name in names:
        last = None
        nxt = None
        w, l, t = 0, 0, 0
        for g in games:
            if g["sport"] != name:
                continue
            if g["scored"]:
                # A score dated in the future is a typo in the file; ignore it
                # rather than showing tomorrow's "result" today.
                if g["day"] > today:
                    continue
                if last == None or g["day"] > last["day"] or (g["day"] == last["day"] and g["i"] > last["i"]):
                    last = g
                if g["day"] >= sy and g["numbered"]:
                    r = _result(g)[0]
                    if r == "W":
                        w += 1
                    elif r == "L":
                        l += 1
                    else:
                        t += 1
            elif g["day"] >= today:
                # An unscored game in the past is just waiting for its score
                # to be typed in, so it is neither a result nor upcoming.
                if nxt == None or g["day"] < nxt["day"]:
                    nxt = g
        recent = last != None and today - last["day"] <= ACTIVE_DAYS
        soon = nxt != None and nxt["day"] - today <= ACTIVE_DAYS
        rec = "%d-%d" % (w, l) + ("-%d" % t if t > 0 else "")
        out.append({
            "name": name,
            "last": last,
            "next": nxt,
            "active": recent or soon,
            "record": rec,
            "played": w + l + t,
        })
    return out

# Believable sample data, drawn relative to today so the demo always looks
# in season. Opponents are real Section 8A schools; the scores are made up.
DEMO_GAMES = [
    ["VB", -9, "home", "FOSSTON", 3, 0, ""],
    ["VB", -6, "away", "STEPHEN-ARGYLE", 3, 2, ""],
    ["VB", -2, "away", "BAGLEY", 3, 1, ""],
    ["VB", 2, "home", "RED LAKE COUNTY", None, None, "7:00 PM"],
    ["FB", -11, "home", "WARREN-ALVARADO-OSLO", 28, 14, ""],
    ["FB", -4, "away", "WIN-E-MAC", 14, 21, ""],
    ["FB", 3, "home", "BLACKDUCK", None, None, "7:00 PM"],
]

def _demo_feed(today):
    games = []
    for row in DEMO_GAMES:
        y, m, d = _civil(today + row[1])
        g = {"sport": row[0], "date": str(y) + "-" + fmt.pad(m, 2) + "-" + fmt.pad(d, 2), "where": row[2], "opp": row[3]}
        if row[4] != None:
            g["us"] = row[4]
            g["them"] = row[5]
        if row[6]:
            g["time"] = row[6]
        games.append(g)
    return {"school": "SACRED HEART", "mascot": "EAGLES", "games": games}

def _raw_link(url):
    """The most likely setup mistake is pasting a GitHub page link instead of
    the raw file link; those return HTML. Rewrite the two common shapes."""
    if "://github.com/" in url and "/blob/" in url:
        rest = url.split("://github.com/", 1)[1].replace("/blob/", "/", 1)
        return "https://raw.githubusercontent.com/" + rest
    if "://gist.github.com/" in url and "/raw" not in url:
        rest = url.split("://gist.github.com/", 1)[1].rstrip("/")
        return "https://gist.githubusercontent.com/" + rest + "/raw"
    return url

def _load(ctx):
    """-> {"state": live|demo|offline|notfound|badurl|notjson|nogames, ...}"""
    today = _today(ctx)
    url = str(ctx.inputs.get("feedurl", "") or "").strip()
    if url == "":
        feed = _demo_feed(today)
        state = "demo"
    else:
        if not (url.startswith("https://") or url.startswith("http://")):
            return {"state": "badurl", "today": today}
        resp = http.get(_raw_link(url), ttl_seconds = FEED_TTL)
        code = resp["status_code"]
        if code == 0:
            return {"state": "offline", "today": today}
        if code != 200:
            return {"state": "notfound", "code": code, "today": today}
        feed = resp["json"]
        if type(feed) != "dict":
            return {"state": "notjson", "today": today}
        state = "live"
    games = _parse_games(feed)
    if len(games) == 0:
        return {"state": "nogames", "today": today}
    return {
        "state": state,
        "today": today,
        "school": str(feed.get("school", "") or "SACRED HEART").strip().upper(),
        "mascot": str(feed.get("mascot", "") or "EAGLES").strip().upper(),
        "games": games,
        "sports": _sports(games, today),
    }

# Each state: (full-width head, sub) for SCORES/UPCOMING, then a short pair
# for TITLE's 61px right zone ("SCHEDULE FILE NOT FOUND" clipped to
# "SCHEDULE FIL.." there, so the title gets its own copy).
ERRORS = {
    "offline": ("SCORES OFFLINE", "WILL TRY AGAIN SOON", "OFFLINE", "RETRYING"),
    "notfound": ("SCHEDULE FILE NOT FOUND", "CHECK THE LINK", "NO FILE", "CHECK LINK"),
    "badurl": ("LINK NOT VALID", "START IT WITH HTTPS://", "BAD LINK", "USE HTTPS"),
    "notjson": ("FILE NOT READABLE", "USE THE RAW JSON LINK", "BAD FILE", "USE RAW LINK"),
    "nogames": ("NO GAMES IN FILE", "CHECK THE FILE FORMAT", "NO GAMES", "CHECK FILE"),
}
NO_DATA = ("NO DATA", "CHECK THE LINK", "NO DATA", "CHECK LINK")

# ---------------------------------------------------------------- drawing ----

def _fit_clip(c, s, x, y, fonts, maxw, color, align = "left"):
    """Largest font from the ladder that fits maxw; if none does, clip the
    smallest with '..'. Returns the drawn width."""
    s = s.upper()
    for f in fonts:
        w = c.text_width(s, f)
        if w <= maxw:
            c.text(s, x, y, font = f, color = color, align = align)
            return w
    f = fonts[-1]
    cut = s
    for n in range(len(s)):
        cut = s[0:len(s) - n - 1].rstrip(" -") + ".."
        if c.text_width(cut, f) <= maxw:
            break
    c.text(cut, x, y, font = f, color = color, align = align)
    return c.text_width(cut, f)

def _row_ys(n):
    """Top y of each 7px row, centered in 32px."""
    if n <= 1:
        return [12]
    if n == 2:
        return [6, 18]
    return [2, 12, 22]

def _message(c, head, sub, head_color = ERR_HEAD, sub_color = ERR_SUB):
    """Two centered lines on bands that can't overlap."""
    mid = (X0 + X1) // 2
    _fit_clip(c, head, mid, 6, ["7x10", "5x7b", "4x7"], X1 - X0, head_color, "center")
    _fit_clip(c, sub, mid, 20, ["5x7", "4x7"], X1 - X0, sub_color, "center")

def _sport_code(c, name, y):
    _fit_clip(c, name, X0, y, ["5x7b", "4x7", "4x5"], 18, GOLD)

# Bald eagle head facing right, in school colors: white head with a gray brow
# ridge, gold eye and hooked beak, ragged white neck feathers over purple
# shoulders. 24x24 at native size; nothing else may draw in x 10-33.
EAGLE = """
........WWWWW...........
......WWWWWWWWW.........
....WWWWWWWWWWWWW.......
...WWWWWWWWWWWWWWW......
..WWWWWWWWWWWWWWWWW.....
..WWWWWWWWWWDDDDDDWW....
.WWWWWWWWWWWWYKKYWWWW...
.WWWWWWWWWWWWWYYWWWWYYY.
.WWWWWWWWWWWWWWWWWWYYYYY
WWWWWWWWWWWWWWWWWYYYYYYY
WWWWWWWWWWWWWWWWYYYYYYYY
WWWWWWWWWWWWWWWWYYYY.YYY
WWWWWWWWWWWWWWWWWYY...YY
WWWWWWWWWWWWWWWYYYY...Y.
WWWWWWWWWWWWWWWWW.......
WWWWWWWWWWWWWWWW........
.WWWWWWWWWWWWWW.........
..WWWWWWWWWWWW..........
W.WWW.WWWWWWW...........
PW.W.WW.WWW.............
PPWPWPPWPW..............
PPPPPPPPPP..............
PPPPPPPPPPP.............
PPPPPPPPPPPP............
"""
EAGLE_LEGEND = {"W": "white", "Y": GOLD, "K": "black", "D": "#5A5A6E", "P": PURPLE}

def _eagle(c, x, y):
    c.sprite(EAGLE, x, y, legend = EAGLE_LEGEND)

# ------------------------------------------------------------------ pages ----

def title(c, ctx):
    c.clear()
    data = _load(ctx)
    state = data["state"]
    school = data.get("school", "SACRED HEART")
    mascot = data.get("mascot", "EAGLES")

    # Identity block: eagle, then school name over mascot.
    _eagle(c, X0, 4)
    tx = X0 + 28
    _fit_clip(c, school, tx, 3, ["5x7b", "4x7"], 72, GOLD)
    _fit_clip(c, mascot, tx, 13, ["10x16_bold", "7x12", "5x7b"], 72, "white")

    # Right zone: game day banner, season records, or the error.
    zx = 120
    c.vline(zx - 5, 3, 26, color.dim(PURPLE, 70))
    if state not in ("live", "demo"):
        e = ERRORS.get(state, NO_DATA)
        _fit_clip(c, e[2], zx, 7, ["5x7b", "4x7", "4x5"], X1 - zx, ERR_HEAD)
        _fit_clip(c, e[3], zx, 18, ["4x7", "4x5"], X1 - zx, ERR_SUB)
        return

    today = data["today"]
    lines = []
    todays = [g for g in data["games"] if g["day"] == today and not g["scored"]]
    if state == "demo":
        lines.append(("DEMO", ERR_HEAD, "badge"))
    if len(todays) > 0:
        lines.append(("GAME DAY", GOLD, "badge"))
        for g in todays:
            lines.append((g["sport"] + " " + (g["time"] or "TODAY"), "white", "pair"))
    else:
        active = [s for s in data["sports"] if s["active"] and s["played"] > 0]
        for s in active:
            lines.append((s["name"] + " " + s["record"], "white", "pair"))
        if len(active) == 0:
            lines.append(("OFF", LABEL, "text"))
            lines.append(("SEASON", LABEL, "text"))

    ys = _row_ys(min(len(lines), MAX_ROWS))
    for i in range(min(len(lines), MAX_ROWS)):
        s, col, kind = lines[i]
        y = ys[i]
        if kind == "badge":
            # Black 5x7b on a filled pill, 1px padding all round (9px tall, so
            # a 10px row pitch still leaves a 1px gap to the next row).
            w = c.text_width(s, "5x7b")
            c.round_rect(zx, y - 1, zx + w + 3, y + 7, 1, fill = col)
            c.text(s, zx + 2, y, font = "5x7b", color = "black")
        elif kind == "pair":
            # Gold sport code on the left, its record or start time right-aligned.
            name, rec = s.split(" ", 1)
            nw = _fit_clip(c, name, zx, y, ["5x7b", "4x7"], 22, GOLD)
            _fit_clip(c, rec, X1, y, ["5x7", "4x7"], X1 - zx - nw - 4, "white", "right")
        else:
            _fit_clip(c, s, zx, y, ["5x7", "4x7"], X1 - zx, col)

def scores(c, ctx):
    c.clear()
    data = _load(ctx)
    if data["state"] not in ("live", "demo"):
        e = ERRORS.get(data["state"], NO_DATA)
        _message(c, e[0], e[1])
        return

    rows = [s for s in data["sports"] if s["active"] and s["last"] != None]
    rows = sorted(rows, key = lambda s: -s["last"]["day"])
    if len(rows) == 0:
        _message(c, "NO GAMES THIS WEEK", "GO " + data["mascot"] + "!", GOLD, PURPLE)
        return

    rows = rows[0:MAX_ROWS]
    ys = _row_ys(len(rows))
    for i in range(len(rows)):
        g = rows[i]["last"]
        y = ys[i]
        _sport_code(c, rows[i]["name"], y)
        sx = X0 + 30
        if g["numbered"]:
            letter, col = _result(g)
            c.text(letter, X0 + 21, y, font = "5x7b", color = col)
            # The score always stays 5x7 ("102-99" is 35px); a note like OT goes
            # after it in quieter 4x7 gray, so a long note can't shrink the score.
            score = "%d-%d" % (g["us"], g["them"])
            sw = _fit_clip(c, score, sx, y, ["5x7", "4x7"], 40, "white")
        else:
            # A meet: its result text ("3RD OF 9") takes the W/L + score columns.
            sw = _fit_clip(c, g["result"], X0 + 21, y, ["5x7", "4x7"], 50, "white") - 9
        if g["note"]:
            sw += 3 + _fit_clip(c, g["note"], sx + sw + 3, y, ["4x7", "4x5"], 16, LABEL)
        date = _md(g["day"])
        dw = c.text_width(date, "4x7")
        c.text(date, X1, y, font = "4x7", color = LABEL, align = "right")
        ox = sx + sw + 6
        _fit_clip(c, _versus(g), ox, y, ["5x7", "4x7"], X1 - dw - 5 - ox, "white")

def upcoming(c, ctx):
    c.clear()
    data = _load(ctx)
    if data["state"] not in ("live", "demo"):
        e = ERRORS.get(data["state"], NO_DATA)
        _message(c, e[0], e[1])
        return

    today = data["today"]
    rows = [s for s in data["sports"] if s["active"]]
    if len(rows) == 0:
        # Off season: show the next game anywhere in the file, if any.
        ahead = [s for s in data["sports"] if s["next"] != None]
        if len(ahead) == 0:
            _message(c, "SCHEDULE COMING SOON", "GO " + data["mascot"] + "!", GOLD, PURPLE)
            return
        rows = ahead
    # Soonest game first; a sport with nothing left on its schedule goes last.
    rows = sorted(rows, key = lambda s: s["next"]["day"] if s["next"] != None else 999999)
    rows = rows[0:MAX_ROWS]
    ys = _row_ys(len(rows))
    for i in range(len(rows)):
        s = rows[i]
        y = ys[i]
        _sport_code(c, s["name"], y)
        g = s["next"]
        dx = X0 + 21
        if g == None:
            lw = c.text_width("SEASON", "5x7")
            c.text("SEASON", dx, y, font = "5x7", color = LABEL)
            c.text(s["record"], dx + lw + 6, y, font = "5x7", color = "white")
            continue
        if g["day"] == today:
            dw = c.text_width("TODAY", "5x7b")
            c.text("TODAY", dx, y, font = "5x7b", color = WIN)
            ox = dx + dw + 6
        else:
            c.text(DOW[_weekday(g["day"])], dx, y, font = "5x7b", color = "white")
            date = _md(g["day"])
            c.text(date, dx + 22, y, font = "5x7", color = "white")
            ox = dx + 22 + c.text_width("12/31", "5x7") + 6
        right = X1
        if g["time"]:
            tw = _fit_clip(c, g["time"], X1, y, ["4x7", "4x5"], 30, LABEL, "right")
            right = X1 - tw - 5
        _fit_clip(c, _versus(g), ox, y, ["5x7", "4x7"], right - ox, "white")
