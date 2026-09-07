# -*- coding: utf-8 -*-
"""Fold the parsed doc into one row per human and emit review + SQL."""
import json, re, io

parsed = json.load(open('import/parsed.json'))

STATE_ABBR = {'alabama':'AL','alaska':'AK','arizona':'AZ','arkansas':'AR','california':'CA',
 'colorado':'CO','connecticut':'CT','delaware':'DE','florida':'FL','georgia':'GA','hawaii':'HI',
 'idaho':'ID','illinois':'IL','indiana':'IN','iowa':'IA','kansas':'KS','kentucky':'KY',
 'louisiana':'LA','maine':'ME','maryland':'MD','massachusetts':'MA','michigan':'MI',
 'minnesota':'MN','mississippi':'MS','missouri':'MO','montana':'MT','nebraska':'NE',
 'nevada':'NV','new hampshire':'NH','new jersey':'NJ','new mexico':'NM','new york':'NY',
 'north carolina':'NC','north dakota':'ND','ohio':'OH','oklahoma':'OK','oregon':'OR',
 'pennsylvania':'PA','rhode island':'RI','south carolina':'SC','south dakota':'SD',
 'tennessee':'TN','texas':'TX','utah':'UT','vermont':'VT','virginia':'VA','washington':'WA',
 'west virginia':'WV','wisconsin':'WI','wyoming':'WY'}

# Two shapes, tried in order: a 2-letter state ("Los Angeles CA 90020" -- the
# lazy city group would otherwise stop at "Los" and call "Angeles CA" a state),
# then a spelled-out one ("Annapolis, Maryland 21401").
CITY_ABBR = re.compile(r'^(?P<city>[A-Za-z .\'\-]+?),?\s+(?P<state>[A-Za-z]{2})\.?\s+(?P<zip>\d{5}(?:-\d{4})?)\s*$')
CITY_FULL = re.compile(r'^(?P<city>[A-Za-z .\'\-]+?),\s*(?P<state>[A-Za-z ]{3,20}?)\.?\s+(?P<zip>\d{5}(?:-\d{4})?)\s*$')


def city_match(l):
    return CITY_ABBR.match(l) or CITY_FULL.match(l)


def split_address(lines):
    """Street lines + a City/State/Zip line -> four fields."""
    street, city, state, zipc = [], '', '', ''
    seen = set()
    for l in lines:
        l = l.strip().rstrip(',')
        key = re.sub(r'[^a-z0-9]', '', l.lower())
        if not l or key in seen:
            continue
        seen.add(key)
        m = city_match(l)
        if m and city:
            continue          # a second copy of the same city line
        if m and not city:
            city = m.group('city').strip()
            st = m.group('state').strip()
            state = STATE_ABBR.get(st.lower(), st.upper() if len(st) == 2 else st)
            zipc = m.group('zip')
            continue
        # "1776 Mentor Avenue, Suite 100 Cincinnati, OH 45212" -- all on one line
        m2 = re.search(r'^(?P<street>.+?)[, ]\s*(?P<city>[A-Za-z .\'\-]+),\s*(?P<state>[A-Z]{2})\.?\s+(?P<zip>\d{5})\s*$', l)
        if m2 and not city:
            street.append(m2.group('street').strip().strip(','))
            city, state, zipc = m2.group('city').strip(), m2.group('state'), m2.group('zip')
            continue
        street.append(l)
    joined = ', '.join(street)
    joined = re.sub(r'\s*\|\s*', ', ', joined).strip(' ,|')   # "One Government Center | Suite 800 |"
    joined = re.sub(r',\s*,', ',', joined)
    return joined, city, state, zipc


def norm_name(n):
    return re.sub(r'[^a-z]', '', (n or '').lower())


def merge(a, b):
    for f in ('title', 'org', 'email'):
        if not a[f] and b[f]:
            a[f] = b[f]
    for ph in b['phones']:
        if ph not in a['phones']:
            a['phones'].append(ph)
    for ad in b['address']:
        if ad not in a['address']:
            a['address'].append(ad)
    for n in b['notes']:
        if n not in a['notes']:
            a['notes'].append(n)
    a['regional'] = a['regional'] or b['regional']
    if b['cc'] is False:
        a['cc'] = False
    elif b['cc'] and a['cc'] is not False:
        a['cc'] = True
    for r in ('primary', 'admin', 'finance'):
        a['roles'][r] = a['roles'][r] or b['roles'][r]
    return a


