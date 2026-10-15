-- =====================================================================
--  Navathon III · Grupo 4 · Administración inteligente de agua
--  Esquema de persistencia — SQLite ≥ 3.38
--  Compatible con el "Contrato de normalización e intercambio de datos"
--  del Grupo 6, versión 1.0.0.
--
--  Convenciones:
--    * Fechas: TEXT ISO-8601 en UTC con milisegundos  →  2026-10-15T13:30:00.000Z
--      (formato fijo ⇒ el orden alfabético coincide con el cronológico).
--      La API las expone en UTC con segundos (2026-10-15T13:30:00Z), como pide el contrato.
--    * Booleanos: INTEGER 0/1.
--    * Unidades (catálogo del contrato): nivel en %, volumen en L.
--    * Todo lo que se comparte con otros grupos es un REGISTRO (tabla records)
--      con un record_id único (UUID). Su detalle va en readings, node_states o events.
--    * El historial es de solo inserción: no se modifica ni se borra.
--
--  IMPORTANTE: SQLite no aplica claves foráneas salvo que cada conexión
--  ejecute  PRAGMA foreign_keys = ON;
-- =====================================================================

PRAGMA foreign_keys = ON;

BEGIN;

-- ---------------------------------------------------------------------
-- 1. CATÁLOGO: niveles de alerta (escala común del contrato)
-- ---------------------------------------------------------------------
CREATE TABLE alert_levels (
    code        TEXT    PRIMARY KEY
                CHECK (code IN ('normal', 'low', 'medium', 'high', 'critical')),
    severity    INTEGER NOT NULL UNIQUE CHECK (severity BETWEEN 0 AND 4),
    name_es     TEXT    NOT NULL,
    description TEXT    NOT NULL
);

INSERT INTO alert_levels (code, severity, name_es, description) VALUES
    ('normal',   0, 'Normal',  'No se detecta riesgo'),
    ('low',      1, 'Bajo',    'Condición que requiere observación'),
    ('medium',   2, 'Medio',   'Situación de riesgo moderado'),
    ('high',     3, 'Alto',    'Requiere atención prioritaria'),
    ('critical', 4, 'Crítico', 'Requiere acción inmediata');

