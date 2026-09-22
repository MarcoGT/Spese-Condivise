#!/usr/bin/env python3
"""Metadati App Store Connect come file di testo versionati.

    python3 tools/asc_metadata.py pull            # scarica la scheda in asc/metadata/
    python3 tools/asc_metadata.py push            # mostra cosa cambierebbe (non scrive)
    python3 tools/asc_metadata.py push --apply    # carica davvero
    python3 tools/asc_metadata.py new-version 2.3.7        # crea la prossima versione
    python3 tools/asc_metadata.py screenshots [--apply]    # sostituisce gli screenshot 6,9"

Parla solo con api.appstoreconnect.apple.com. La chiave resta in
~/.appstoreconnect/key.json (fuori dal repo) e non viene mai stampata.
Dipendenze: solo `cryptography`, niente fastlane/Ruby.

Non invia MAI l'app in revisione: quello resta un gesto manuale.
"""

import argparse
import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

BUNDLE_ID = "com.marcolagana.Spese-Condivise"
KEY_FILE = Path.home() / ".appstoreconnect" / "key.json"
API = "https://api.appstoreconnect.apple.com/v1"
METADATA_DIR = Path(__file__).resolve().parent.parent / "asc" / "metadata"

APP_INFO_FIELDS = {"name": "name.txt", "subtitle": "subtitle.txt"}
VERSION_FIELDS = {
    "description": "description.txt",
    "keywords": "keywords.txt",
    "promotionalText": "promotional_text.txt",
    "whatsNew": "release_notes.txt",
}
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170,
          "description": 4000, "whatsNew": 4000}

# Stati in cui Apple accetta modifiche ai testi di una versione.
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "INVALID_BINARY",
}


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_token() -> str:
    if not KEY_FILE.exists():
        sys.exit(f"Chiave non trovata: {KEY_FILE}")
    cfg = json.loads(KEY_FILE.read_text())
    pem = Path(cfg["key_filepath"]).expanduser().read_bytes()
    key = serialization.load_pem_private_key(pem, password=None)

    header = {"alg": "ES256", "kid": cfg["key_id"], "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": cfg["issuer_id"], "iat": now, "exp": now + 15 * 60,
               "aud": "appstoreconnect-v1"}
    signing_input = f"{_b64url(json.dumps(header).encode())}.{_b64url(json.dumps(payload).encode())}"

    # ES256 in un JWT vuole r||s grezzi (64 byte), non la firma DER di cryptography.
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return f"{signing_input}.{_b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


class ASC:
    def __init__(self):
        self.token = make_token()

    def request(self, method, path, body=None):
        url = path if path.startswith("http") else API + path
        req = urllib.request.Request(url, method=method)
        req.add_header("Authorization", f"Bearer {self.token}")
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, data, timeout=30) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            sys.exit(f"{method} {path} → HTTP {e.code}\n{detail}")

    def get(self, path, **params):
        if params:
            path += "?" + urllib.parse.urlencode(params)
        return self.request("GET", path)

    def patch(self, type_, id_, attributes):
        return self.request("PATCH", f"/{type_}/{id_}",
                            {"data": {"type": type_, "id": id_, "attributes": attributes}})


def find_app(asc):
    apps = asc.get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"Nessuna app con bundle id {BUNDLE_ID}")
    return apps[0]["id"]


def pick_app_info(asc, app_id):
    """L'appInfo modificabile, se c'è; altrimenti quella live (per il pull)."""
    infos = asc.get(f"/apps/{app_id}/appInfos")["data"]
    live_states = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE"}

    def state(i):
        a = i["attributes"]
        return a.get("state") or a.get("appStoreState") or ""

    editable = [i for i in infos if state(i) not in live_states]
    return (editable or infos)[0], bool(editable)


def pick_version(asc, app_id):
    versions = asc.get(f"/apps/{app_id}/appStoreVersions",
                       **{"filter[platform]": "IOS", "limit": 10})["data"]
    for v in versions:
        if v["attributes"]["appStoreState"] in EDITABLE_VERSION_STATES:
            return v, True
    return (versions[0] if versions else None), False


def load_state(asc):
    app_id = find_app(asc)
    info, info_editable = pick_app_info(asc, app_id)
    version, version_editable = pick_version(asc, app_id)

    info_locs = asc.get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]
    version_locs = (asc.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
                    if version else [])
    return {
        "version": version, "version_editable": version_editable,
        "info_editable": info_editable,
        "info_locs": {l["attributes"]["locale"]: l for l in info_locs},
        "version_locs": {l["attributes"]["locale"]: l for l in version_locs},
    }


def cmd_pull(asc):
    st = load_state(asc)
    v = st["version"]
    label = f"{v['attributes']['versionString']} ({v['attributes']['appStoreState']})" if v else "nessuna"
    print(f"Versione: {label}")
    for locale in sorted(set(st["info_locs"]) | set(st["version_locs"])):
        d = METADATA_DIR / locale
        d.mkdir(parents=True, exist_ok=True)
        for src, fields in (("info_locs", APP_INFO_FIELDS), ("version_locs", VERSION_FIELDS)):
            loc = st[src].get(locale)
            if not loc:
                continue
            for attr, fname in fields.items():
                (d / fname).write_text((loc["attributes"].get(attr) or "").rstrip() + "\n")
        print(f"  {locale} → {d.relative_to(METADATA_DIR.parent.parent)}")


