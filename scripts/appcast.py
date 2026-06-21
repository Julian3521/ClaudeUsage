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

res = subprocess.run([signtool, dmg, "--ed-key-file", keyfile],
                     capture_output=True, text=True)
attrs = res.stdout.strip()
if "edSignature" not in attrs:
    sys.exit("sign_update failed:\n" + res.stdout + res.stderr)

pub = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")

item = f"""    <item>
      <title>{short}</title>
      <link>{page}</link>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>{pub}</pubDate>
      <description><![CDATA[Release notes: <a href="{page}">{short}</a>]]></description>
      <enclosure url="{url}" {attrs} type="application/octet-stream"/>
    </item>"""

# Keep previous items (skip any with the same build number to avoid duplicates).
old = []
if existing and os.path.exists(existing):
    txt = open(existing, encoding="utf-8").read()
    for block in re.findall(r"<item>.*?</item>", txt, re.S):
        if f"<sparkle:version>{build}</sparkle:version>" not in block:
            old.append("    " + block)

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
