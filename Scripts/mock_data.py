#!/usr/bin/env python3
"""Generate realistic mock cycle data for Moonly.

Writes a plaintext data.json into ~/Library/Application Support/Moonly/.
The app reads plaintext via its migration path and re-encrypts on next save.

The timeline is built so "today" lands in the late-luteal PMS window (period in
~2 days) with PMS-type symptoms logged the last few days, so the new
intensity-aware "peak" header and supplement tips are visible immediately.
"""
import argparse
import json
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

TODAY = date(2026, 6, 20)
CYCLE_LEN = 27
PERIOD_LEN = 5

# Where in the cycle "today" should land, by scenario name -> cycle day.
SCENARIOS = {
    "menstrual": 2,
    "follicular": 9,    # normal, productive day
    "ovulatory": 13,
    "luteal-early": 18,
    "luteal-pms": 26,   # PMS peak, period in 2 days
}

# Set in main() once the scenario is chosen.
PERIOD_STARTS = []


def last_start_on_or_before(d):
    s = [x for x in PERIOD_STARTS if x <= d]
    return s[-1] if s else None


def phase_for(cd):
    ov = max(10, CYCLE_LEN - 14)  # 13
    if cd <= PERIOD_LEN:
        return "menstrual"
    if cd < ov - 1:
        return "follicular"
    if cd <= ov + 1:
        return "ovulatory"
    return "luteal"


def iso(d):
    # Noon UTC keeps the calendar day stable across time zones.
    return datetime(d.year, d.month, d.day, 12, 0, 0, tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sym(*names):
    return [{"rawValue": n} for n in names]


def make_log(d, cd):
    """Return a DailyLog dict, or None to leave the day unlogged."""
    phase = phase_for(cd)
    log = {
        "id": str(uuid.uuid4()).upper(),
        "date": iso(d),
        "isPeriod": False,
        "symptoms": [],
        "notes": "",
    }

    if phase == "menstrual":
        log["isPeriod"] = True
        flow = ["heavy", "heavy", "medium", "light", "spotting"][cd - 1]
        log["flow"] = flow
        if cd == 1:
            log["symptoms"] = sym("cramps", "fatigue", "backache")
            log["mood"], log["energy"] = "low", "low"
        elif cd == 2:
            log["symptoms"] = sym("cramps", "fatigue", "headache")
            log["mood"], log["energy"] = "low", "low"
        elif cd == 3:
            log["symptoms"] = sym("cramps", "backache")
            log["mood"], log["energy"] = "neutral", "low"
        elif cd == 4:
            log["mood"], log["energy"] = "neutral", "medium"
        else:
            log["mood"], log["energy"] = "good", "medium"
        return log

    if phase == "follicular":
        # Energy climbing; log lightly and skip some days for realism.
        if cd in (6, 8, 10):
            log["mood"] = "good" if cd != 10 else "great"
            log["energy"] = "high"
            if cd == 8:
                log["symptoms"] = sym("acne")
            return log
        return None  # unlogged day

    if phase == "ovulatory":
        log["mood"] = "great"
        log["energy"] = "high"
        if cd == 13:
            log["symptoms"] = sym("acne")
        return log

    # luteal
    if cd <= CYCLE_LEN - 6:  # early luteal: calmer
        if cd % 2 == 0:
            log["symptoms"] = sym("bloating", "cravings")
            log["mood"], log["energy"] = "neutral", "medium"
            return log
        return None
    # late luteal / PMS
    pms_by_offset = {
        0: (sym("bloating", "cravings", "breastTenderness"), "irritable", "low"),
        1: (sym("cramps", "fatigue", "bloating"), "low", "low"),
        2: (sym("cramps", "headache", "breastTenderness"), "anxious", "low"),
        3: (sym("bloating", "cravings"), "irritable", "medium"),
        4: (sym("breastTenderness", "fatigue"), "neutral", "medium"),
        5: (sym("bloating",), "neutral", "medium"),
    }
    offset = CYCLE_LEN - cd  # 0 == day before next period
    symptoms, mood, energy = pms_by_offset.get(offset, (sym("bloating"), "neutral", "medium"))
    log["symptoms"] = symptoms
    log["mood"], log["energy"] = mood, energy
    return log


def main():
    global PERIOD_STARTS
    parser = argparse.ArgumentParser(description="Generate Moonly mock data.")
    parser.add_argument("--lands", choices=SCENARIOS.keys(), default="follicular",
                        help="which phase 'today' should fall on (default: follicular)")
    args = parser.parse_args()

    target_cd = SCENARIOS[args.lands]
    last_start = TODAY - timedelta(days=target_cd - 1)
    # Four cycles of history ending with the current one.
    PERIOD_STARTS = [last_start - timedelta(days=CYCLE_LEN * i) for i in range(3, -1, -1)]

    logs = []
    d = PERIOD_STARTS[0]
    while d <= TODAY:
        start = last_start_on_or_before(d)
        cd = (d - start).days + 1
        if cd <= CYCLE_LEN:  # ignore overrun days between cycles (there are none here)
            entry = make_log(d, cd)
            if entry is not None:
                logs.append(entry)
        d += timedelta(days=1)

    payload = {
        "logs": logs,
        "cycleLengthOverride": None,
        "periodLengthOverride": None,
        "customSymptoms": None,
    }

    out = Path.home() / "Library/Application Support/Moonly/data.json"
    out.write_text(json.dumps(payload, indent=2))
    cd = (TODAY - PERIOD_STARTS[-1]).days + 1
    print(f"Wrote {len(logs)} logs to {out}")
    print(f"Scenario: {args.lands} -> today is cycle day {cd}, phase {phase_for(cd)}")
    print("Last period start:", PERIOD_STARTS[-1], "next period:", PERIOD_STARTS[-1] + timedelta(days=CYCLE_LEN))


if __name__ == "__main__":
    main()
