#!/usr/bin/env python3
"""Build the website's shared parts.

Every page in website/ keeps only its own content between <!-- content --> and <!-- /content -->; this script
rewrites everything around it (head, header and tabs, sidebar, footer) from one template, and generates
website/packages.html from the ports tree. The wiki (website/wiki/, listed in WIKI below) works the same way: each
article gets the wiki navigation, a table of contents made from its <h2>/<h3> headings and, from a
<!-- related: slug slug --> line in its content, a "Related articles" box. Run it after changing a page, the ports
or VERSION:

    tools/website.py
"""
import html, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, 'website')
# the release the website offers for download (the one published on GitHub)
RELEASE = os.environ.get('SITE_RELEASE') or open(os.path.join(WEB, 'release')).read().strip()
GH = 'https://github.com/tortr-rs/systemLinux'
ISO = f'{GH}/releases/download/v{RELEASE}/systemLinux-{RELEASE}-x86_64.iso'

# file, tab label, page title, has the sidebar
PAGES = [
    ('index.html', 'Home', 'A small source-based GNU/Linux distribution', True),
    ('news.html', 'News', 'News', True),
    ('about.html', 'About', 'About', True),
    ('download.html', 'Download', 'Download', True),
    ('wiki/index.html', 'Wiki', 'Wiki', False),
    ('get.html', 'get', 'The get package tool', True),
    ('packages.html', 'Packages', 'Packages', False),
    ('packaging.html', 'Packaging', 'Packaging guide', False),
    ('system.html', 'System', 'System', True),
]

def header(current, up=''):
    on = ' class="on"'
    tabs = ''.join(f'<a href="{up}{f}"{on if f == current else ""}>{label}</a>' for f, label, _, _ in PAGES)
    return f'''<!-- header -->
<header class="masthead"><div class="wrap">
<a class="brand" href="{up}index.html"><img src="{up}logo.svg" alt="" width="40" height="40">systemLinux</a>
<div class="tagline">source-based &middot; dinit &middot; no systemd<br>owned by everyone who uses it</div>
</div></header>
<nav class="tabs"><div class="wrap">{tabs}<a href="{GH}">Source</a></div></nav>
<!-- /header -->'''

def sidebar():
    return f'''<!-- side -->
<aside class="side">
<div class="box"><h3>Get systemLinux {RELEASE}</h3><div class="in">
<p style="margin:.2em 0 .6em"><a class="btn" href="{ISO}">Download the ISO</a></p>
<p class="small muted" style="margin:0">x86_64, UEFI and legacy BIOS. <a href="download.html">Checksums and notes</a></p>
</div></div>
<div class="box"><h3>Documentation</h3><div class="in"><ul>
<li><a href="wiki/index.html">Wiki</a>: everything</li>
<li><a href="wiki/handbook.html">Handbook</a>: installing</li>
<li><a href="get.html">get</a>: installing software</li>
<li><a href="packaging.html">Packaging guide</a>: writing ports</li>
<li><a href="system.html">System</a>: services and limits</li>
<li><a href="{GH}/blob/main/CHANGELOG.md">Changelog</a></li>
</ul></div></div>
<div class="box"><h3>Get involved</h3><div class="in"><ul>
<li><a href="{GH}">Source on GitHub</a></li>
<li><a href="{GH}/issues">Report a bug</a></li>
<li><a href="{GH}/tree/main/ports">Ports tree</a></li>
<li><a href="packaging.html">Add a port</a></li>
</ul></div></div>
</aside>
<!-- /side -->'''

def footer(up=''):
    return f'''<!-- footer -->
<footer><div class="wrap">
<span>systemLinux {RELEASE}</span><span>Owned by everyone who uses it.</span><span>Tux by Larry Ewing and The GIMP (<a href="{up}about.html#mascot">credits</a>)</span>
<a href="{GH}">Source</a><a href="{GH}/issues">Issues</a><a href="{GH}/releases">Releases</a>
</div></footer>
<!-- /footer -->'''

def content_of(text):
    m = re.search(r'<!-- content -->\n?(.*?)\n?<!-- /content -->', text, re.S)
    if m: return m.group(1)
    # the old page layout: content sits between the <hr> after the menu and the <hr> before the footer
    body = text.split('<hr>', 1)[1]
    return body.rsplit('<hr>', 1)[0].strip()

