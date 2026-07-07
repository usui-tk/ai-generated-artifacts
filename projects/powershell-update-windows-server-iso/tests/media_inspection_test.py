#!/usr/bin/env python3
"""T38: media-inspection engine contract (offline).

Pins the r11.59 `media-inspection` arc [user-adjudicated 2026-07-07]:
full pre/post media inspection (P06 / P11), pure diff + observe-first
cross-checks (P13), and the burial of P11's dead verification path
(Get-WindowsPackage was invoked with -ImagePath/-Index -- an invalid
parameter set that threw on every OS and was swallowed by a catch, so
the Kb rows and the TBAU hard check had never actually run).

Layers:
  1. REPL `ConvertFrom-InspectionBuildValue`: live-string, JSON
     {Major, Minor} shape, REPL hashtable shape, null, and the
     Major=-1 sentinel all normalise correctly.
  2. REPL `Compare-MediaInspection` over synthetic pre/post objects:
     build advance, package-count delta, 2024-4B prereq flip, boot
     _EX payload appearance, and a post-missing index.
  3. REPL `Get-InspectionCrossChecks` (observe-first): disabled+
     advanced -> Warning; enabled+unchanged -> Warning; tolerate+
     advanced -> Info (flip-to-enabled evidence); tolerate+unchanged
     -> Info (tolerated path); bridge-need confirmed vs redundant.
  4. REPL `Get-KbAliasFromPatchPath`: Catalog parent/child KB alias
     extraction (.NET offering KB vs installed child KB).
  5. Data audit: across all four committed configs, a KbId that
     differs from the KB embedded in FileName occurs ONLY on
     Kind=DotNet Lines (the verified parent/child structure); any
     other divergence fails the audit and forces investigation.
  6. Structure pins: P06 writes inspection_pre.json; P11 emits the
     SHA-256 content-identity rows, writes inspection_post.json, and
     derives Kb/TBAU from measured evidence; P13 diffs + cross-checks;
     the invalid `ImagePath = $installWim` Get-WindowsPackage call is
     gone.

Exit code 0 on full pass, 1 on any failure.
"""
from __future__ import annotations

import pathlib
import re
import sys

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
sys.path.insert(0, str(TESTS_DIR))
from common.ps_invoke import PSSession  # type: ignore  # noqa: E402

SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"

PASS = "  PASS"
FAIL = "  FAIL"


def check(label, ok, detail, p, f):
    if ok:
        print(f"{PASS}  {label}: {detail}")
        return p + 1, f
    print(f"{FAIL}  {label}: {detail}")
    return p, f + 1


def vstr(v):
    if isinstance(v, dict) and "Major" in v:
        return f"{v['Major']}.{v['Minor']}"
    return None if v is None else str(v)


def mk_index(idx, build, pkg_count, prereq, kind="install", efi_ex=False, error=None):
    rec = {
        "Kind": kind,
        "Index": idx,
        "Evidence": {"Build": build, "MeetsPca2023Prereq": prereq},
        "PackageNames": [f"pkg{n}" for n in range(pkg_count)],
        "ErrorMessage": error,
    }
    if kind == "boot":
        rec["HasEfiExDir"] = efi_ex
    return rec


def mk_inspection(label, install_idx, boot_idx, install_sha, boot_sha):
    return {
        "Label": label,
        "OsKey": "Server2022",
        "MediaRoot": "D:\\\\x",
        "Timestamp": "2026-07-07T00:00:00",
        "InstallWim": {"Present": True, "Sha256": install_sha, "Indexes": install_idx},
        "BootWim": {"Present": True, "Sha256": boot_sha, "Indexes": boot_idx},
        "BootStlPaths": [],
        "ErrorMessage": None,
    }


