-- 094_client_other_social_url.sql
--
-- Greg (8/29/26): "i don't want social media links here [on application
-- intake]. they need to be on the company page with the website link and i
-- want a field for each social media link. FaceBook, LinkedIn, X/Twitter,
-- Instagram, YouTube, and Other." The first 5 already exist as per-platform
-- columns on `clients` (linkedin_url/facebook_url/instagram_url/twitter_url/
-- youtube_url, from 019_client_profile_content.sql). This adds the 6th:
-- a free-form "Other" link for whatever platform doesn't have its own field.
--
-- Safe to re-run.

alter table clients add column if not exists other_social_url text;
