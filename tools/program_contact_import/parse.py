# -*- coding: utf-8 -*-
"""Parse Chris's "EG PROGRAMS CONTACT INFO" doc into structured contacts.

The doc is prose in a 3-column table, so nothing here is a clean field split.
The anchors that ARE reliable: an email address is unique per person, and a
person's own name is the most "person-shaped" line in the run of lines
preceding their email. Everything else (org, address, phone, notes) is
classified by shape and hung off that person.
"""
import json, re, unicodedata

blocks = json.load(open('import/blocks.json'))

ORG_WORDS = re.compile(r'\b(count(y|ies)|authority|council|chamber|corp|corporation|alliance|'
                       r'partnership|university|universities|city of|town of|department|dept|'
                       r'development|commission|government|board|solutions|strategy|advisors|'
                       r'enterprise|fund|foundation|association|agency|institute|center|centre|'
                       r'college|school|district|group|company|llc|inc\.?|ltd|network|'
                       r'squared|planning|regional|economic|econ dev|zoning|purchasing|'
                       r'innovation|industry|services|kansas|valley|builders|ies)\b', re.I)

TITLE_WORDS = re.compile(r'\b(director|dir\.?|manager|mgr\.?|president|vice president|vp|'
                         r'ceo|coo|cfo|officer|coach|specialist|administrator|admin|'
                         r'consultant|coordinator|analyst|chief|executive|senior|sr\.?|jr\.?|'
                         r'associate|assistant|deputy|supervisor|engagement|intern|'
                         r'business|marketing|communications|research|relations|operations|'
                         r'ops|support|mep|non-credit|statewide|attraction|retention|'
                         r'small business|project|program)\b', re.I)

