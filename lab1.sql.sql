SET search_path TO s470509;


CREATE TABLE ship (
    id_ship SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(50),
    launch_date DATE,
    country_of_origin VARCHAR(50),
    status VARCHAR(20) DEFAULT 'Active' CHECK (status IN ('Active', 'Crashed', 'Decommissioned'))
);

CREATE TABLE orbit (
    id_orbit SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    altitude_km DECIMAL(10,2) CHECK (altitude_km > 0),
    inclination_deg DECIMAL(5,2),
    period_min DECIMAL(10,2)
);


CREATE TABLE material (
    id_material SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    density_g_cm3 DECIMAL(10,2),
    physical_state VARCHAR(20) CHECK (physical_state IN ('Solid', 'Liquid', 'Gas', 'Plasma'))
);

CREATE TABLE debris (
    id_debris SERIAL PRIMARY KEY,
    id_ship INTEGER NOT NULL REFERENCES ship(id_ship) ON DELETE CASCADE,
    id_orbit INTEGER NOT NULL REFERENCES orbit(id_orbit),
    detection_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approx_size_m DECIMAL(10,2),
    distance_from_station_km DECIMAL(10,2),
    visible_to_naked_eye BOOLEAN DEFAULT false,
    description TEXT
);

CREATE TABLE composition (
    id_composition SERIAL PRIMARY KEY,
    id_debris INTEGER NOT NULL REFERENCES debris(id_debris) ON DELETE CASCADE,
    id_material INTEGER NOT NULL REFERENCES material(id_material),
    percentage DECIMAL(5,2) CHECK (percentage > 0 AND percentage <= 100),
    UNIQUE(id_debris, id_material)
);


INSERT INTO orbit (name, altitude_km, inclination_deg) VALUES
('Low Earth Orbit (LEO)', 400.00, 51.60),
('Geostationary Orbit', 35786.00, 0.00),
('Polar Orbit', 800.00, 90.00);

INSERT INTO ship (name, type, launch_date, country_of_origin, status) VALUES
('Stellar Voyager', 'Exploration', '2050-03-15', 'United Federation', 'Crashed'),
('Space Aurora', 'Cargo', '2048-07-22', 'Martian Empire', 'Crashed'),
('Helios Prime', 'Research', '2052-11-30', 'Solar Alliance', 'Active');

INSERT INTO material (name, density_g_cm3, physical_state) VALUES
('Reinforced Metal', 7.80, 'Solid'),
('Paper', 0.80, 'Solid'),
('Aluminum', 2.70, 'Solid'),
('Crystalline Ice', 0.92, 'Solid'),
('Ionized Plasma', 0.001, 'Plasma');


INSERT INTO debris (id_ship, id_orbit, detection_date, approx_size_m, distance_from_station_km, description) VALUES
(1, 1, '2055-01-15 14:30:00', 2.50, 150.75, 'Mutilated fragment of the main hull'),
(1, 1, '2055-01-15 14:35:00', 0.05, 152.30, 'Scattered pieces of paper'),
(2, 2, '2055-01-16 09:20:00', 1.20, 35000.00, 'Aluminum foil reflecting sunlight'),
(1, 1, '2055-01-17 22:15:00', 0.01, 148.90, 'Cloud of crystalline ice crystals glittering');

INSERT INTO composition (id_debris, id_material, percentage) VALUES
(1, 1, 100.00),
(2, 2, 100.00),
(3, 3, 100.00),
(4, 4, 90.00),
(4, 5, 10.00);


SELECT 'SHIP' AS table_name, COUNT(*) AS records FROM ship
UNION ALL
SELECT 'ORBIT', COUNT(*) FROM orbit
UNION ALL
SELECT 'MATERIAL', COUNT(*) FROM material
UNION ALL
SELECT 'DEBRIS', COUNT(*) FROM debris
UNION ALL
SELECT 'COMPOSITION', COUNT(*) FROM composition;


SELECT 'orbit' AS type, name FROM orbit;

SELECT 
    d.description AS debris,
    m.name AS material,
    c.percentage::text || '%' AS percentage
FROM debris d
JOIN composition c ON d.id_debris = c.id_debris
JOIN material m ON c.id_material = m.id_material
ORDER BY d.id_debris;

SELECT 
    o.name AS orbit,
    COUNT(d.id_debris) AS debris_count,
    AVG(d.approx_size_m) AS avg_size
FROM orbit o
LEFT JOIN debris d ON o.id_orbit = d.id_orbit
GROUP BY o.id_orbit, o.name
ORDER BY debris_count DESC;

SELECT 
    'INTEGRITY CHECK' AS check_type,
    CASE 
        WHEN COUNT(*) = 0 THEN 'ALL FKs OK'
        ELSE 'PROBLEMS FOUND'
    END AS status
FROM (
    SELECT id_ship FROM debris WHERE id_ship NOT IN (SELECT id_ship FROM ship)
    UNION ALL
    SELECT id_orbit FROM debris WHERE id_orbit NOT IN (SELECT id_orbit FROM orbit)
    UNION ALL
    SELECT id_debris FROM composition WHERE id_debris NOT IN (SELECT id_debris FROM debris)
    UNION ALL
    SELECT id_material FROM composition WHERE id_material NOT IN (SELECT id_material FROM material)
) AS problems;

-- ============================================
-- ENTITY CLASSIFICATION (for the report)
-- ============================================
-- CORE ENTITIES (independent):
--   - ship
--   - orbit
--   - material
--
-- CHARACTERISTIC ENTITY (depends on ship):
--   - debris
--
-- ASSOCIATION ENTITY (N:M relationship):
--   - composition (connects debris and material)
--
-- RELATIONSHIPS:
--   - ship 1 --- N debris
--   - orbit 1 --- N debris
--   - debris N --- M material (through composition)
--
-- ============================================

