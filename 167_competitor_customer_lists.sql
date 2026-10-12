-- 167: Competitors and Customers become a file or a link.
--
-- Greg (10/12/26): "let's simplify the customers and competitors list pages
-- down to a simple button to upload a file or a link. With that, maybe we
-- can even combine them into a single step."
--
-- Nobody was typing thirty competitors into a spreadsheet-style editor a row
-- at a time -- they already had the list in a file. Two wizard steps with
-- inline add-row forms and CSV import/export become one step with two slots,
-- each holding one file OR one link, the same shape every other document
-- slot in the app uses.
--
-- client_competitors and client_top_customers are left in place and still
-- read by get_client_public_view; nothing writes to them any more, and the
-- client-facing dashboard no longer renders them. Retiring both tables, and
-- dropping competitors/top_customers from that view, belongs with the rest
-- of the go-live cleanup (punch list #310).

alter table client_content
  add column if not exists competitor_list_url text,
  add column if not exists competitor_list_storage_path text,
  add column if not exists customer_list_url text,
  add column if not exists customer_list_storage_path text;