EMAIL_RE = re.compile(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+')
PHONE_RE = re.compile(r'(?:\+?1[\s.\-]?)?\(?\d{3}\)?[\s.\-]\d{3}[\s.\-]\d{3,4}(?:\s*(?:x|ext\.?)\s*\d+)?')
ZIP_RE   = re.compile(r'\b[A-Z][A-Za-z .]{1,20},?\s+[A-Z]{2}\.?\s+\d{5}\b|\b\d{5}(-\d{4})?\b')
STREET_RE = re.compile(r'^\s*(p\.?\s*o\.?\s*box|pob\b|campus box|\d+\s+[A-Za-z])', re.I)
ADDR_HINT = re.compile(r'\b(suite|ste\.?|floor|fl\.?|#\d|apt|pmb|box|street|st\.|avenue|ave\.?|'
                       r'road|rd\.?|drive|dr\.?|blvd|boulevard|lane|ln\.?|way|court|ct\.?|'
                       r'circle|parkway|pkwy|crossing|building)\b', re.I)
STATE_ZIP_RE = re.compile(r'^(?P<city>[A-Za-z .\'\-]+),?\s+(?P<state>[A-Za-z ]{2,20}?)\.?\s+(?P<zip>\d{5}(?:-\d{4})?)\s*$')

NOTE_RE = re.compile(r'\b(no nd[ac]|yes nda|\(\d+\s*co\)|\+\s*\d+\s*yrs?|\+\d)\b', re.I)
DATE_RE = re.compile(r'\b\d{1,2}/\d{1,2}/\d{2,4}\b|\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2},\s*\d{4}\b', re.I)

SECTION_RD  = re.compile(r'^\s*(regional directors?|regional managers?)\s*:?\s*$', re.I)
SECTION_ALL = re.compile(r'^\s*all communications\s*:?\s*$', re.I)
SECTION_NOCC= re.compile(r'^\s*do not cc\s*:?\s*$', re.I)
CC_LINE     = re.compile(r'^\s*cc\s*:\s*(.+)$', re.I)

ROLE_HEAD = re.compile(r'^\s*(primary contact|program administrator|program finance)\s*$', re.I)

LABELLED = re.compile(r'^\s*(email|e-mail|phone|office|mobile|cell|direct|tel|fax)\s*:\s*', re.I)


def fix_email_typos(line):
    # "smrice@annapolis,gov" -- a comma typed where the period belongs. The
    # regex would otherwise stop at "annapolis" and drop "gov" into the notes.
    return re.sub(r'(@[A-Za-z0-9.\-]+),(?=(gov|com|org|net|edu|us|biz)\b)', r'\1.', line, flags=re.I)


def clean_email(e):
    e = e.strip().strip('.,;:<>()[]"\'')
    # ", gov" / ", com" -- comma typed for a period in the TLD.
    e = re.sub(r',(?=(gov|com|org|net|edu|us|biz)\b)', '.', e, flags=re.I)
    return e


def is_addressish(line):
    if STREET_RE.search(line):
        return True
    if STATE_ZIP_RE.match(line.strip()):
        return True
    if ADDR_HINT.search(line) and re.search(r'\d', line) and not TITLE_WORDS.search(line):
        return True
    return False


def person_score(line):
    """How much this line looks like a human being's name (with optional title)."""
    s = line.strip().rstrip('|').strip()
    if not s or '@' in s:
        return -99
    if is_addressish(s):
        return -99
    if re.match(r'^[\d(+]', s):
        return -99
    if LABELLED.match(s):
        return -99
    if NOTE_RE.search(s) or DATE_RE.search(s):
        return -99
    if is_title_line(s):
        return -5
    head = s.split(',')[0].strip()
    toks = head.split()
    if len(toks) > 4:
        if (len(toks) >= 3 and re.match(r"^[A-Z][a-z.'\-]+$", toks[0])
                and re.match(r"^[A-Z][a-z.'\-]+$", toks[1])
                and toks[2][:1].islower()):
            return 2      # "Firstname Lastname <lowercase description>"
        return -99
    if len(toks) < 1:
        return -99
    if not re.match(r"^[A-Z][A-Za-z.'\-]*$", toks[0]):
        return -99
    score = 0
    if len(toks) in (2, 3):
        score += 3
    if ORG_WORDS.search(head):
        score -= 6
    if ',' in s and TITLE_WORDS.search(s.split(',', 1)[1]):
        score += 4          # "Name, Title" -- the strongest signal in the doc
    if all(re.match(r"^[A-Z][a-z.'\-]+$", t) or re.match(r'^[A-Z]\.$', t) for t in toks):
        score += 2
    if s.strip() == '??':
        score = 1
    return score


PURE_TITLE = re.compile(
    r'^\s*(managing|senior|sr\.?|jr\.?|assistant|deputy|associate|interim|acting|global|'
    r'executive|vice|exec\.?|chief|lead|principal|regional|statewide|county|business|'
    r'development|economic|marketing|program|project|research|operations|support|'
    r'director|dir\.?|manager|mgr\.?|president|vp|ceo|coo|cfo|officer|coach|specialist|'
    r'administrator|consultant|coordinator|analyst|engagement|attraction|retention|'
    r'communications|relations|services|service|purchasing|budget|mktg|ops|existing|'
    r'industry|expansion|innovation|planning|zoning|markets|new|small|finance|'
    r'administration|sales|non-credit|credit|mep|staff|dev\.?|of|and|&|the|for|,|\s)+$', re.I)


def is_title_line(line):
    head = line.split(',')[0].strip()
    return bool(head) and bool(PURE_TITLE.match(line.strip()))


def new_person():
    return {'name': '', 'title': '', 'org': '', 'address': [], 'email': '', 'phones': [],
            'notes': [], 'regional': False, 'cc': None}


def split_name_title(line):
    s = line.strip().rstrip('|').strip()
    s = s.strip(' |-\u2013\u2014,')
    s = re.sub(r'\s+(at|or|and)$', '', s, flags=re.I)
    toks = s.split(',')[0].split()
    if len(toks) > 4 and toks[2][:1].islower():
        return ' '.join(toks[:2]), ' '.join(toks[2:])
    if ',' in s:
        head, rest = s.split(',', 1)
        return head.strip(), rest.strip().strip(',').strip()
    # "Matt Hurlbutt" then a separate title line -- handled by the caller
    return s, ''


def finalize(p, pending):
    """Turn a buffer of unclassified lines into name/title/org/address."""
    cands = [(person_score(l), i, l) for i, l in enumerate(pending)]
    best = max(cands, key=lambda c: (c[0], -c[1])) if cands else None
    if best and best[0] > 0:
        p['name'], p['title'] = split_name_title(best[2])
        used = best[1]
    else:
        used = None
    for i, l in enumerate(pending):
        if i == used:
            continue
        s = l.strip().strip(' |,')
        if not s:
            continue
        if is_addressish(s):
            p['address'].append(s)
        elif NOTE_RE.search(s) or DATE_RE.search(s):
            p['notes'].append(s)
        elif person_score(s) <= 0 and not p['org'].endswith(s):
            p['org'] = (p['org'] + ', ' + s).strip(', ') if p['org'] else s
        elif not p['title'] and TITLE_WORDS.search(s) and len(s.split()) <= 8:
            p['title'] = s
        else:
            p['notes'].append(s)
    # A leading title that landed in `org` because it mentions a word the org
    # test also uses ("Industry Relations", "Business Services"). If the line
    # starts like a job title and the person has no title yet, it is one.
    if not p['title'] and p['org'] and re.match(
            r'^(director|dir\b|manager|mgr\b|president|vice president|vp\b|ceo|coo|cfo|'
            r'chief|executive|senior|sr\.?|associate|assistant|deputy|business|'
            r'regional manager)', p['org'], re.I) and not re.search(
            r'\b(count(y|ies)|authority|council|chamber|corp|university|city of|town of)\b',
            p['org'], re.I):
        p['title'] = p['org']; p['org'] = ''
    # Stray fragments left by the doc's own typos: "brian@regeneration.us>".
    p['org'] = re.sub(r'[,\s]*>+\s*$', '', p['org']).strip(' ,')
    p['notes'] = [n for n in p['notes'] if len(n.strip(' >.,')) > 2]
    return p


def parse_cell(text, role):
    people, cur, pending = [], None, []
    regional_mode = False
    nocc_mode = False
    all_comms = False
    cc_refs = []
    section_org = ''

    def flush():
        nonlocal cur, pending
        if cur is not None:
            finalize(cur, pending)
            if cur['name'] or cur['email'] or cur['phones']:
                people.append(cur)
            else:
                # A fragment with no person in it -- almost always one of
                # Chris's contract notes ("7/1/19 (10 co) No NDA") sitting on
                # its own after a contact. Those describe the Program, so they
                # go there rather than being dropped.
                orphan_notes.extend(cur['notes'])
                orphan_notes.extend(l for l in pending if l.strip())
        cur, pending = None, []

    lines = [fix_email_typos(l.rstrip()) for l in text.split('\n')]
    orphan_notes = []
    for raw in lines:
        line = raw.strip()
        if not line:
            # Chris separates contacts inside a cell with a blank line. It is
            # the only boundary the doc gives for a person with no email, and
            # without it the next person's name gets absorbed into this one.
            flush()
            continue
        if ROLE_HEAD.match(line):
            continue
        if SECTION_RD.match(line):
            flush(); regional_mode = True; section_org = ''; continue
        if SECTION_ALL.match(line):
            flush(); all_comms = True; continue
        if SECTION_NOCC.match(line):
            flush(); nocc_mode = True; continue
        m = CC_LINE.match(line)
        if m and '@' not in m.group(1) and person_score(m.group(1)) > 0:
            cc_refs.append(m.group(1).strip()); continue
        if m and '@' in m.group(1):
            cc_refs.append(clean_email(EMAIL_RE.search(m.group(1)).group(0))); continue

        emails = EMAIL_RE.findall(line)
        if emails:
            rest = EMAIL_RE.sub('', line)
            rest = LABELLED.sub('', rest)
            rest = PHONE_RE.sub('', rest)
            rest = re.sub(r'\((?:as of|effective)[^)]*\)', '', rest, flags=re.I)
            rest = re.sub(r'\s+(at|or|and)\s*$', '', rest.strip(' |\t,;'), flags=re.I)
            rest = rest.strip(' |\t,;')
            if cur is None:
                cur = new_person()
            if cur['email']:
                # second email in one run -> that's a second person
                flush(); cur = new_person()
            if rest:
                pending.append(rest)
            cur['email'] = clean_email(emails[0])
            for extra in emails[1:]:
                cur['notes'].append('also: ' + clean_email(extra))
            for ph in PHONE_RE.findall(line):
                pass
            cur['regional'] = regional_mode
            cur['cc'] = (False if nocc_mode else (True if all_comms else None))
            if regional_mode:
                cur['_section_org'] = section_org
            continue

        phones = PHONE_RE.findall(line)
        if phones and not person_score(line) > 0:
            label = ''
            lm = LABELLED.match(line)
            if lm:
                label = lm.group(1).title() + ': '
            found = PHONE_RE.findall(line)
            target = cur if cur is not None else None
            if target is None:
                cur = new_person(); cur['regional'] = regional_mode
                cur['cc'] = (False if nocc_mode else (True if all_comms else None))
                target = cur
            for ph in found:
                lbl = ''
                mm = re.search(r'(office|mobile|cell|direct|phone|tel|fax)\s*:?\s*' + re.escape(ph), line, re.I)
                if mm:
                    lbl = mm.group(1).title() + ': '
                elif '(office)' in line.lower() and ph in line:
                    lbl = 'Office: '
                elif '(cell)' in line.lower() and ph in line:
                    lbl = 'Cell: '
                target['phones'].append((lbl + ph).strip())
            leftover = PHONE_RE.sub('', line)
            leftover = re.sub(r'\b(office|mobile|cell|direct|phone|tel|fax)\s*:?', '', leftover, flags=re.I)
            leftover = leftover.strip(' |,;:().')
            if leftover and len(leftover) > 2:
                pending.append(leftover)
            continue

        # plain line: name / title / org / address / note.
        #
        # An email is the one reliable per-person anchor in this doc, and every
        # person's own lines come BEFORE theirs (org, name, then email, then
        # phones). So the first plain line after an email belongs to the next
        # person, not this one -- without that the org headings in the Regional
        # Directors lists all attach one person too early.
        if cur is not None and cur['email']:
            flush()

        if cur is None:
            cur = new_person()
            cur['regional'] = regional_mode
            cur['cc'] = (False if nocc_mode else (True if all_comms else None))
            if regional_mode:
                cur['_section_org'] = section_org
        if regional_mode and person_score(line) <= 0 and not is_addressish(line) and not cur['email']:
            section_org = line
            cur['_section_org'] = section_org
        pending.append(line)

    flush()
    for p in people:
        p['role'] = role
    return people, cc_refs, orphan_notes


out = []
for b in blocks:
    rec = {'program': b['program'], 'people': [], 'cc_refs': [], 'empty': not b['cells']}
    if b['cells']:
        for cell, role in zip(b['cells'], ['primary', 'admin', 'finance']):
            ppl, ccs, orphans = parse_cell(cell, role)
            rec['people'] += ppl
            rec['cc_refs'] += ccs
            rec.setdefault('notes', []).extend(orphans)
    out.append(rec)

json.dump(out, open('import/parsed.json', 'w'), indent=1)
print('programs', len(out), 'people rows', sum(len(r['people']) for r in out))