def render(fname, label, title, side, content):
    full_title = 'systemLinux' if fname == 'index.html' else f'{title} - systemLinux'
    if fname == 'index.html': full_title = f'systemLinux: {title.lower()}'
    hero = ''
    if fname == 'index.html':
        hero = f'''<section class="hero"><div class="wrap">
<img src="tux.svg" alt="Tux, the systemLinux mascot" width="110" style="float:right;margin-left:1em">
<h1>systemLinux</h1>
<p class="lead">A small x86_64 GNU/Linux distribution: dinit instead of systemd, the newest kernel, and software
built from source with <code>get</code>, from a ports tree of over a thousand recipes. Nobody owns it and nobody profits
from it.</p>
<div class="actions"><a class="btn" href="{ISO}">Download {RELEASE}</a><a class="btn ghost" href="wiki/handbook.html">Read the handbook</a><a class="btn ghost" href="packages.html">Browse packages</a></div>
</div></section>'''
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{full_title}</title>
<link rel="icon" type="image/svg+xml" href="logo.svg">
<link rel="stylesheet" href="style.css">
</head>
<body>
{header(fname)}
{hero}
<div class="wrap page">
<main class="main">
<!-- content -->
{content}
<!-- /content -->
</main>
{sidebar() if side else ''}
</div>
{footer()}
</body>
</html>
'''

def recipe(path):
    d = {}
    for line in open(path, errors='replace'):
        m = re.match(r'([a-z_]+)\s*=\s*(.*)', line.rstrip('\n'))
        if m and m.group(1) not in d: d[m.group(1)] = m.group(2).strip().strip('"')
    return d

def packages_content():
    ports = os.path.join(ROOT, 'ports')
    rows = []
    for cat in sorted(os.listdir(ports)):
        cdir = os.path.join(ports, cat)
        if not os.path.isdir(cdir): continue
        for name in sorted(os.listdir(cdir)):
            r = os.path.join(cdir, name, 'recipe')
            if not os.path.isfile(r): continue
            d = recipe(r)
            if not d.get('version') and d.get('url'):  # older recipes: take it from the file name
                m = re.search(r'[-_v](\d+(?:\.\d+)+[a-z]?)(?:[-_.](?:src|source|stable|orig))?\.(?:tar|tgz|tbz|txz|zip)', d['url'].rsplit('/', 1)[-1])
                if m: d['version'] = m.group(1)
            tags = ''
            if name.endswith('-bin'): tags += '<span class="tag">bin</span>'
            if os.path.isdir(os.path.join(cdir, name, 'dinit')): tags += '<span class="tag">service</span>'
            if not d.get('url'): tags += '<span class="tag">meta</span>'
            rows.append(f'<tr><td><span class="cat">{cat}/</span><a href="{GH}/tree/main/ports/{cat}/{name}"><b>{html.escape(name)}</b></a>{tags}</td>'
                        f'<td>{html.escape(d.get("version", ""))}</td><td>{html.escape(d.get("description", ""))}</td></tr>')
    return f'''<h1>Packages</h1>