-- ---------------------------------------------------------------------
-- 2. CONFIGURACIÓN: cómo es el sistema físico
-- ---------------------------------------------------------------------
CREATE TABLE nodes (
    node_id             TEXT    PRIMARY KEY
                        CHECK (node_id GLOB 'water_node_[0-9][0-9]'),
    group_number        INTEGER NOT NULL DEFAULT 4 CHECK (group_number = 4),
    subsystem           TEXT    NOT NULL DEFAULT 'Administración inteligente de agua',
    name                TEXT    NOT NULL,
    location            TEXT,
    -- Capacidad que representa el 100 % (el contrato exige indicarla junto al porcentaje).
    tank_capacity_l     REAL    NOT NULL CHECK (tank_capacity_l > 0),
    -- Sin datos durante este lapso ⇒ el nodo se informa como 'offline' en la web propia.
    heartbeat_timeout_s INTEGER NOT NULL DEFAULT 30 CHECK (heartbeat_timeout_s > 0),
    created_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- Sensores: lo que el ESP32 LEE.
CREATE TABLE sensors (
    sensor_id    INTEGER PRIMARY KEY,
    node_id      TEXT    NOT NULL REFERENCES nodes (node_id)
                         ON UPDATE CASCADE ON DELETE RESTRICT,
    code         TEXT    NOT NULL,                  -- nombre de variable del contrato: 'water_level'
    description  TEXT    NOT NULL,                  -- qué representa en el sistema de agua
    hardware     TEXT    NOT NULL,                  -- componente físico instalado
    unit         TEXT    NOT NULL,                  -- unidad del contrato: '%', 'L/min', 'degC'
    min_value    REAL    NOT NULL,
    max_value    REAL    NOT NULL,
    gpio         TEXT,                              -- pin del ESP32
    -- 1 = el componente reemplaza al real (p. ej. un potenciómetro en lugar de un sensor de nivel)
    is_simulated INTEGER NOT NULL CHECK (is_simulated IN (0, 1)),
    UNIQUE (node_id, code),
    CHECK (min_value < max_value)
);

-- Actuadores: lo que el ESP32 MUEVE o ENCIENDE.
CREATE TABLE actuators (
    actuator_id  INTEGER PRIMARY KEY,
    node_id      TEXT    NOT NULL REFERENCES nodes (node_id)
                         ON UPDATE CASCADE ON DELETE RESTRICT,
    code         TEXT    NOT NULL,                  -- identificador interno: 'pump'
    kind         TEXT    NOT NULL
                 CHECK (kind IN ('pump', 'valve', 'motor', 'buzzer', 'display', 'indicator')),
    description  TEXT    NOT NULL,
    hardware     TEXT    NOT NULL,
    gpio         TEXT,                              -- pin(es) de control del ESP32
    is_simulated INTEGER NOT NULL CHECK (is_simulated IN (0, 1)),
    UNIQUE (node_id, code)
);

-- Umbrales de alerta, editables desde la web ("configuración de parámetros").
-- Se cumple si  valor <comparison> limit_value. Si se cumplen varios, rige el más severo.
CREATE TABLE alert_thresholds (
    threshold_id INTEGER PRIMARY KEY,
    sensor_id    INTEGER NOT NULL REFERENCES sensors (sensor_id) ON DELETE RESTRICT,
    alert_level  TEXT    NOT NULL REFERENCES alert_levels (code)
                         CHECK (alert_level <> 'normal'),   -- 'normal' = no se cumple ninguno
    comparison   TEXT    NOT NULL CHECK (comparison IN ('<=', '>=')),
    limit_value  REAL    NOT NULL,
    -- Margen para salir del nivel; evita que la alerta oscile cuando el valor ronda el límite.
    hysteresis   REAL    NOT NULL DEFAULT 0 CHECK (hysteresis >= 0),
    updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_by   TEXT    NOT NULL DEFAULT 'system',
    UNIQUE (sensor_id, alert_level)
);

-- ---------------------------------------------------------------------
-- 3. REGISTROS DEL CONTRATO (solo inserción)
--    records guarda el "sobre" común de cada registro que se comparte;
--    el contenido específico va en una de sus tablas hijas:
--      record_type = 'reading' → readings      (una fila por variable medida)
--      record_type = 'state'   → node_states   (foto del estado del nodo)
--      record_type = 'event'   → events
-- ---------------------------------------------------------------------
CREATE TABLE records (
    -- Orden de inserción estable: es el cursor de GET /api/v1/records.
    seq                  INTEGER PRIMARY KEY AUTOINCREMENT,
    -- Identificador único del registro (UUID v4), generado una sola vez y
    -- conservado en reintentos: así el Grupo 6 detecta duplicados.
    record_id            TEXT    NOT NULL UNIQUE DEFAULT (
                             lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
                             substr(lower(hex(randomblob(2))), 2) || '-' ||
                             substr('89ab', 1 + (abs(random()) % 4), 1) ||
                             substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))))
                         CHECK (record_id GLOB '[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'),
    schema_version       TEXT    NOT NULL DEFAULT '1.0.0',
    record_type          TEXT    NOT NULL CHECK (record_type IN ('reading', 'state', 'event')),
    node_id              TEXT    NOT NULL REFERENCES nodes (node_id)
                                 ON UPDATE CASCADE ON DELETE RESTRICT,
    -- Momento de la medición o del evento (no el de la consulta).
    ts                   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                         CHECK (ts GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    status               TEXT    NOT NULL CHECK (status IN ('active', 'offline', 'error')),
    alert_level          TEXT    NOT NULL REFERENCES alert_levels (code),
    -- Metadatos obligatorios del contrato.
    alert_evaluated      INTEGER NOT NULL CHECK (alert_evaluated IN (0, 1)),
    environment          TEXT    NOT NULL CHECK (environment IN ('test', 'operational')),
    source_type          TEXT    NOT NULL CHECK (source_type IN ('real', 'simulated', 'mixed')),
    clock_synced         INTEGER NOT NULL DEFAULT 1 CHECK (clock_synced IN (0, 1)),
    -- Correcciones: un registro nuevo que reemplaza a otro (el original no se toca).
    supersedes_record_id TEXT    REFERENCES records (record_id) ON DELETE RESTRICT,
    created_at           TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE INDEX idx_records_node_type_ts ON records (node_id, record_type, ts);

-- Mediciones: una fila por variable dentro de un registro 'reading'.
CREATE TABLE readings (
    reading_id   INTEGER PRIMARY KEY,
    record_seq   INTEGER NOT NULL REFERENCES records (seq) ON DELETE RESTRICT,
    sensor_id    INTEGER NOT NULL REFERENCES sensors (sensor_id) ON DELETE RESTRICT,
    value        REAL,                              -- en la unidad del sensor; NULL si falló
    raw_value    INTEGER,                           -- lectura cruda (ADC 0–4095), para diagnóstico
    quality      TEXT    NOT NULL
                 CHECK (quality IN ('valid', 'missing', 'invalid', 'uncalibrated')),
    is_simulated INTEGER NOT NULL CHECK (is_simulated IN (0, 1)),
    UNIQUE (record_seq, sensor_id),
    -- Contrato: una lectura fallida va como null (nunca 0, -999 ni "N/A").
    CHECK ((quality IN ('valid', 'uncalibrated')) = (value IS NOT NULL))
);
CREATE INDEX idx_readings_sensor ON readings (sensor_id, record_seq);

-- Estado del nodo: lo que devuelve GET /api/v1/status.
CREATE TABLE node_states (
    record_seq  INTEGER PRIMARY KEY REFERENCES records (seq) ON DELETE RESTRICT,
    water_level REAL    CHECK (water_level BETWEEN 0 AND 100),   -- NULL si no hay lectura válida
    pump_state  TEXT    NOT NULL CHECK (pump_state  IN ('on', 'off', 'unknown')),
    valve_state TEXT    NOT NULL CHECK (valve_state IN ('open', 'closed', 'unknown')),
    motor_state TEXT    NOT NULL CHECK (motor_state IN ('on', 'off', 'unknown'))
);

-- Eventos: cambios de alerta, arranques, fallas.
CREATE TABLE events (
    event_id             INTEGER PRIMARY KEY,
    record_seq           INTEGER NOT NULL UNIQUE REFERENCES records (seq) ON DELETE RESTRICT,
    event_code           TEXT    NOT NULL
                         CHECK (event_code IN ('node_start', 'alert_change', 'status_change',
                                               'sensor_fault', 'manual_command', 'config_change')),
    previous_alert_level TEXT    REFERENCES alert_levels (code),
    message              TEXT    NOT NULL,          -- texto legible: qué pasa y qué hacer
    reading_id           INTEGER REFERENCES readings (reading_id) ON DELETE RESTRICT,
    CHECK (event_code <> 'alert_change' OR previous_alert_level IS NOT NULL)
);

-- ---------------------------------------------------------------------
-- 4. ACCIONES SOBRE ACTUADORES (uso interno: justificar decisiones)
-- ---------------------------------------------------------------------
CREATE TABLE actuator_actions (
    action_id    INTEGER PRIMARY KEY,
    actuator_id  INTEGER NOT NULL REFERENCES actuators (actuator_id) ON DELETE RESTRICT,
    ts           TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                 CHECK (ts GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'),
    state        TEXT    NOT NULL CHECK (state IN ('on', 'off', 'set')),
    value        REAL,                              -- p. ej. ángulo del servo
    origin       TEXT    NOT NULL CHECK (origin IN ('auto', 'manual_web', 'remote_api')),
    rule_code    TEXT,                              -- regla del firmware: 'R01', 'R02', ...
    reason       TEXT    NOT NULL,                  -- explicación legible de la acción
    reading_id   INTEGER REFERENCES readings (reading_id) ON DELETE RESTRICT,
    requested_by TEXT,                              -- usuario web o grupo remoto
    -- Toda acción queda justificada: automática ⇒ regla + lectura que la causó;
    -- manual o remota ⇒ quién la pidió.
    CHECK (origin <> 'auto' OR (rule_code IS NOT NULL AND reading_id IS NOT NULL)),
    CHECK (origin =  'auto' OR requested_by IS NOT NULL),
    CHECK (state  <> 'set'  OR value IS NOT NULL)
);
CREATE INDEX idx_actions_actuator_ts ON actuator_actions (actuator_id, ts);

-- ---------------------------------------------------------------------
-- 5. TRIGGERS — solo integridad; la lógica de control vive en firmware/backend
-- ---------------------------------------------------------------------
-- 5.1 Cada tabla hija solo acepta registros de su tipo.
CREATE TRIGGER trg_readings_type BEFORE INSERT ON readings
WHEN (SELECT record_type FROM records WHERE seq = NEW.record_seq) IS NOT 'reading'
BEGIN SELECT RAISE(ABORT, 'readings solo admite registros de tipo reading'); END;

CREATE TRIGGER trg_states_type BEFORE INSERT ON node_states
WHEN (SELECT record_type FROM records WHERE seq = NEW.record_seq) IS NOT 'state'
BEGIN SELECT RAISE(ABORT, 'node_states solo admite registros de tipo state'); END;

CREATE TRIGGER trg_events_type BEFORE INSERT ON events
WHEN (SELECT record_type FROM records WHERE seq = NEW.record_seq) IS NOT 'event'
BEGIN SELECT RAISE(ABORT, 'events solo admite registros de tipo event'); END;

-- 5.2 Historial inmutable: un registro editable no sirve para justificar decisiones,
--     y el Grupo 6 necesita que el historial no cambie para recuperarlo tras un corte.
CREATE TRIGGER trg_records_no_update BEFORE UPDATE ON records
BEGIN SELECT RAISE(ABORT, 'records es de solo inserción'); END;
CREATE TRIGGER trg_records_no_delete BEFORE DELETE ON records
BEGIN SELECT RAISE(ABORT, 'records no admite borrado'); END;

CREATE TRIGGER trg_readings_no_update BEFORE UPDATE ON readings
BEGIN SELECT RAISE(ABORT, 'readings es de solo inserción'); END;
CREATE TRIGGER trg_readings_no_delete BEFORE DELETE ON readings
BEGIN SELECT RAISE(ABORT, 'readings no admite borrado'); END;

CREATE TRIGGER trg_states_no_update BEFORE UPDATE ON node_states
BEGIN SELECT RAISE(ABORT, 'node_states es de solo inserción'); END;
CREATE TRIGGER trg_states_no_delete BEFORE DELETE ON node_states
BEGIN SELECT RAISE(ABORT, 'node_states no admite borrado'); END;

CREATE TRIGGER trg_events_no_update BEFORE UPDATE ON events
BEGIN SELECT RAISE(ABORT, 'events es de solo inserción'); END;
CREATE TRIGGER trg_events_no_delete BEFORE DELETE ON events
BEGIN SELECT RAISE(ABORT, 'events no admite borrado'); END;

CREATE TRIGGER trg_actions_no_update BEFORE UPDATE ON actuator_actions
BEGIN SELECT RAISE(ABORT, 'actuator_actions es de solo inserción'); END;
CREATE TRIGGER trg_actions_no_delete BEFORE DELETE ON actuator_actions
BEGIN SELECT RAISE(ABORT, 'actuator_actions no admite borrado'); END;

-- 5.3 Mantiene updated_at al día cuando se edita un umbral desde la web.
CREATE TRIGGER trg_thresholds_touch AFTER UPDATE OF limit_value, hysteresis ON alert_thresholds
WHEN OLD.limit_value IS NOT NEW.limit_value OR OLD.hysteresis IS NOT NEW.hysteresis
BEGIN
    UPDATE alert_thresholds
       SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE threshold_id = NEW.threshold_id;
END;

-- ---------------------------------------------------------------------
-- 6. VISTAS — lo que consume la API
-- ---------------------------------------------------------------------

-- 6.1 Cada registro armado en el FORMATO DEL CONTRATO (JSON listo para enviar).
--     GET /api/v1/records  →  SELECT seq, payload FROM v_contract_records
--                             WHERE seq > :cursor ORDER BY seq LIMIT :limit;
CREATE VIEW v_contract_records AS
WITH reading_parts AS (
    SELECT r.record_seq,
           json_group_object(s.code, r.value)   AS data,
           json_group_object(s.code, s.unit)    AS units,
           json_group_object(s.code, r.quality) AS quality,
           json_group_object(s.code, CASE r.is_simulated WHEN 1 THEN 'simulated' ELSE 'real' END) AS sources,
           MAX(CASE WHEN s.code = 'water_level' THEN r.value   END) AS level,
           MAX(CASE WHEN s.code = 'water_level' THEN r.quality END) AS level_quality
    FROM readings r
    JOIN sensors s ON s.sensor_id = r.sensor_id
    GROUP BY r.record_seq
),
body AS (
    SELECT rec.seq,
           CASE rec.record_type
               WHEN 'reading' THEN
                   -- water_volume se deriva del nivel y la capacidad del tanque.
                   CASE WHEN rp.level_quality IS NULL THEN json(rp.data)
                        ELSE json_set(json(rp.data), '$.water_volume',
                                      ROUND(rp.level / 100.0 * n.tank_capacity_l, 1)) END
               WHEN 'state' THEN
                   json_object('water_level',  ns.water_level,
                               'water_volume', ROUND(ns.water_level / 100.0 * n.tank_capacity_l, 1),
                               'pump_state',   ns.pump_state,
                               'valve_state',  ns.valve_state,
                               'motor_state',  ns.motor_state)
               WHEN 'event' THEN
                   json_object('event_code',           ev.event_code,
                               'message',              ev.message,
                               'previous_alert_level', ev.previous_alert_level,
                               'related_record_ids',
                                   json(CASE WHEN rel.record_id IS NULL THEN '[]'
                                             ELSE json_array(rel.record_id) END))
           END AS data,
           CASE rec.record_type
               WHEN 'reading' THEN
                   CASE WHEN rp.level_quality IS NULL THEN json(rp.units)
                        ELSE json_set(json(rp.units), '$.water_volume', 'L') END
               WHEN 'state' THEN json_object('water_level', '%', 'water_volume', 'L')
           END AS units,
           CASE rec.record_type
               WHEN 'reading' THEN
                   CASE WHEN rp.level_quality IS NULL THEN json(rp.quality)
                        ELSE json_set(json(rp.quality), '$.water_volume', rp.level_quality) END
           END AS quality,
           CASE WHEN rec.record_type = 'reading' AND rec.source_type = 'mixed'
                THEN json(rp.sources) END AS sources
    FROM records rec
    JOIN nodes n               ON n.node_id = rec.node_id
    LEFT JOIN reading_parts rp ON rp.record_seq = rec.seq
    LEFT JOIN node_states ns   ON ns.record_seq = rec.seq
    LEFT JOIN events ev        ON ev.record_seq = rec.seq
    LEFT JOIN readings evr     ON evr.reading_id = ev.reading_id
    LEFT JOIN records rel      ON rel.seq = evr.record_seq
)
SELECT rec.seq,
       rec.record_id,
       rec.record_type,
       rec.node_id,
       rec.ts,
       rec.environment,
       json_object(
           'schema_version', rec.schema_version,
           'record_id',      rec.record_id,
           'record_type',    rec.record_type,
           'node_id',        rec.node_id,
           'group',          n.group_number,
           'subsystem',      n.subsystem,
           'timestamp',      strftime('%Y-%m-%dT%H:%M:%SZ', rec.ts),
           'status',         rec.status,
           'alert_level',    rec.alert_level,
           'data',           json(b.data),
           -- json_patch con valor null omite la clave: los metadatos opcionales
           -- solo aparecen cuando corresponden.
           'metadata', json_patch(
               json_object(
                   'environment',     rec.environment,
                   'source_type',     rec.source_type,
                   'alert_evaluated', json(CASE rec.alert_evaluated WHEN 1 THEN 'true' ELSE 'false' END),
                   'clock_synced',    json(CASE rec.clock_synced    WHEN 1 THEN 'true' ELSE 'false' END),
                   'extensions',      json_object('tank_capacity_l', n.tank_capacity_l)
               ),
               json_object(
                   'units',                json(b.units),
                   'quality',              json(b.quality),
                   'sources',              json(b.sources),
                   'supersedes_record_id', rec.supersedes_record_id
               )
           )
       ) AS payload
FROM records rec
JOIN nodes n ON n.node_id = rec.node_id
JOIN body b  ON b.seq = rec.seq;

-- 6.2 GET /api/v1/status: último registro de tipo 'state' de cada nodo.
CREATE VIEW v_api_status AS
SELECT node_id, record_id, ts, payload
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY ts DESC, seq DESC) AS rn
      FROM v_contract_records
      WHERE record_type = 'state')
