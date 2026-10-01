#!/usr/bin/env python3
"""
Live demo: Offensive Message Detection System
Sends real messages to the running Java API and prints formatted results.
"""
import requests
import time
import json

API = "http://localhost:8080/api"
ML  = "http://localhost:5001/api/ml"

RED    = "\033[91m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
RESET  = "\033[0m"

MESSAGES = [
    ("I hate you so much, you are completely worthless",  "twitter",   "troll_99"),
    ("Go kill yourself, nobody likes you loser",          "facebook",  "anon_user"),
    ("You are the ugliest and dumbest person alive",      "instagram", "hater_x"),
    ("I will find you and hurt you badly",                "twitter",   "threat_bot"),
    ("Good morning! Hope everyone has a wonderful day",   "instagram", "happy_user"),
    ("Congratulations on your graduation! So proud",      "facebook",  "friend_22"),
    ("Can anyone help me with my Python homework?",       "twitter",   "student_42"),
    ("Shut up you stupid idiot, no one cares",            "twitter",   "troll_99"),
    ("Beautiful sunset today, feeling so grateful",       "instagram", "nature_fan"),
    ("You make me sick with your disgusting opinions",    "facebook",  "angry_99"),
    ("Just finished reading an amazing book, loved it!",  "twitter",   "reader_01"),
    ("Die in a fire you worthless piece of trash",        "facebook",  "extremist_7"),
]

SEVERITY_COLOR = {
    "high":   RED,
    "medium": YELLOW,
    "low":    CYAN,
    "none":   GREEN,
}

def banner():
    print(f"\n{BOLD}{'='*65}{RESET}")
    print(f"{BOLD}   OFFENSIVE MESSAGE DETECTION SYSTEM — LIVE DEMO{RESET}")
    print(f"{BOLD}{'='*65}{RESET}")
    print(f"{DIM}   Java API  → {API}{RESET}")
    print(f"{DIM}   ML Engine → {ML}{RESET}")
    print(f"{BOLD}{'='*65}{RESET}\n")

def analyze_message(text, platform, author):
    r = requests.post(f"{API}/messages/analyze",
                      json={"text": text, "author": author, "platform": platform},
                      timeout=10)
    return r.json()

def print_result(i, text, result):
    label     = result.get("label", "?")
    offensive = result.get("isOffensive", False)
    conf      = result.get("confidence", 0)
    severity  = result.get("severity", "none")
    status    = result.get("status", "?")
    platform  = result.get("platform", "?")
    author    = result.get("author", "?")

    icon  = "🚨" if offensive else "✅"
    scol  = SEVERITY_COLOR.get(severity, RESET)
    lcol  = RED if offensive else GREEN

    print(f"{BOLD}[{i:02d}] {icon}  {lcol}{label.upper()}{RESET}  "
          f"│  confidence: {BOLD}{conf:.0%}{RESET}  "
          f"│  severity: {scol}{BOLD}{severity.upper()}{RESET}  "
          f"│  status: {BOLD}{status}{RESET}")
    print(f"      {DIM}platform: {platform}  │  author: {author}{RESET}")
    print(f"      \"{text[:72]}{'…' if len(text)>72 else ''}\"")
    print()

def print_stats(stats):
    total   = stats.get("total", 0)
    off     = stats.get("offensive", 0)
    normal  = stats.get("normal", 0)
    rate    = stats.get("offensiveRate", 0)
    sev     = stats.get("bySeverity", {})

    print(f"{BOLD}{'─'*65}{RESET}")
    print(f"{BOLD}  FINAL STATISTICS{RESET}")
    print(f"{BOLD}{'─'*65}{RESET}")
    print(f"  Total messages analyzed : {BOLD}{total}{RESET}")
    print(f"  Offensive (flagged)     : {RED}{BOLD}{off}{RESET}  ({rate:.0%})")
    print(f"  Normal (cleared)        : {GREEN}{BOLD}{normal}{RESET}")
    print(f"  By severity:")
    print(f"    🔴  High    : {RED}{BOLD}{sev.get('high',0)}{RESET}")
    print(f"    🟡  Medium  : {YELLOW}{BOLD}{sev.get('medium',0)}{RESET}")
    print(f"    🔵  Low     : {CYAN}{BOLD}{sev.get('low',0)}{RESET}")
    print(f"{BOLD}{'─'*65}{RESET}\n")

def main():
    banner()
    print(f"{BOLD}Submitting {len(MESSAGES)} messages for analysis...{RESET}\n")

    for i, (text, platform, author) in enumerate(MESSAGES, 1):
        result = analyze_message(text, platform, author)
        print_result(i, text, result)
        time.sleep(0.3)

    # Stats
    stats = requests.get(f"{API}/messages/stats", timeout=5).json()
    print_stats(stats)

    # Show open moderator queue
    flagged = requests.get(f"{API}/messages/offensive", timeout=5).json()
    print(f"{BOLD}  MODERATOR QUEUE — {len(flagged)} message(s) flagged{RESET}")
    print(f"{BOLD}{'─'*65}{RESET}")
    for msg in flagged:
        scol = SEVERITY_COLOR.get(msg.get("severity","none"), RESET)
        print(f"  {scol}[{msg.get('severity','?').upper()}]{RESET}  "
              f"{DIM}{msg.get('platform','?')} / {msg.get('author','?')}{RESET}")
        txt = msg.get('text','')
        print(f"  \"{txt[:70]}{'…' if len(txt)>70 else ''}\"")
    print(f"{BOLD}{'='*65}{RESET}\n")

if __name__ == "__main__":
    main()