<p>The ports tree has <b>{len(rows)}</b> packages. Install any of them with <code>get install NAME</code>; dependencies are
built first. <span class="tag">bin</span> ports install the project's own official build instead of compiling it,
<span class="tag">service</span> ports come with a dinit service and <span class="tag">meta</span> ports only pull in other
packages. Missing something? <a href="packaging.html">Write a port</a>.</p>
<input class="search" id="q" type="search" placeholder="Search {len(rows)} packages by name or description" autofocus>
<table class="pkgs"><thead><tr><th>Package</th><th>Version</th><th>Description</th></tr></thead>
<tbody id="rows">
{chr(10).join(rows)}
</tbody></table>
<p class="muted small" id="count"></p>
<script>
(function () {{
  var q = document.getElementById('q'), rows = document.getElementById('rows').rows, count = document.getElementById('count');
  function filter() {{
    var words = q.value.toLowerCase().split(/\\s+/).filter(Boolean), shown = 0;
    for (var i = 0; i < rows.length; i++) {{
      var t = rows[i].textContent.toLowerCase(), ok = words.every(function (w) {{ return t.indexOf(w) >= 0; }});
      rows[i].style.display = ok ? '' : 'none'; if (ok) shown++;
    }}
    count.textContent = words.length ? shown + ' of ' + rows.length + ' packages' : '';
  }}
  q.addEventListener('input', filter);
  if (location.hash.length > 1) {{ q.value = decodeURIComponent(location.hash.slice(1)); filter(); }}
}})();
</script>'''

# ---- the wiki
# slug (website/wiki/SLUG.html), title, category. The order here is the order in the navigation.
WIKI = [
    ('index', 'Main page', None),
    ('handbook', 'Handbook: overview', 'Handbook'),
    ('handbook-media', '1. Installation media', 'Handbook'),
    ('handbook-live', '2. Booting the live system', 'Handbook'),
    ('handbook-disks', '3. Preparing the disks', 'Handbook'),
    ('handbook-stage', '4. Installing the stage', 'Handbook'),
    ('handbook-chroot', '5. Entering the new system', 'Handbook'),
    ('handbook-config', '6. Configuring the system', 'Handbook'),
    ('handbook-kernel', '7. Kernel and initramfs', 'Handbook'),
    ('handbook-bootloader', '8. Bootloader', 'Handbook'),
    ('handbook-finalizing', '9. Finalizing', 'Handbook'),
    ('quick-install', 'Quick install (systemlinux-install)', 'Installation'),
    ('dual-boot', 'Dual boot', 'Installation'),
    ('general-recommendations', 'General recommendations', 'Installation'),
    ('get', 'get', 'Software'),
    ('ports', 'Ports tree', 'Software'),
    ('profiles', 'Package profiles', 'Software'),
    ('dinit', 'dinit', 'System administration'),
    ('users-and-groups', 'Users and groups', 'System administration'),
    ('sudo', 'sudo', 'System administration'),
    ('fstab', 'fstab', 'System administration'),
    ('swap', 'Swap', 'System administration'),
    ('system-time', 'System time', 'System administration'),
    ('locale', 'Locale', 'System administration'),
    ('linux-console', 'Linux console', 'System administration'),
    ('system-maintenance', 'System maintenance', 'System administration'),
    ('kernel', 'Kernel', 'Boot process'),
    ('kernel-parameters', 'Kernel parameters', 'Boot process'),
    ('initramfs', 'Initramfs', 'Boot process'),
    ('grub', 'GRUB', 'Boot process'),
    ('luks', 'Disk encryption (LUKS)', 'Boot process'),
    ('firmware', 'Firmware', 'Hardware'),
    ('graphics', 'Graphics drivers', 'Hardware'),
    ('pipewire', 'Sound (PipeWire)', 'Hardware'),
    ('bluetooth', 'Bluetooth', 'Hardware'),
    ('printing', 'Printing (CUPS)', 'Hardware'),
    ('laptop', 'Laptop', 'Hardware'),
    ('network-configuration', 'Network configuration', 'Networking'),
    ('wireless', 'Wireless', 'Networking'),
    ('ssh', 'OpenSSH', 'Networking'),
    ('desktop', 'Graphical session', 'Desktop'),
    ('sway', 'Sway', 'Desktop'),
    ('xorg', 'Xorg', 'Desktop'),
    ('i3', 'i3', 'Desktop'),
    ('greetd', 'greetd (login manager)', 'Desktop'),
    ('recovery', 'Recovery', 'Help'),
    ('troubleshooting', 'Troubleshooting', 'Help'),
    ('faq', 'FAQ', 'Help'),
    ('contributing', 'Contributing', 'Help'),
    ('building-the-iso', 'Building the ISO', 'Help'),
]
WIKI_TITLES = {slug: title for slug, title, _ in WIKI}

def wiki_nav(current):
    out, cat = ['<nav class="wiki-nav"><a class="wiki-home" href="index.html">systemLinux Wiki</a>'], ''
    for slug, title, c in WIKI:
        if c is None: continue
        if c != cat:
            out.append(('</ul>' if cat else '') + f'<h4>{c}</h4><ul>')
            cat = c
        cls = ' class="on"' if slug == current else ''
        out.append(f'<li><a href="{slug}.html"{cls}>{html.escape(title)}</a></li>')
    out.append('</ul><h4>Elsewhere</h4><ul><li><a href="../packages.html">Packages</a></li>'
               '<li><a href="../packaging.html">Packaging guide</a></li>'
               f'<li><a href="{GH}/issues">Report a bug</a></li></ul></nav>')
    return '\n'.join(out)

def anchor(text):
    return re.sub(r'[^a-z0-9]+', '-', re.sub(r'<[^>]+>', '', html.unescape(text)).lower()).strip('-')

def add_toc(content):
    """Give every <h2>/<h3> an id and return (content, the numbered table of contents)."""
    entries, used = [], set()
    def heading(m):
        level, attrs, text = m.group(1), m.group(2), m.group(3)
        idm = re.search(r'id="([^"]+)"', attrs)
        hid = idm.group(1) if idm else anchor(text)
        while hid in used: hid += '-2'
        used.add(hid)
        entries.append((int(level), hid, re.sub(r'<[^>]+>', '', text)))
        if not idm: attrs += f' id="{hid}"'
        return f'<h{level}{attrs}>{text}</h{level}>'
    content = re.sub(r'<h([23])([^>]*)>(.*?)</h\1>', heading, content, flags=re.S)
    if len(entries) < 3: return content, ''
    toc, n2, n3, open3 = ['<div class="toc"><b>Contents</b><ol>'], 0, 0, False
    for level, hid, text in entries:
        if level == 2:
            if open3: toc.append('</ol>'); open3 = False
            if n2: toc.append('</li>')
            n2 += 1; n3 = 0
            toc.append(f'<li><a href="#{hid}"><span>{n2}</span> {text}</a>')
        else:
            if not open3: toc.append('<ol>'); open3 = True
            n3 += 1
            toc.append(f'<li><a href="#{hid}"><span>{n2}.{n3}</span> {text}</a></li>')
    if open3: toc.append('</ol>')
    toc.append('</li></ol></div>')
    return content, ''.join(toc)

def render_wiki(slug, title, cat, content):
    related = ''
    m = re.search(r'<!-- related: (.*?) -->', content)
    if m:
        links = ''.join(f'<li><a href="{r}.html">{html.escape(WIKI_TITLES[r])}</a></li>' for r in m.group(1).split())
        related = f'<div class="related"><b>Related articles</b><ul>{links}</ul></div>'
    body, toc = add_toc(content)
    crumbs = '<a href="index.html">Wiki</a>' + (f' &rsaquo; {cat}' if cat else '')
    h1 = 'systemLinux Wiki' if slug == 'index' else html.escape(title)
    full_title = 'systemLinux Wiki' if slug == 'index' else f'{title} - systemLinux Wiki'
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(full_title)}</title>
<link rel="icon" type="image/svg+xml" href="../logo.svg">
<link rel="stylesheet" href="../style.css">
</head>
<body>
{header('wiki/index.html', '../')}
<div class="wrap page wiki">
{wiki_nav(slug)}
<main class="main">
<div class="crumbs">{crumbs}</div>
<h1>{h1}</h1>
<div class="wiki-boxes">{related}{toc}</div>
<!-- content -->
{body}
<!-- /content -->
<p class="wiki-edit"><a href="{GH}/edit/main/website/wiki/{slug}.html">Edit this page on GitHub</a> &middot; <a href="{GH}/commits/main/website/wiki/{slug}.html">History</a></p>
</main>
</div>
{footer('../')}
</body>
</html>
'''

def main():
    for slug, title, cat in WIKI:
        path = os.path.join(WEB, 'wiki', slug + '.html')
        page = render_wiki(slug, title, cat, content_of(open(path).read()))
        open(path, 'w').write(page)
    print('wrote', len(WIKI), 'wiki pages')
    for fname, label, title, side in PAGES:
        if fname.startswith('wiki/'): continue
        path = os.path.join(WEB, fname)
        if fname == 'packages.html':
            content = packages_content()
        else:
            content = content_of(open(path).read())
        open(path, 'w').write(render(fname, label, title, side, content))
        print('wrote', fname)

if __name__ == '__main__':
    main()
