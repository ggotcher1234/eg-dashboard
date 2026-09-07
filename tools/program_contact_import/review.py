# -*- coding: utf-8 -*-
import json, io, html

d = json.load(open('import/final.json'))
progs, flags = d['programs'], d['flags']
esc = lambda t: html.escape(str(t or ''))

ROWS = []
for r in progs:
    addr = ', '.join(x for x in [r['street'], ' '.join(x for x in [r['city'], r['state'], r['zip']] if x)] if x)
    people = [p for p in r['people'] if not p['regional']]
    rds    = [p for p in r['people'] if p['regional']]
    body = ''
    if not r['people']:
        body = '<tr><td colspan="6" class="muted">Chris\'s doc has no contacts for this Program &mdash; only the heading.</td></tr>'
    for p in people + rds:
        roles = []
        if p['roles']['primary']: roles.append('<b class="tag">Primary</b>')
        if p['roles']['admin']:   roles.append('<b class="tag">Admin</b>')
        if p['roles']['finance']: roles.append('<b class="tag">Finance</b>')
        if p['regional']:         roles.append('<b class="tag tag-rd">Regional Director</b>')
        if p['cc']:               roles.append('<b class="tag tag-cc">CC</b>')
        if p['cc'] is False:      roles.append('<b class="tag tag-no">Do not CC</b>')
        extra = ' / '.join(x for x in [p['org'], p['address_str']] if x)
        body += ('<tr><td>%s%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class="sm">%s</td></tr>' % (
            '<b>' + esc(p['name']) + '</b>' if p['name'] else '<span class="muted">(no name in the doc)</span>',
            ('<div class="sm muted">' + esc(p['region']) + '</div>') if p['region'] else '',
            esc(p['title']), esc(p['email']), esc(p['phone_str']),
            ' '.join(roles), esc('\n'.join(x for x in [extra] + p['notes'] if x))))
    ROWS.append("""
    <section>
      <h2>%s <span class="count">%d %s</span></h2>
      <p class="addr">%s%s</p>
      %s
      <table><thead><tr><th>Name</th><th>Title</th><th>Email</th><th>Phone</th><th>Roles</th><th>Organisation / notes</th></tr></thead>
      <tbody>%s</tbody></table>
    </section>""" % (
        esc(r['program']), len(r['people']), 'person' if len(r['people']) == 1 else 'people',
        esc(addr) or '<span class="muted">no address in the doc</span>',
        (' &middot; ' + esc(r['phone'])) if r['phone'] else '',
        ('<p class="pnote">Program note: ' + esc('  '.join(r['notes'])) + '</p>') if r['notes'] else '',
        body))

flag_html = ''.join('<li><b>%s</b> &mdash; %s</li>' % (esc(a), esc(b)) for a, b in flags)

TPL = """<!doctype html><meta charset="utf-8"><title>Program contact import &mdash; review</title>
<style>
 :root{--navy:#1e3a5f;--muted:#6b7a8f;--border:#dfe4ea;--bg:#f6f8fa}
 *{box-sizing:border-box} body{margin:0;font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;color:#1c2430;background:var(--bg)}
 .wrap{max-width:1180px;margin:0 auto;padding:28px 22px 70px}
 h1{color:var(--navy);margin:0 0 4px;font-size:24px}
 .lede{color:var(--muted);margin:0 0 22px}
 .box{background:#fff;border:1px solid var(--border);border-radius:10px;padding:14px 18px;margin-bottom:22px}
 .box h3{margin:0 0 8px;font-size:14px;color:var(--navy)}
 .box ul{margin:0;padding-left:18px} .box li{margin-bottom:4px}
 section{background:#fff;border:1px solid var(--border);border-radius:10px;padding:14px 18px;margin-bottom:14px}
 h2{font-size:15px;color:var(--navy);margin:0 0 2px}
 .count{font-weight:400;font-size:12px;color:var(--muted)}
 .addr{margin:0 0 10px;font-size:12.5px;color:var(--muted)}
 .pnote{margin:0 0 10px;font-size:12.5px;background:#fffbe9;border:1px solid #f0e3b2;border-radius:6px;padding:6px 9px}
 table{width:100%;border-collapse:collapse}
 th{text-align:left;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);border-bottom:1px solid var(--border);padding:5px 8px 5px 0}
 td{padding:6px 8px 6px 0;border-bottom:1px solid #eef1f4;vertical-align:top;font-size:13px}
 tr:last-child td{border-bottom:none}
 .sm{font-size:11.5px;color:var(--muted);white-space:pre-line}
 .muted{color:var(--muted)}
 .tag{display:inline-block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.04em;
      background:#eaf0f7;color:var(--navy);border-radius:4px;padding:2px 5px;margin:0 3px 2px 0}
 .tag-rd{background:#eef6ee;color:#2f6b3a} .tag-cc{background:#f2edf9;color:#5b3f8c}
 .tag-no{background:#fdeceb;color:#a3352c}
</style>
<div class="wrap">
<h1>Program contact import &mdash; what will land in the dashboard</h1>
<p class="lede">Parsed from Chris's <i>EG PROGRAMS CONTACT INFO</i>, 6/25/26. @NPROG@ Programs, @NPEOPLE@ people.
A person listed under more than one heading is one row here with more than one role ticked.</p>
<div class="box"><h3>Worth a look before you run it</h3><ul>@FLAGS@</ul></div>
@SECTIONS@
</div>"""

doc = (TPL.replace('@NPROG@', str(len(progs)))
          .replace('@NPEOPLE@', str(sum(len(p['people']) for p in progs)))
          .replace('@FLAGS@', flag_html or '<li class="muted">Nothing ambiguous turned up.</li>')
          .replace('@SECTIONS@', ''.join(ROWS)))

io.open('import/import_review.html', 'w', encoding='utf-8').write(doc)
print('wrote review,', len(doc), 'bytes')
