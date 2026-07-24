#!/usr/bin/env python3
"""Build/update the Sparkle appcast feed for a new release.

Usage:
  appcast.py <dmg> <shortVersion> <buildVersion> <enclosureURL> \
             <sign_update> <keyFile> <existingAppcast|""> <out> <releasePageURL>

Signs the DMG with the EdDSA key, then writes an appcast whose newest <item> is
this release, followed by the items from the previous appcast (so older versions
stay listed). The previous appcast is fetched from releases/latest/download.
"""
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

dmg, short, build, url, signtool, keyfile, existing, out, page = sys.argv[1:10]

old_items = []
if existing and os.path.exists(existing):
    old_items = re.findall(r"<item>.*?</item>", open(existing, encoding="utf-8").read(), re.S)


def build_numbers(items):
    return [int(m) for block in items
            for m in re.findall(r"<sparkle:version>(\d+)</sparkle:version>", block)]


# Sparkle compares <sparkle:version> (the build number), not the marketing
# version. Publishing a build that isn't higher than the newest one already in
# the feed means nobody is offered the update — silently. Refuse instead.
published = max(build_numbers(old_items), default=0)
if int(build) < published:
    sys.exit(f"✗ build {build} is older than the published build {published} — "
             "bump CURRENT_PROJECT_VERSION in project.yml.")
if int(build) == published and os.environ.get("ALLOW_REPUBLISH") != "1":
    sys.exit(f"✗ build {build} is already published. Bump CURRENT_PROJECT_VERSION "
             "in project.yml, or set ALLOW_REPUBLISH=1 to re-run this same release.")


def deployment_target(path="project.yml", fallback="14.0"):
    """Keep minimumSystemVersion in step with the actual deployment target —
    hard-coding it would offer the update to Macs that can't launch the app."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return fallback
    m = re.search(r"deploymentTarget:\s*\n\s*macOS:\s*\"?([\d.]+)\"?", text)
    return m.group(1) if m else fallback


res = subprocess.run([signtool, dmg, "--ed-key-file", keyfile],
                     capture_output=True, text=True)
attrs = res.stdout.strip()
if "edSignature" not in attrs:
    sys.exit("sign_update failed:\n" + res.stdout + res.stderr)

pub = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
minimum_system = deployment_target()

item = f"""    <item>
      <title>{short}</title>
      <link>{page}</link>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum_system}</sparkle:minimumSystemVersion>
      <pubDate>{pub}</pubDate>
      <description><![CDATA[Release notes: <a href="{page}">{short}</a>]]></description>
      <enclosure url="{url}" {attrs} type="application/octet-stream"/>
    </item>"""

# Keep previous items (skip any with the same build number to avoid duplicates —
# only reachable on an ALLOW_REPUBLISH re-run of the same release).
old = ["    " + block for block in old_items
       if f"<sparkle:version>{build}</sparkle:version>" not in block]

items = "\n".join([item] + old)
feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Claude Usage</title>
    <link>{page}</link>
    <description>Claude Usage updates</description>
    <language>en</language>
{items}
  </channel>
</rss>
"""
open(out, "w", encoding="utf-8").write(feed)
print(f"wrote {out}: {1 + len(old)} item(s); new = {short} (build {build})")
