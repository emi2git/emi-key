#!/usr/bin/env python3
"""Build Emi Key's offline data.

Resources/pinyin.tsv   simplified \t traditional \t pinyin (tone digits, space separated) \t freq
Resources/english.txt  common English words, lowercase, one per line

Usage: python3 -I scripts/build-data.py [download_dir]
Sources: CC-CEDICT (CC BY-SA 4.0), jieba dict.txt (MIT), FrequencyWords en_50k (MIT),
google-10000-english 20k (public), /usr/share/dict/words.
"""
import gzip, os, re, sys, tempfile, urllib.request
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Resources")
URLS = {
    "cedict.txt.gz": "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz",
    "jieba.txt": "https://raw.githubusercontent.com/fxsjy/jieba/master/jieba/dict.txt",
    "en_50k.txt": "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt",
    "en20k.txt": "https://raw.githubusercontent.com/first20hours/google-10000-english/master/20k.txt",
}
SKIP_TAGS = re.compile(r"\((vulgar|offensive|derog)", re.I)
SYL = re.compile(r"^[a-z]+[1-5]$")
HAN = re.compile(r"^[㐀-鿿豈-﫿]+$")


def fetch(d):
    for name, url in URLS.items():
        p = os.path.join(d, name)
        if not os.path.exists(p):
            urllib.request.urlretrieve(url, p)
    return {n: os.path.join(d, n) for n in URLS}


def norm_syllable(s):
    s = s.lower().replace("u:", "v").replace("ü", "v")
    return s


def build_pinyin(f):
    freq = {}
    with open(f["jieba.txt"], encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                freq[parts[0]] = int(parts[1])
    # characters get the larger of their own count or 1/4 of the words they appear in
    char_from_words = defaultdict(int)
    for w, n in freq.items():
        if len(w) > 1:
            for ch in w:
                char_from_words[ch] += n

    rows = {}
    line_re = re.compile(r"^(\S+) (\S+) \[([^\]]+)\] /(.*)/$")
    with gzip.open(f["cedict.txt.gz"], "rt", encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("#"):
                continue
            m = line_re.match(line.strip())
            if not m:
                continue
            trad, simp, py, gloss = m.groups()
            if not HAN.match(simp) or not HAN.match(trad) or SKIP_TAGS.search(gloss):
                continue
            syls = [norm_syllable(s) for s in py.split()]
            if len(syls) != len(simp) or not all(SYL.match(s) for s in syls):
                continue
            n = freq.get(simp, 0)
            if len(simp) == 1:
                n = max(n, char_from_words.get(simp, 0) // 4)
            # surname-only and variant entries rank last
            if py[:1].isupper() and len(simp) > 1:   # proper nouns (names) rank below ordinary words
                n = n if n >= 200 else 0
            if gloss.startswith("surname ") or "variant of" in gloss or "old variant" in gloss:
                n = min(n, 1)
            py = " ".join(syls)
            key = (simp, py)
            if key not in rows or rows[key][1] < n:
                rows[key] = (trad, n)
    out = os.path.join(RES, "pinyin.tsv")
    with open(out, "w", encoding="utf-8") as fh:
        for (simp, py), (trad, n) in sorted(rows.items(), key=lambda kv: (kv[0][1], -kv[1][1])):
            fh.write(f"{simp}\t{trad}\t{py}\t{n}\n")
    return out, len(rows)


def build_english(f):
    dict_words = set()
    if os.path.exists("/usr/share/dict/words"):
        with open("/usr/share/dict/words", encoding="utf-8", errors="ignore") as fh:
            dict_words = {w.strip().lower() for w in fh if w.strip().isalpha()}
    with open(f["en20k.txt"], encoding="utf-8") as fh:
        common = {w.strip().lower() for w in fh if w.strip().isalpha()}
    words = []
    with open(f["en_50k.txt"], encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) == 2 and parts[0].isalpha() and parts[0].isascii():
                w = parts[0].lower()
                if w in dict_words or w in common:
                    words.append(w)
    seen = set(); final = []
    for w in words + sorted(common):
        if w not in seen and (len(w) > 1 or w in ("a", "i")):
            seen.add(w); final.append(w)
    out = os.path.join(RES, "english.txt")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(final) + "\n")
    return out, len(final)


if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="emikey-data-")
    os.makedirs(RES, exist_ok=True)
    f = fetch(d)
    p, n = build_pinyin(f)
    e, m = build_english(f)
    print(f"{p}: {n} entries, {os.path.getsize(p)//1024} KB")
    print(f"{e}: {m} words, {os.path.getsize(e)//1024} KB")
