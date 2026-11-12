-- 194: the Other slot gets a pasted list too.
--
-- Greg (12/11/26): "The optional catch all list should have the same layout
-- as all the others which should include a text box to paste an email or
-- list and the ability to clear the list and list name."
--
-- 189 gave competitors, customers and keywords a freeform box and left this
-- one out, on the reasoning that Greg had named three. The slot is the catch
-- all, so the case 189 was built for -- a handful of names typed into the
-- body of an email, with no document anywhere -- is if anything likelier
-- here than on the three named slots.
--
-- Same shape as 189: its own column, its own save, neither clearing nor
-- cleared by the file/link pair, and stored as the raw text that was pasted.
alter table public.client_content
  add column if not exists other_list_text text;
