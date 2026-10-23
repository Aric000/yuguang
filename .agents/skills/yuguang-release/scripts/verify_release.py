#!/usr/bin/env python3
"""Read-only validation of a Yuguang release, its exact tag and CI-produced assets."""
import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


def get_json(path):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Yuguang-release-check"}
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    request = urllib.request.Request("https://api.github.com" + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def verify(args):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        raise ValueError("Invalid owner/repository")
    if not re.fullmatch(r"v\d+\.\d+\.\d+", args.tag):
        raise ValueError("Expected vX.Y.Z tag")
    if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        raise ValueError("Expected full 40-character commit SHA")
    base = "/repos/" + args.repo
    release = get_json(base + "/releases/tags/" + args.tag)
    ref = get_json(base + "/git/ref/tags/" + args.tag)["object"]
    for _ in range(4):
        if ref["type"] != "tag":
            break
        ref = get_json(base + "/git/tags/" + ref["sha"])["object"]
    if ref["type"] != "commit" or ref["sha"] != args.commit:
        raise ValueError("Release tag does not point to verified commit")
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Release is not a published stable release")
    runs = get_json(base + "/actions/runs?head_sha=" + args.commit + "&per_page=100")["workflow_runs"]
    runs = [run for run in runs if run.get("path", "").split("@")[0] == ".github/workflows/release.yml" and run["event"] == "release"]
    if not runs:
        print("Pending: release workflow has not appeared")
        return 2
    run = max(runs, key=lambda item: item["id"])
    if run["status"] != "completed":
        print("Pending: " + run["html_url"])
        return 2
    if run["conclusion"] != "success":
        raise ValueError("Release workflow failed: " + run["html_url"])
    version = args.tag[1:]
    prefix = "Yuguang-" + version
    expected = {prefix + suffix for suffix in [
        "-macOS-arm64.dmg", "-macOS-arm64.zip", "-macOS-arm64.sha256",
        "-windows-x64-setup.exe", "-windows-x64-portable.exe", "-windows-x64.sha256",
    ]}
    assets = {asset["name"]: asset for asset in release["assets"]}
    missing = expected - assets.keys()
    if missing:
        print("Pending assets: " + ", ".join(sorted(missing)))
        return 2
    for name in expected:
        asset = assets[name]
        if asset["state"] != "uploaded" or asset["size"] <= 0 or not re.fullmatch(r"sha256:[0-9a-f]{64}", asset.get("digest") or ""):
            raise ValueError("Incomplete asset: " + name)
    checked = set()
    for name in sorted(expected):
        if not name.endswith(".sha256"):
            continue
        url = assets[name]["browser_download_url"]
        if urllib.parse.urlparse(url).hostname != "github.com":
            raise ValueError("Unexpected checksum asset host")
        request = urllib.request.Request(url, headers={"User-Agent": "Yuguang-release-check"})
        with urllib.request.urlopen(request, timeout=30) as response:
            manifest_bytes = response.read(65537)
        if len(manifest_bytes) > 65536:
            raise ValueError("Oversized checksum manifest")
        if "sha256:" + hashlib.sha256(manifest_bytes).hexdigest() != assets[name]["digest"]:
            raise ValueError("Checksum manifest digest differs from GitHub asset digest")
        for line in manifest_bytes.decode("utf-8").splitlines():
            match = re.fullmatch(r"([0-9a-f]{64})\s+\*?([^/\\]+)", line)
            if not match or match[2] not in expected or match[2].endswith(".sha256"):
                raise ValueError("Invalid checksum manifest entry")
            if assets[match[2]]["digest"] != "sha256:" + match[1]:
                raise ValueError("Installer digest differs from manifest: " + match[2])
            checked.add(match[2])
    if checked != {name for name in expected if not name.endswith(".sha256")}:
        raise ValueError("Manifests do not cover every installer")
    print(json.dumps({"release": release["html_url"], "commit": args.commit, "workflow": run["html_url"], "verified_assets": sorted(expected)}, ensure_ascii=False, indent=2))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="Aric000/yuguang")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    try:
        return verify(args)
    except (ValueError, KeyError, OSError, urllib.error.URLError) as error:
        print("Release verification failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
