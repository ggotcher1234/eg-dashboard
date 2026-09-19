# EG Dashboard — DNS setup for send.economicgardening.org

**For:** Eric (DNS for economicgardening.org)
**From:** Greg Gotcher
**What this is for:** letting the EG Dashboard send its automated email from an economicgardening.org address instead of a testing address.

Two jobs here, both small:

1. **Add three DNS records** so Resend can send as the domain.
2. **Set up one forwarding address** so replies to those emails reach a person.

Nothing here touches the existing mail for economicgardening.org. No MX record on the root domain changes, and the root SPF record is not edited.

---

## Background (30 seconds)

The dashboard is hosted on Netlify, but Netlify never sends email — the sending goes through **Resend**. Today it sends from `onboarding@resend.dev`, Resend's shared *testing* address, which can only deliver to the Resend account owner and rejects the whole send for anyone else. That's why the "new application received" notices haven't been arriving.

The fix is to prove that economicgardening.org authorizes Resend to send for it. That's what these records do.

---

## Job 1 — the three DNS records

Greg has added **`send.economicgardening.org`** in Resend, and its dashboard now lists the exact records. **Copy the values from that screen, not from this page** — the DKIM key is long, unique to this domain, and truncated in every screenshot.

What to expect:

| Type | Name | Content | TTL |
|------|------|---------|-----|
| TXT | `resend._domainkey.send` | `p=MIGfMA…wIDAQAB` (long key) | Auto |
| CNAME | `rsend.send` | `rsend.fo….mta.net` | Auto |
| CNAME | `send.send` | `send.for….mta.net` | Auto |

Points that cause most failed verifications:

- **The names already include `.send`.** They're written relative to the root zone, so `rsend.send` becomes `rsend.send.economicgardening.org`. If your DNS host appends the domain automatically, enter them exactly as above. If it wants the full name, spell it out — just don't end up with `…send.economicgardening.org.economicgardening.org`.
- **Two of the three are CNAMEs, not TXT.** Resend uses CNAMEs pointing at their mail infrastructure rather than an SPF TXT record on the subdomain.
- **Don't add quotes** around the DKIM value unless the host requires them, and don't let it break the key across lines.
- **Leave the root domain's MX and SPF alone.** Everything here lives under `send.` or `_domainkey`.
- **TTL:** Auto / default.

Verification usually completes within about 15 minutes of the records going live; DNS can occasionally take up to 72 hours.

---

## Job 2 — one forwarding address for replies

The dashboard will send from a no-reply style address on the subdomain. That address doesn't need a mailbox to *send* — but if a recipient hits Reply, the message has to land somewhere real.

**Preferred, if it's easy on your side:** create a forwarding address on the **root** domain pointed at Chris:

```
egdashboard@economicgardening.org   →   forwards to: cgibbons@economicgardening.org
```

Root rather than the subdomain, because:

- It needs no MX record on `send.economicgardening.org`, so it can't interfere with the sending setup above.
- It reads better to anyone who looks at the reply address.
- On Google Workspace it's a one-minute alias or group; most other hosts have a plain "forwarder" field.

If you'd rather keep everything on the subdomain, a forwarder at `replies@send.economicgardening.org` works too — that one does need an MX record on `send.economicgardening.org` pointed at whatever handles the forwarding, added alongside (not instead of) the records in Job 1.

Either way, tell Greg the final address and he'll wire it in as the Reply-To.

Worth a sanity check on your side: both addresses are on economicgardening.org, so this is a forward from one address on the domain to another on the same domain. On Google Workspace that's an alias on Chris's account rather than a forwarding rule, which is simpler and avoids a loop.

---

## After it verifies — Greg's side, not Eric's

1. Resend shows the domain **Verified**.
2. Change the send address in `supabase/functions/public-submit-application/index.ts` from `onboarding@resend.dev` to `EG Dashboard <noreply@send.economicgardening.org>`, and add the Reply-To from Job 2.
3. Redeploy that edge function from the Supabase dashboard.
4. Test: submit an application through a program link and confirm it reaches all three recipients — Greg, Chris and Rita — not just the Resend account owner.

---

## Optional, and deliberately separate: DMARC

Worth checking whether `_dmarc.economicgardening.org` exists. If it does, nothing to do — a subdomain inherits it. If it doesn't, adding one is good hygiene but it governs **all** mail for the domain including everyone's day-to-day email, so it deserves its own change rather than riding along with this one. A safe start is monitor-only:

| Type | Name | Content |
|------|------|---------|
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:cgibbons@economicgardening.org` |

`p=none` changes no delivery behavior — it only asks receiving servers for reports.
