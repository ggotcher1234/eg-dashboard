# Program contact import

Turns Chris's `EG PROGRAMS CONTACT INFO` Word doc into
`113_import_program_contacts.sql`. Checked in so the import can be re-derived
when Chris sends an update, rather than re-typed.

The doc is a 3-column Word table -- Primary Contact / Program Administrator /
Program Finance -- and every cell is free-form prose: name, title,
organisation, address, email and phone in whatever order, plus sub-lists
("Regional Directors", "Regional Managers", "All communications", "Do not
cc:") and contract notes ("7/1/19 (10 co) No NDA"). There is no delimiter to
split on, so the parser leans on the two things the doc is consistent about:
an email address is unique to a person, and a person's own lines come before
their email.

    python3 parse.py     # blocks.json (from the .docx) -> parsed.json
    python3 build.py     # one row per human: merges roles, flags oddities
    python3 gen_sql.py   # -> ../../113_import_program_contacts.sql
    python3 review.py    # -> import_review.html, the human-readable version

`parse.py` reads `blocks.json`, which is the doc's table cells as extracted by
python-docx. To start from a newer doc, re-extract it into that file first.

## Testing the migration

`test_schema.sql` is enough of the real schema to run 112 and 113 against a
throwaway Postgres and check the merge. It seeds Programs deliberately spelled
the way the dashboard might spell them ("Tri-City Regional Chamber" for the
doc's "TRICITY, WASHINGTON") plus contacts that must survive untouched.

    createdb eg
    psql -d eg -f test_schema.sql
    psql -d eg -f ../../112_program_contacts_and_address.sql
    psql -d eg -f ../../113_import_program_contacts.sql   # run twice: the
                                                          # second adds nothing