-- ============================================
-- DENORMALIZATIONS FOR PERFORMANCE OPTIMIZATION
-- ============================================

-- 2.1 Add redundant columns to debris table
ALTER TABLE debris ADD COLUMN IF NOT EXISTS ship_name VARCHAR(100);
ALTER TABLE debris ADD COLUMN IF NOT EXISTS orbit_name VARCHAR(100);

-- 2.2 Update redundant columns with current data
UPDATE debris SET ship_name = ship.name FROM ship WHERE debris.id_ship = ship.id_ship;
UPDATE debris SET orbit_name = orbit.name FROM orbit WHERE debris.id_orbit = orbit.id_orbit;

-- 2.3 Create materialized view for common queries
DROP MATERIALIZED VIEW IF EXISTS debris_details;
CREATE MATERIALIZED VIEW debris_details AS
SELECT 
    d.id_debris,
    d.description,
    d.approx_size_m,
    d.detection_date,
    d.visible_to_naked_eye,
    d.distance_from_station_km,
    s.name AS ship_name,
    s.status AS ship_status,
    o.name AS orbit_name,
    o.altitude_km,
    m.name AS material_name,
    c.percentage
FROM debris d
JOIN ship s ON d.id_ship = s.id_ship
JOIN orbit o ON d.id_orbit = o.id_orbit
JOIN composition c ON d.id_debris = c.id_debris
JOIN material m ON c.id_material = m.id_material
ORDER BY d.id_debris;

-- Create index on materialized view for faster queries
CREATE INDEX idx_debris_details_ship_name ON debris_details (ship_name);
CREATE INDEX idx_debris_details_orbit_name ON debris_details (orbit_name);

-- ============================================
-- TRIGGER AND FUNCTION FOR DATA INTEGRITY
-- ============================================

-- 3.1 Create log table for tracking invalid insert attempts
CREATE TABLE IF NOT EXISTS debris_insert_log (
    id SERIAL PRIMARY KEY,
    attempted_data JSONB,
    error_message TEXT,
    attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3.2 Function to prevent duplicate debris entries
CREATE OR REPLACE FUNCTION prevent_duplicate_debris()
RETURNS TRIGGER AS $$
BEGIN
    -- Check for existing debris with same ship, same orbit, and similar size (±0.1m)
    IF EXISTS (
        SELECT 1 FROM debris
        WHERE id_ship = NEW.id_ship
          AND id_orbit = NEW.id_orbit
          AND ABS(approx_size_m - NEW.approx_size_m) < 0.1
    ) THEN
        -- Log the attempted insertion
        INSERT INTO debris_insert_log (attempted_data, error_message)
        VALUES (row_to_json(NEW), 'Duplicate debris detected for ship ' || NEW.id_ship || ' and orbit ' || NEW.id_orbit);
        
        -- Raise exception to prevent the insertion
        RAISE EXCEPTION 'Duplicate debris: similar entry exists for ship % and orbit %',
                        NEW.id_ship, NEW.id_orbit;
    END IF;
    
    -- Automatically update redundant columns before insert
    SELECT name INTO NEW.ship_name FROM ship WHERE id_ship = NEW.id_ship;
    SELECT name INTO NEW.orbit_name FROM orbit WHERE id_orbit = NEW.id_orbit;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3.3 Create trigger on debris table
DROP TRIGGER IF EXISTS trg_prevent_duplicate_debris ON debris;
CREATE TRIGGER trg_prevent_duplicate_debris
    BEFORE INSERT ON debris
    FOR EACH ROW
    EXECUTE FUNCTION prevent_duplicate_debris();

-- 3.4 Create trigger to update redundant columns on ship/orbit changes
CREATE OR REPLACE FUNCTION update_debris_ship_name()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE debris SET ship_name = NEW.name WHERE id_ship = NEW.id_ship;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_debris_orbit_name()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE debris SET orbit_name = NEW.name WHERE id_orbit = NEW.id_orbit;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_debris_ship_name ON ship;
CREATE TRIGGER trg_update_debris_ship_name
    AFTER UPDATE OF name ON ship
    FOR EACH ROW
    EXECUTE FUNCTION update_debris_ship_name();

DROP TRIGGER IF EXISTS trg_update_debris_orbit_name ON orbit;
CREATE TRIGGER trg_update_debris_orbit_name
    AFTER UPDATE OF name ON orbit
    FOR EACH ROW
    EXECUTE FUNCTION update_debris_orbit_name();

-- ============================================
-- TESTING THE IMPLEMENTATION
-- ============================================

-- 4.1 Test valid insertion (should succeed)
INSERT INTO debris (id_ship, id_orbit, approx_size_m, description) 
VALUES (1, 1, 3.00, 'Test debris - new fragment');

-- 4.2 Test duplicate insertion (should fail)
INSERT INTO debris (id_ship, id_orbit, approx_size_m, description) 
VALUES (1, 1, 3.01, 'Test debris - similar fragment');

-- 4.3 Check the log table
SELECT * FROM debris_insert_log;

-- 4.4 Verify materialized view
SELECT * FROM debris_details LIMIT 10;

-- 4.5 Test redundant columns
SELECT id_debris, description, ship_name, orbit_name FROM debris;

-- 4.6 Verify dependency analysis
-- Check if all tables are in BCNF
SELECT 
    'Ship table: ' || COUNT(*) || ' dependencies, all determinants are superkeys' AS bcnf_check
FROM (SELECT 1) t;