WHERE rn = 1;

-- 6.3 Estado actual para la web propia. 'offline' se calcula solo: un nodo
--     caído no puede avisar que se cayó, así que se deduce por la falta de datos.
CREATE VIEW v_node_state AS
WITH last_record AS (
    SELECT *
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY ts DESC, seq DESC) AS rn
          FROM records)
    WHERE rn = 1
),
last_state AS (
    SELECT rec.node_id, ns.*
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY ts DESC, seq DESC) AS rn
          FROM records WHERE record_type = 'state') rec
    JOIN node_states ns ON ns.record_seq = rec.seq
    WHERE rec.rn = 1
)
SELECT n.node_id,
       lr.ts AS last_seen,
       CASE
           WHEN lr.ts IS NULL
             OR lr.ts < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-' || n.heartbeat_timeout_s || ' seconds')
                THEN 'offline'
           ELSE lr.status
       END                                                   AS status,
       COALESCE(lr.alert_level, 'normal')                    AS alert_level,
       lr.alert_evaluated,
       lr.environment,
       lr.source_type,
       ls.water_level                                        AS level_pct,
       ROUND(ls.water_level / 100.0 * n.tank_capacity_l, 1)  AS volume_l,
       ls.pump_state,
       ls.valve_state,
       ls.motor_state
FROM nodes n
LEFT JOIN last_record lr ON lr.node_id = n.node_id
LEFT JOIN last_state  ls ON ls.node_id = n.node_id;

-- 6.4 Trazabilidad: cada acción con su motivo y la lectura que la causó.
CREATE VIEW v_decision_trace AS
SELECT aa.action_id, aa.ts, a.code AS actuator, aa.state, aa.value, aa.origin,
       aa.rule_code, aa.reason, r.value AS reading_value, s.unit,
       rec.record_id AS reading_record_id, rec.environment, aa.requested_by
FROM actuator_actions aa
JOIN actuators a      ON a.actuator_id = aa.actuator_id
LEFT JOIN readings r  ON r.reading_id = aa.reading_id
LEFT JOIN sensors s   ON s.sensor_id = r.sensor_id
LEFT JOIN records rec ON rec.seq = r.record_seq;

COMMIT;