def read_local(locale, fname):
    p = METADATA_DIR / locale / fname
    return p.read_text().rstrip("\n") if p.exists() else None


def cmd_push(asc, apply):
    st = load_state(asc)
    changes, problems = [], []

    for locale in sorted(p.name for p in METADATA_DIR.iterdir() if p.is_dir()):
        for src, fields, type_, editable in (
            ("info_locs", APP_INFO_FIELDS, "appInfoLocalizations", st["info_editable"]),
            ("version_locs", VERSION_FIELDS, "appStoreVersionLocalizations", st["version_editable"]),
        ):
            remote = st[src].get(locale)
            attrs = {}
            for attr, fname in fields.items():
                new = read_local(locale, fname)
                if new is None:
                    continue
                if len(new) > LIMITS[attr]:
                    problems.append(f"{locale}/{fname}: {len(new)} caratteri, limite {LIMITS[attr]}")
                old = (remote["attributes"].get(attr) or "").rstrip("\n") if remote else ""
                if new != old:
                    attrs[attr] = new
            if not attrs:
                continue
            if not remote:
                problems.append(f"{locale}: lingua non presente su App Store Connect")
                continue
            if not editable:
                problems.append(f"{locale}: {', '.join(attrs)} cambiati ma nessuna versione modificabile "
                                f"— crea la nuova versione in App Store Connect")
                continue
            changes.append((type_, remote["id"], locale, attrs))

    for _, _, locale, attrs in changes:
        for attr, val in attrs.items():
            preview = val if len(val) <= 80 else val[:77] + "..."
            print(f"  {locale:6} {attr:16} → {preview!r}")
    for p in problems:
        print(f"  ! {p}")

    if problems:
        sys.exit("Niente caricato: sistema i problemi sopra.")
    if not changes:
        print("Nessuna differenza con App Store Connect.")
        return
    if not apply:
        print("\nAnteprima. Per caricare: push --apply")
        return
    for type_, id_, locale, attrs in changes:
        asc.patch(type_, id_, attrs)
    print("Caricato. L'invio in revisione resta manuale.")


def cmd_new_version(asc, version_string):
    """Crea la versione in preparazione; Apple le copia testi e screenshot della precedente."""
    app_id = find_app(asc)
    current, editable = pick_version(asc, app_id)
    if editable:
        sys.exit(f"Esiste già una versione modificabile: {current['attributes']['versionString']}")
    asc.request("POST", "/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version_string},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
    }})
    print(f"Creata la versione {version_string} (in preparazione).")


SCREENSHOT_DIR = METADATA_DIR.parent / "screenshots"
SCREENSHOT_TYPE = "APP_IPHONE_67"  # casella del display 6,9" (1320×2868)


def upload_screenshot(asc, set_id, path):
    import hashlib
    data = path.read_bytes()
    res = asc.request("POST", "/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
    }})["data"]
    # I blocchi vanno su URL firmati da Apple, senza il nostro token.
    for op in res["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=120).read()
    asc.patch("appScreenshots", res["id"],
              {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
    return res["id"]


def cmd_screenshots(asc, apply):
    """Sostituisce gli screenshot 6,9" della versione in preparazione con asc/screenshots/<lingua>/."""
    st = load_state(asc)
    if not st["version_editable"]:
        sys.exit("Nessuna versione modificabile: crea prima la nuova versione (new-version).")
    for locale_dir in sorted(p for p in SCREENSHOT_DIR.iterdir() if p.is_dir() and p.name != "raw"):
        files = sorted(locale_dir.glob("[0-9][0-9].png"))
        loc = st["version_locs"].get(locale_dir.name)
        if not files or not loc:
            continue
        sets = asc.get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
        target = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == SCREENSHOT_TYPE), None)
        old = asc.get(f"/appScreenshotSets/{target['id']}/appScreenshots")["data"] if target else []
        print(f"  {locale_dir.name:6} {len(old)} vecchi → {len(files)} nuovi ({', '.join(f.name for f in files)})")
        if not apply:
            continue
        if not target:
            target = asc.request("POST", "/appScreenshotSets", {"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": SCREENSHOT_TYPE},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}},
            }})["data"]
        for s in old:
            asc.request("DELETE", f"/appScreenshots/{s['id']}")
        ids = [upload_screenshot(asc, target["id"], f) for f in files]
        asc.request("PATCH", f"/appScreenshotSets/{target['id']}/relationships/appScreenshots",
                    {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
    print("Caricati." if apply else "\nAnteprima. Per caricare: screenshots --apply")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("pull")
    p = sub.add_parser("push")
    p.add_argument("--apply", action="store_true")
    nv = sub.add_parser("new-version")
    nv.add_argument("version")
    sc = sub.add_parser("screenshots")
    sc.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    asc = ASC()
    if args.cmd == "pull":
        cmd_pull(asc)
    elif args.cmd == "push":
        cmd_push(asc, args.apply)
    elif args.cmd == "new-version":
        cmd_new_version(asc, args.version)
    else:
        cmd_screenshots(asc, args.apply)


if __name__ == "__main__":
    main()
