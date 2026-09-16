#!/usr/bin/env python3
"""Download the official government datasets into DataSources/.

    python Scripts/fetch_datasets.py [--out DataSources] [--only nrcan-bev]

Standard library only. No API key, no account, no third-party service. Each URL
is a direct machine-readable download published by the issuing government; this
script never scrapes a web page.

Downloads are written to a temporary file and moved into place only after the
transfer completes, so an interrupted run cannot leave a truncated CSV behind
that a later build would happily parse.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
USER_AGENT = "FuelSmart-dataset-fetcher/1.0 (+offline vehicle cost comparison)"


def load_sources() -> dict:
    with open(os.path.join(HERE, "sources.json"), encoding="utf-8") as handle:
        return json.load(handle)


def download(url: str, destination: str) -> int:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status} for {url}")
        handle = tempfile.NamedTemporaryFile(delete=False, dir=os.path.dirname(destination))
        try:
            shutil.copyfileobj(response, handle)
            handle.close()
            size = os.path.getsize(handle.name)
            if size == 0:
                raise RuntimeError(f"empty download from {url}")
            shutil.move(handle.name, destination)
            return size
        except BaseException:
            handle.close()
            if os.path.exists(handle.name):
                os.unlink(handle.name)
            raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=os.path.join(REPO, "DataSources"))
    parser.add_argument("--only", action="append", help="limit to these source ids")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    config = load_sources()

    failures = 0
    for source in config["sources"]:
        if args.only and source["id"] not in args.only:
            continue
        for url in source["urls"]:
            name = url.rsplit("/", 1)[-1]
            destination = os.path.join(args.out, name)
            try:
                size = download(url, destination)
                print(f"  ok    {source['id']:<20} {name}  ({size:,} bytes)")
            except (urllib.error.URLError, RuntimeError, OSError) as error:
                failures += 1
                if os.path.exists(destination):
                    print(f"  WARN  {source['id']:<20} {name}  download failed ({error}); keeping existing copy")
                else:
                    print(f"  FAIL  {source['id']:<20} {name}  {error}", file=sys.stderr)

    if failures:
        print(f"\n{failures} download(s) failed. Existing local copies, where present, were left untouched.")
        print("The app always ships with the last successfully generated data, so a failed refresh is not fatal.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
