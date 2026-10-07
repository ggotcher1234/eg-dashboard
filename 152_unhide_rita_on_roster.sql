-- 152: Rita back on the Roster.
--
-- Rita (10/7/26): "When I log in I don't see my name in the Roster. Only the
-- archived one."
--
-- She is not archived, and there has never been a second Rita record -- the
-- only archived rows in users are duplicate Chris and Greg accounts (144).
-- What hid her was users.hidden_from_roster, set by 108, which deliberately
-- kept all three admins off the Roster and off every specialist / team-lead
-- pick list.
--
-- That decision has since been unwound for the other two and not for her:
-- Chris and Greg both read hidden_from_roster = false, Greg's on purpose
-- ("my Roster account needs to say Team Lead even though i have admin
-- capability", 10/6/26). Rita was the only one still carrying the flag, so
-- the Roster she administers was the one place she could not find herself.
--
-- Nothing else changes: she keeps super_admin, and her Roster card shows
-- "Admin" from primaryCategoryLabel()'s fallback, which for her is correct --
-- it is also already her title.
--
-- Applied 10/7/26.

update users
   set hidden_from_roster = false
 where email = 'rbenson@economicgardening.org'
   and archived_at is null;
