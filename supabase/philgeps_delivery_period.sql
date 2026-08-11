-- Run once in the Supabase SQL editor before deploying the updated scraper.
alter table public.philgeps_posts
  add column if not exists delivery_period text not null default '';

comment on column public.philgeps_posts.delivery_period is
  'Delivery Period scraped from the PhilGEPS Bid Notice Abstract.';
