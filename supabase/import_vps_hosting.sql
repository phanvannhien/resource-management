-- Nhập dữ liệu từ VPS_Hosting_final.xlsx (sinh tự động).
-- Chạy trong Supabase → SQL Editor. Chạy lại nhiều lần không bị trùng (tự xoá lần nhập trước).

-- 1. Cho phép loại dịch vụ OTHER (bảo trì, SSL, email...)
alter table public.services drop constraint if exists services_type_check;
alter table public.services add constraint services_type_check
  check (type in ('DOMAIN', 'HOSTING', 'VPS', 'OTHER'));

-- 2. Nhập dữ liệu
do $$
declare
  uid uuid;
  c uuid;
  h uuid;
  v uuid;
begin
  -- Gán cho user đăng nhập gần nhất (tài khoản đang dùng trên app).
  -- Muốn chỉ định user khác: đổi thành  select id into uid from auth.users where email = 'email@cua-ban';
  select id into uid from auth.users
  where last_sign_in_at is not null
  order by last_sign_in_at desc
  limit 1;
  if uid is null then
    raise exception 'Chưa có user nào đăng nhập app. Hãy đăng nhập app 1 lần rồi chạy lại.';
  end if;

  -- Xoá dữ liệu của lần nhập trước (nếu có) để nhập lại không bị trùng
  delete from public.services  where owner_id = uid and note like '%[import VPS_Hosting.xlsx]%';
  delete from public.customers where owner_id = uid and note like '%[import VPS_Hosting.xlsx]%';
  delete from public.providers where owner_id = uid and note like '%[import VPS_Hosting.xlsx]%';


  -- A Giang · canhquanthanhpho.com · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'A Giang', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'canhquanthanhpho.com', c, '2019-07-01', '2023-07-01', 12, 800000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Chị Thủy · canhocantavil.net · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Chị Thủy', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'canhocantavil.net', c, '2022-09-16', '2025-09-16', 12, 800000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Bảo Viralwave · viralwave.vn · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Bảo Viralwave', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'viralwave.vn', c, '2026-09-13', '2027-09-13', 12, 800000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Hưng bạn Duẫn · leskinbysui.com · Domain & Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Hưng bạn Duẫn', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'leskinbysui.com', c, '2021-12-28', '2026-12-28', 12, 1200000, '[import VPS_Hosting.xlsx]') returning id into h;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, linked_hosting_id, note)
  values (uid, 'DOMAIN', 'leskinbysui.com', c, '2021-12-28', '2026-12-28', 12, 380000, h, '[import VPS_Hosting.xlsx]');

  -- Bà Phương · truonggiahuy.com.vn · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Bà Phương', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'truonggiahuy.com.vn', c, '2020-04-24', '2027-04-24', 12, 1200000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- A Hóa bạn Cao · phattienelectric.vn · Domain & Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'A Hóa bạn Cao', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'phattienelectric.vn', c, '2018-12-01', '2026-12-01', 12, 800000, '[import VPS_Hosting.xlsx]') returning id into h;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, linked_hosting_id, note)
  values (uid, 'DOMAIN', 'phattienelectric.vn', c, '2018-12-01', '2026-12-01', 12, 450000, h, '[import VPS_Hosting.xlsx]');

  -- Nhi Milestone · traphuson.vn · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Nhi Milestone', '0902474144', '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'traphuson.vn', c, '2026-01-07', '2027-01-07', 12, 800000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Anh Nam · hoangthiennam.vn · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Anh Nam', '0931277277', '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'hoangthiennam.vn', c, '2017-03-10', '2027-03-10', 12, 800000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Chương · chuongbee.com · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Chương', '0389941454', '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'chuongbee.com', c, null, '2026-11-03', 12, 800000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Bà Phương (đã có) · mh-intercon.com · Hosting
  select id into c from public.customers where owner_id = uid and name = 'Bà Phương' and note like '%[import VPS_Hosting.xlsx]%';
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'mh-intercon.com', c, '2026-04-01', '2027-04-01', 12, 1200000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Gongcha · gongcha.com.vn · Maintenance
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Gongcha', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'OTHER', 'Bảo trì gongcha.com.vn', c, null, '2027-06-11', 12, 6500000, '[import VPS_Hosting.xlsx]');

  -- LyLy · klamed.vn · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'LyLy', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'klamed.vn', c, '2025-12-11', '2026-12-11', 12, 1500000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- Dương Gongcha · darmi.vn · Hosting
  insert into public.customers (owner_id, name, phone, note)
  values (uid, 'Dương Gongcha', null, '[import VPS_Hosting.xlsx]') returning id into c;
  insert into public.services (owner_id, type, name, customer_id, start_date, expiry_date, cycle_months, sell_price, note)
  values (uid, 'HOSTING', 'darmi.vn', c, '2026-03-09', '2027-03-09', 12, 1500000, '[import VPS_Hosting.xlsx]') returning id into h;

  -- VPS Nhiên Contabo
  insert into public.providers (owner_id, name, note) values (uid, 'Contabo', '[import VPS_Hosting.xlsx]') returning id into v;
  insert into public.services (owner_id, type, name, provider_id, start_date, expiry_date, cycle_months, note)
  values (uid, 'VPS', 'VPS Nhiên Contabo', v, '2026-02-09', '2027-02-09', 12, '[import VPS_Hosting.xlsx]');

end $$;

-- 3. Kiểm tra kết quả: dữ liệu đã gán cho email nào
select u.email,
       count(distinct s.id) as so_dich_vu,
       count(distinct s.customer_id) as so_khach
from public.services s
join auth.users u on u.id = s.owner_id
where s.note like '%[import VPS_Hosting.xlsx]%'
group by u.email;

-- Muốn xoá toàn bộ dữ liệu vừa nhập thì chạy:
-- delete from public.services  where note like '%[import VPS_Hosting.xlsx]%';
-- delete from public.customers where note like '%[import VPS_Hosting.xlsx]%';
-- delete from public.providers where note like '%[import VPS_Hosting.xlsx]%';

