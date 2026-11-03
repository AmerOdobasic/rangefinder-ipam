-- 04_views.sql  
-- Owner: Marc
USE rangefinder;

-- What you need to do (Auditor use cases):
--  1. v_subnet_utilization   per subnet: total IPs, assigned, available, % available
--  2. v_vlan_utilization     same totals rolled (added to totals at a higher level) up per VLAN (Step 2 says "subnets and VLANs")
--  3. v_rack_space           per rack: total_units, used units (SUM Device.rack_units), free units
--  4. v_location_rack_space  rack space rolled up per location / server room
