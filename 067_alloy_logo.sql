-- 067_alloy_logo.sql
--
-- Alloy Development's logo (Greg, 8/21/26) -- shipped as a static file in
-- the repo (alloy-logo.png, alongside NCEG_Logo_transparent.png and every
-- other image this app already serves the same way) rather than uploaded
-- to the program-logos storage bucket from 066. Simpler for a one-off:
-- Netlify serves it at the site root the moment this deploys, no storage
-- upload step needed. The Programs admin screen can still swap this out
-- later via a real upload into program-logos if Greg wants that per-program
-- eventually -- this just gets Alloy's application page branded today.
--
-- Depends on 066_public_program_applications.sql (econ_dev_companies.logo_url).
--
-- Safe to re-run.

update econ_dev_companies
set logo_url = 'alloy-logo.png'
where code = 'ALLOY';