programs, flags = [], []
for rec in parsed:
    people = []
    index = {}
    for p in rec['people']:
        p = dict(p)
        p['roles'] = {'primary': p['role'] == 'primary',
                      'admin': p['role'] == 'admin' and not p['regional'],
                      'finance': p['role'] == 'finance'}
        key = ('e:' + p['email'].lower()) if p['email'] else ('n:' + norm_name(p['name']) + ('|rd' if p['regional'] else ''))
        if p['email'] and p['regional']:
            key += '|rd'
        if key in ('n:', 'n:|rd'):
            # No name and no email -- TriCity, where the doc just says "??".
            # Keyed on the phone so the same unknown person listed under all
            # three roles is one row with three flags, not three rows.
            digits = re.sub(r'\D', '', ' '.join(p['phones']))
            key = ('p:' + digits) if digits else ('x:%d' % len(index))
        if key in index:
            merge(index[key], p)
        else:
            index[key] = p
            people.append(p)

    # The doc gives a person's email in one column and omits it in another
    # (Andrew Larsen has one under Primary Contact, none under Program
    # Administrator). Same name, same Program, same human -- one row.
    for q in list(people):
        if q['email']:
            continue
        twin = next((o for o in people
                     if o is not q and o['email'] and o['regional'] == q['regional']
                     and norm_name(o['name']) and norm_name(o['name']) == norm_name(q['name'])), None)
        if twin:
            merge(twin, q)
            people.remove(q)

    # explicit "CC: <name or email>" lines lower in the doc
    for ref in rec['cc_refs']:
        hit = None
        for p in people:
            if ('@' in ref and p['email'].lower() == ref.lower()) or norm_name(p['name']) == norm_name(ref):
                hit = p
                break
        if hit and hit['cc'] is not False:
            hit['cc'] = True
        elif not hit and ref.strip():
            flags.append((rec['program'], 'CC list names "%s", who is not one of this Program\'s contacts' % ref))

    prim = next((p for p in people if p['roles']['primary']), None)
    street = city = state = zipc = phone = ''
    if prim:
        street, city, state, zipc = split_address(prim['address'])
        phone = re.sub(r'^[A-Za-z]+:\s*', '', prim['phones'][0]) if prim['phones'] else ''
    # The doc doesn't always put the address in the Primary Contact block
    # (Lucas County keeps it under Program Administrator). Fall back to the
    # first contact who has one rather than leaving the Program address blank.
    if not city:
        dom = prim['email'].split('@')[-1].lower() if prim and prim['email'] else None
        for q in people:
            if dom and q['email'].split('@')[-1].lower() != dom:
                continue      # a colleague at another organisation, not this
                              # Program's own address (EDPNC's admin list
                              # includes people at ccedp.com and ncsu.edu)
            st2, c2, s2, z2 = split_address(q['address'])
            if c2:
                street, city, state, zipc = st2, c2, s2, z2
                break

    for p in people:
        p['address_str'] = ', '.join(p['address'])
        p['phone_str'] = ' / '.join(p['phones'])
        extra = list(p['notes'])
        if p['address_str'] and p['address_str'] != ', '.join([street] if street else []):
            extra.append(p['address_str'])
        if p['org']:
            extra.insert(0, p['org'])
        p['notes_str'] = '\n'.join(x for x in extra if x)
        p['region'] = (p['org'] or p['title']) if p['regional'] else ''
        # Data the doc itself can't support -- surfaced rather than guessed at.
        if p['email'] and not re.search(r'@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$', p['email']):
            flags.append((rec['program'], 'email "%s" (%s) has no domain ending -- imported as written' % (p['email'], p['name'] or '?')))
        for ph in p['phones']:
            digits = re.sub(r'\D', '', ph)
            if len(digits) not in (0, 10, 11) and not re.search(r'x|ext', ph, re.I):
                flags.append((rec['program'], 'phone "%s" (%s) is %d digits' % (ph, p['name'] or '?', len(digits))))
        if not p['name']:
            flags.append((rec['program'], 'a %s contact has no name in the doc (%s)' % (p['role'], p['email'] or p['phone_str'] or '??')))

    programs.append({'program': rec['program'], 'people': people, 'empty': rec['empty'],
                     'street': street, 'city': city, 'state': state, 'zip': zipc, 'phone': phone,
                     'notes': sorted(set(rec.get('notes', [])))})

json.dump({'programs': programs, 'flags': flags}, open('import/final.json', 'w'), indent=1)
print('programs', len(programs), 'people', sum(len(p['people']) for p in programs), 'flags', len(flags))
for f in flags:
    print('  !', f[0], '--', f[1])
