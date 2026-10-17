-- A property can have at most 5 photos (same as marketplace items and cars).
create or replace function public.eedb_limit_property_images() returns trigger
language plpgsql as $$
begin
  if (select count(*) from public.property_images where property_id = new.property_id) >= 5 then
    raise exception 'A property can have at most 5 photos';
  end if;
  return new;
end $$;
drop trigger if exists property_images_limit on public.property_images;
create trigger property_images_limit before insert on public.property_images
  for each row execute function public.eedb_limit_property_images();
