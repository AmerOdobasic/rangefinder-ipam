-- 05_seed.sql 
-- Owners: Amer and Marc
USE rangefinder;

-- What to do: 2-3 locations, a few racks, 3-4 VLANs, a /24 and a /28 subnet (call sp_generate_ips),
-- about 20 devices, a few hundred IP rows, 3 User_Account rows (fake hashes only btw).
-- Keep trigger test cases (so duplicate IP, overlapping subnet, delete subnet with assigned IP,
-- delete device) in 06_queries.sql, not written here tho, so the build never fails on purpose...
