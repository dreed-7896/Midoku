"""Turns a native Midoku backup's collection into an import plan for Midoku Web (plan.json)."""
import base64, io, json, sys
from PIL import Image

c = json.load(open(sys.argv[1]))
L = c['library']
APPLE = 978307200  # seconds from 1970 to 2001 (Apple reference date)

SOURCES = {  # native source key -> Suwayomi source id, url form
    'multi.mangadex': ('6404943692147160087', 'MangaDex', lambda k: '/manga/' + k),
    'en.hentairead': ('2299981010822511979', 'HentaiRead', None),
    'multi.nhentai': ('7309872737163460316', 'NHentai', None),
    'en.manhwaread': ('492596911850505683', 'ManhwaRead', None),
    'en.omegascans': ('1534451209269193504', 'Omega Scans', lambda k: k if k.startswith('/') else '/series/' + k),
    'en.allporncomic': ('8547397037512613554', 'AllPornComic', None),
    'en.novelcrow': ('4344163117450761946', 'NovelCrow', None),
    'en.hentainexus': ('7719798645438596394', 'HentaiNexus', None),
    'multi.hitomi': ('690123758188633713', 'Hitomi', 'search'),
    'multi.xcomic': ('1951931397842101209', 'XCOMIC', None),
    'en.hentai2read': ('8314925449740051373', 'Hentai2Read', 'search'),
}

conn = {x['id']: x['sourceKey'] for x in c['connections']}
listings = {x['id']: x for x in L['listings']}
chapters = {x['id']: x for x in L['chapters']}
covers = {x['id']: x for x in L['covers']}
cats = {x['id']: x['name'] for x in c['categories']}
completed = {(x['listing']['connectionID'], x['listing']['externalID'], x['externalID']) for x in L['completed']}


import urllib.request
REFERER = {'multi.xcomic': 'https://xcomic.net/', 'en.hentairead': 'https://hentairead.com/'}
fetched = {'ok': 0, 'failed': []}
def cover_bytes(cid):
    x = covers.get(cid)
    if not x:
        return None
    if x.get('data'):
        return base64.b64decode(x['data'])
    url = x.get('url')
    if not url:
        return None
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Referer': REFERER.get(x.get('sourceKey'), url)})
        b = urllib.request.urlopen(req, timeout=20).read()
        fetched['ok'] += 1
        return b
    except Exception as err:
        fetched['failed'].append((url, str(err)[:60]))
        return url  # kept as an address

def small_cover(cid, width=360):
    data = cover_bytes(cid)
    if data is None:
        return None
    if isinstance(data, str):
        return data
    img = Image.open(io.BytesIO(data)).convert('RGB')
    if img.width > width:
        img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, 'JPEG', quality=80)
    return 'data:image/jpeg;base64,' + base64.b64encode(out.getvalue()).decode()


def small_thumb(cid):
    return small_cover(cid, 240)


skipped_sources = {}
plan_listings = {}  # listing id -> what the runner needs


def listing(lid):
    l = listings.get(lid)
    if not l:
        return None
    key = conn.get(l['identity']['connectionID'])
    if key not in SOURCES:
        skipped_sources[key] = skipped_sources.get(key, 0) + 1
        return None
    sid, name, form = SOURCES[key]
    ext = l['identity']['externalID']
    url = form(ext) if callable(form) else ext
    plan_listings[lid] = {
        'id': lid, 'sourceKey': key, 'sourceId': sid, 'sourceName': name, 'externalID': ext,
        'url': None if form == 'search' else url, 'search': form == 'search',
        'title': l['details'].get('title', ''), 'webURL': l['details'].get('webURL'),
    }
    return plan_listings[lid]