def main() -> int:
    p = 0
    f = 0
    with PSSession(SCRIPT_PATH) as ps:
        print("=== 1. ConvertFrom-InspectionBuildValue ===")
        got = ps.invoke("ConvertFrom-InspectionBuildValue", Value="20348.5256.1.13")
        p, f = check("string shape", vstr(got) == "20348.5256", f"got={got!r}", p, f)
        got = ps.invoke("ConvertFrom-InspectionBuildValue",
                        Value={"Major": 20348, "Minor": 5256, "Build": -1})
        p, f = check("{Major, Minor} shape", vstr(got) == "20348.5256", f"got={got!r}", p, f)
        got = ps.invoke("ConvertFrom-InspectionBuildValue", Value=None)
        p, f = check("null -> null", got is None, f"got={got!r}", p, f)
        got = ps.invoke("ConvertFrom-InspectionBuildValue",
                        Value={"Major": -1, "Minor": -1})
        p, f = check("Major=-1 sentinel -> null", got is None, f"got={got!r}", p, f)

        print("=== 2. Compare-MediaInspection ===")
        pre = mk_inspection(
            "pre",
            [mk_index(1, "20348.587", 10, False), mk_index(2, "20348.587", 10, False)],
            [mk_index(1, "20348.587", 5, False, kind="boot", efi_ex=False)],
            "aaa", "bbb")
        post = mk_inspection(
            "post",
            [mk_index(1, "20348.5256", 14, True)],  # idx 2 missing post
            [mk_index(1, "20348.5256", 7, True, kind="boot", efi_ex=True)],
            "ccc", "ddd")
        diff = ps.invoke("Compare-MediaInspection", Pre=pre, Post=post)
        wims = {w["Wim"]: w for w in diff.get("Wims", [])}
        inst = {ix["Index"]: ix for ix in wims["InstallWim"]["Indexes"]}
        boot = {ix["Index"]: ix for ix in wims["BootWim"]["Indexes"]}
        p, f = check(
            "install idx1: build advance + package delta + prereq flip",
            inst[1]["BuildAdvanced"] is True
            and vstr(inst[1]["BuildBefore"]) == "20348.587"
            and vstr(inst[1]["BuildAfter"]) == "20348.5256"
            and inst[1]["PackageCountBefore"] == 10
            and inst[1]["PackageCountAfter"] == 14
            and inst[1]["PrereqBefore"] is False and inst[1]["PrereqAfter"] is True,
            f"idx1={inst[1]!r}"[:140], p, f)
        p, f = check(
            "install idx2 missing post -> PostMissing, no advance",
            inst[2]["PostMissing"] is True and inst[2]["BuildAdvanced"] is False,
            f"PostMissing={inst[2]['PostMissing']!r}", p, f)
        p, f = check(
            "boot idx1: _EX payload appearance detected",
            boot[1]["ExPayloadAppeared"] is True,
            f"ExPayloadAppeared={boot[1]['ExPayloadAppeared']!r}", p, f)
        p, f = check(
            "WIM SHA change surfaced",
            wims["InstallWim"]["ShaChanged"] is True and wims["BootWim"]["ShaChanged"] is True,
            "both changed", p, f)

        print("=== 3. Get-InspectionCrossChecks (observe-first) ===")
        def run(policy, pre_boot, post_boot, bridge=None, pre_install=None):
            out = ps.invoke("Get-InspectionCrossChecks",
                            BootWimLcuPolicy=policy,
                            BridgeMinimumStack=bridge,
                            PreInstallBuild=pre_install,
                            PreBootBuild=pre_boot, PostBootBuild=post_boot)
            # a single finding round-trips as a dict, not a 1-list
            if isinstance(out, dict):
                return [out]
            return out or []

        fd = run("disabled", "17763.107", "17763.8880")
        fd0 = ([x for x in fd if x["Kind"] == "boot-policy"] or [{}])[0]
        p, f = check("disabled + measured advance -> Warning",
                     fd0.get("Level") == "Warning", f"{fd0.get('Message','')[:80]!r}", p, f)
        fd = run("enabled", "14393.6796", "14393.6796")
        fd0 = ([x for x in fd if x["Kind"] == "boot-policy"] or [{}])[0]
        p, f = check("enabled + no advance -> Warning",
                     fd0.get("Level") == "Warning", f"{fd0.get('Message','')[:80]!r}", p, f)
        fd = run("tolerate", "20348.587", "20348.5256")
        fd0 = ([x for x in fd if x["Kind"] == "boot-policy"] or [{}])[0]
        p, f = check("tolerate + advance -> Info with flip-to-enabled evidence",
                     fd0.get("Level") == "Info" and "enabled" in fd0.get("Message", ""),
                     f"{fd0.get('Message','')[:90]!r}", p, f)
        fd = run("tolerate", "20348.587", "20348.587")
        fd0 = ([x for x in fd if x["Kind"] == "boot-policy"] or [{}])[0]
        p, f = check("tolerate + no advance -> Info tolerated path",
                     fd0.get("Level") == "Info" and "tolerated" in fd0.get("Message", ""),
                     f"{fd0.get('Message','')[:90]!r}", p, f)
        fd = run("tolerate", "20348.587", "20348.587",
                 bridge="20348.1960", pre_install="20348.587")
        fdb = ([x for x in fd if x["Kind"] == "bridge-need"] or [{}])[0]
        p, f = check("bridge need CONFIRMED (pre build below floor) -> Info",
                     fdb.get("Level") == "Info" and "CONFIRMED" in fdb.get("Message", ""),
                     f"{fdb.get('Message','')[:90]!r}", p, f)
        fd = run("tolerate", "20348.587", "20348.587",
                 bridge="20348.1960", pre_install="20348.2402")
        fdb = ([x for x in fd if x["Kind"] == "bridge-need"] or [{}])[0]
        p, f = check("bridge redundant (pre build meets floor) -> Warning",
                     fdb.get("Level") == "Warning" and "redundant" in fdb.get("Message", ""),
                     f"{fdb.get('Message','')[:90]!r}", p, f)

        print("=== 4. Get-KbAliasFromPatchPath (Catalog parent/child KB) ===")
        got = ps.invoke("Get-KbAliasFromPatchPath", KbId="KB5088862",
                        Path="D:\\patches\\Server2022\\dotnet\\windows10.0-kb5087068-x64-ndp48_abc.msu")
        p, f = check("parent KbId + child file -> child alias",
                     got == "KB5087068", f"got={got!r}", p, f)
        got = ps.invoke("Get-KbAliasFromPatchPath", KbId="KB5094128",
                        Path="windows10.0-kb5094128-x64_f2fe.msu")
        p, f = check("matching KB ids -> no alias", got is None, f"got={got!r}", p, f)
        got = ps.invoke("Get-KbAliasFromPatchPath", KbId="KB5094128", Path="")
        p, f = check("empty path -> no alias", got is None, f"got={got!r}", p, f)

    print("=== 5. Data audit: KbId/FileName divergence is DotNet-only ===")
    import glob as _glob
    import json as _json
    offenders = []
    for cf in sorted(_glob.glob(str(SUBPROJECT_ROOT / "data" / "config-Server*.json"))):
        cfg = _json.load(open(cf, encoding="utf-8-sig"))
        for ln in cfg["PatchBaseline"]["Lines"]:
            kb = ln.get("KbId", "") or ""
            fn = ln.get("FileName", "") or ""
            m = re.search(r"(?i)kb(\d{6,7})", fn)
            if m and ("KB" + m.group(1)).lower() != kb.lower() and ln.get("Kind") != "DotNet":
                offenders.append(f"{pathlib.Path(cf).name}:{ln.get('Kind')}:{kb}/{fn[:40]}")
    p, f = check(
        "non-DotNet Lines never diverge (parent/child KB is a .NET Catalog structure)",
        offenders == [],
        "clean" if not offenders else f"offenders={offenders!r}", p, f)

    print("=== 6. Structure pins ===")
    code = SCRIPT_PATH.read_text(encoding="utf-8-sig")
    p, f = check("P06 writes inspection_pre.json (pre inspection wired)",
                 "-Label 'pre'" in code and "inspection_pre.json" in code,
                 "wired", p, f)
    p, f = check("P11 emits SHA-256 content-identity rows",
                 "IsoWimHashMatch_" in code, "rows present", p, f)
    p, f = check("P11 writes inspection_post.json (post inspection wired)",
                 "-Label 'post'" in code, "wired", p, f)
    p, f = check("P13 diffs + observe-first wired",
                 "inspection_diff.json" in code
                 and re.search(r"Get-InspectionCrossChecks\s+-BootWimLcuPolicy", code) is not None,
                 "wired", p, f)
    p, f = check("P11 Kb rows accept the Catalog child-KB alias",
                 re.search(r"Get-KbAliasFromPatchPath\s+-KbId", code) is not None,
                 "alias wired", p, f)
    p, f = check("the invalid Get-WindowsPackage -ImagePath call is gone",
                 re.search(r"Get-WindowsPackage'\s+-Parameters\s+@\{\s*ImagePath", code) is None,
                 "dead path buried", p, f)

    print()
    print(f"  Summary: {p} passed, {f} failed, {p + f} total")
    return 0 if f == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