entries = []
for e in L['entries']:
    links = [ln for ln in e['links'] if listing(ln['listingID'])]
    link_by_listing = {ln['listingID']: ln for ln in links}
    excluded = set(e.get('exclusions') or [])
    slots = []
    for si, s in enumerate(e['slots']):
        vs = []
        for v in s['variants']:
            ch = chapters.get(v['chapterID'])
            if not ch:
                continue
            ident = ch['identity']
            lid = next((x for x in link_by_listing if listings[x]['identity']['externalID'] == ident['listing']['externalID']
                        and listings[x]['identity']['connectionID'] == ident['listing']['connectionID']), None)
            if not lid:
                continue
            edits = v.get('edits') or {}
            ps = v.get('pageSelection')
            vs.append({
                'variantID': v['id'], 'listing': lid, 'chapterExt': ident['externalID'],
                'number': float(ch['record']['number']) if ch['record'].get('number') not in (None, '') else None,
                'title': ch['record'].get('title'),
                'read': (ident['listing']['connectionID'], ident['listing']['externalID'], ident['externalID']) in completed or bool(s.get('completionOverride')),
                'removed': v['chapterID'] in excluded,
                'name': edits.get('title'),
                'editNumber': edits.get('number'),
                'thumb': small_thumb(edits['coverID']) if edits.get('coverID') else None,
                'preferred': v['id'] == s.get('preferredID') and len(s['variants']) > 1,
                'pages': ps and {'ranges': ps.get('ranges', []), 'excluded': ps.get('excluded', []), 'part': ps.get('part', 0)},
            })
        if vs:
            slots.append(vs)

    # Listings in a slot together are versions of each other (one segment); groups follow each other in slot order.
    parent = {}
    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    for vs in slots:
        ls = [v['listing'] for v in vs]
        for x in ls[1:]:
            parent[find(x)] = find(ls[0])
    order = []
    for vs in slots:
        for v in vs:
            g = find(v['listing'])
            if g not in order:
                order.append(g)
    for ln in links:  # listings without chapters in slots
        g = find(ln['listingID'])
        if g not in order:
            order.append(g)
    segment = {lid: order.index(find(lid)) for lid in link_by_listing}
    primary = e.get('primaryListingID') if e.get('primaryListingID') in link_by_listing else (links[0]['listingID'] if links else None)

    entries.append({
        'id': e['id'], 'parent': e.get('parentEntryID'),
        'title': e.get('titleOverride'), 'author': e.get('authorOverride') or e.get('artistOverride'),
        'description': e.get('descriptionOverride'),
        'cover': small_cover(e['coverID']) if e.get('coverID') else None,
        'thumbs': bool(e.get('chapterGridOverride')),
        'tabs': [cats[x] for x in e.get('categoryIDs', []) if x in cats],
        'lastReadAt': (e['lastReadAt'] + APPLE) if e.get('lastReadAt') else None,
        'createdAt': (e['createdAt'] + APPLE) if e.get('createdAt') else None,
        'manualOrder': bool(e.get('manualOrder')),
        'contentOrder': e.get('contentOrder') or [],
        'sources': [{'listing': ln['listingID'], 'main': ln['listingID'] == primary, 'segment': segment[ln['listingID']] if len(order) > 1 else 0,
                     'following': bool(ln.get('followsNewChapters'))} for ln in links],
        'slots': slots,
        'droppedLinks': len(e['links']) - len(links),
    })

json.dump({'categories': [x['name'] for x in c['categories']], 'listings': plan_listings, 'entries': entries}, open(sys.argv[2], 'w'))
print('entries', len(entries), 'listings', len(plan_listings), 'search', sum(1 for x in plan_listings.values() if x['search']))
print('skipped links by source', skipped_sources)
print('slots', sum(len(e['slots']) for e in entries), 'read', sum(1 for e in entries for vs in e['slots'] for v in vs if v['read']))
print('named', sum(1 for e in entries for vs in e['slots'] for v in vs if v['name']), 'splits', sum(1 for e in entries for vs in e['slots'] for v in vs if v['pages']))
print('remote covers', fetched['ok'], 'fetched;', len(fetched['failed']), 'kept as links', fetched['failed'][:3])
print('own series', [e['title'] for e in entries if not e['sources']])
