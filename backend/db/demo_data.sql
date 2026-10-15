-- =====================================================================
--  Datos de demostración (SIMULADOS): el tanque se vacía hasta nivel
--  crítico y la bomba lo vuelve a llenar. Sirve para probar consultas,
--  la API y el dashboard sin la maqueta conectada.
--  Todos los registros llevan environment = 'test' y source_type = 'simulated'.
--
--  Reglas del firmware (sketch.ino):
--    R01  nivel ≤ 25 %  → bomba ON + válvula 90°
--    R02  nivel ≥ 85 %  → bomba OFF + válvula 0°
--    R03  nivel ≤ 15 %  → motor ON + buzzer ON
--    R04  nivel > 15 %  → motor OFF + buzzer OFF
--
--  Patrón que usará el backend por cada lectura del ESP32:
--    1 registro 'reading' (+ fila en readings)
--    1 registro 'event'   (+ fila en events)   solo si cambió el nivel de alerta
--    acciones en actuator_actions               solo si se movió un actuador
--    1 registro 'state'   (+ fila en node_states)
-- =====================================================================
PRAGMA foreign_keys = ON;

BEGIN;

-- Sobres comunes (records). seq explícito para poder referenciarlos abajo.
INSERT INTO records (seq, record_type, node_id, ts, status, alert_level, alert_evaluated, environment, source_type) VALUES
    ( 1, 'event',   'water_node_01', '2026-10-15T13:00:00.000Z', 'active', 'normal',   0, 'test', 'simulated'),
    ( 2, 'reading', 'water_node_01', '2026-10-15T13:00:00.000Z', 'active', 'normal',   1, 'test', 'simulated'),
    ( 3, 'state',   'water_node_01', '2026-10-15T13:00:00.000Z', 'active', 'normal',   1, 'test', 'simulated'),
    ( 4, 'reading', 'water_node_01', '2026-10-15T13:05:00.000Z', 'active', 'low',      1, 'test', 'simulated'),
    ( 5, 'event',   'water_node_01', '2026-10-15T13:05:00.000Z', 'active', 'low',      1, 'test', 'simulated'),
    ( 6, 'state',   'water_node_01', '2026-10-15T13:05:00.000Z', 'active', 'low',      1, 'test', 'simulated'),
    ( 7, 'reading', 'water_node_01', '2026-10-15T13:10:00.000Z', 'active', 'medium',   1, 'test', 'simulated'),
    ( 8, 'event',   'water_node_01', '2026-10-15T13:10:00.000Z', 'active', 'medium',   1, 'test', 'simulated'),
    ( 9, 'state',   'water_node_01', '2026-10-15T13:10:00.000Z', 'active', 'medium',   1, 'test', 'simulated'),
    (10, 'reading', 'water_node_01', '2026-10-15T13:15:00.000Z', 'active', 'high',     1, 'test', 'simulated'),
    (11, 'event',   'water_node_01', '2026-10-15T13:15:00.000Z', 'active', 'high',     1, 'test', 'simulated'),
    (12, 'state',   'water_node_01', '2026-10-15T13:15:00.000Z', 'active', 'high',     1, 'test', 'simulated'),
    (13, 'reading', 'water_node_01', '2026-10-15T13:20:00.000Z', 'active', 'critical', 1, 'test', 'simulated'),
    (14, 'event',   'water_node_01', '2026-10-15T13:20:00.000Z', 'active', 'critical', 1, 'test', 'simulated'),
    (15, 'state',   'water_node_01', '2026-10-15T13:20:00.000Z', 'active', 'critical', 1, 'test', 'simulated'),
    (16, 'reading', 'water_node_01', '2026-10-15T13:25:00.000Z', 'active', 'medium',   1, 'test', 'simulated'),
    (17, 'event',   'water_node_01', '2026-10-15T13:25:00.000Z', 'active', 'medium',   1, 'test', 'simulated'),
    (18, 'state',   'water_node_01', '2026-10-15T13:25:00.000Z', 'active', 'medium',   1, 'test', 'simulated'),
    (19, 'reading', 'water_node_01', '2026-10-15T13:30:00.000Z', 'active', 'normal',   1, 'test', 'simulated'),
    (20, 'event',   'water_node_01', '2026-10-15T13:30:00.000Z', 'active', 'normal',   1, 'test', 'simulated'),
    (21, 'state',   'water_node_01', '2026-10-15T13:30:00.000Z', 'active', 'normal',   1, 'test', 'simulated'),
    -- Comando manual desde la web (ejemplo de "control de operación").
    (22, 'state',   'water_node_01', '2026-10-15T13:40:00.000Z', 'active', 'normal',   1, 'test', 'simulated'),
    (23, 'state',   'water_node_01', '2026-10-15T13:41:00.000Z', 'active', 'normal',   1, 'test', 'simulated');

INSERT INTO readings (reading_id, record_seq, sensor_id, value, raw_value, quality, is_simulated) VALUES
    (1,  2, 1, 77.8, 3185, 'valid', 1),
    (2,  4, 1, 55.6, 2275, 'valid', 1),
    (3,  7, 1, 44.4, 1820, 'valid', 1),
    (4, 10, 1, 22.2,  910, 'valid', 1),
    (5, 13, 1, 11.1,  455, 'valid', 1),
    (6, 16, 1, 33.3, 1365, 'valid', 1),
    (7, 19, 1, 88.9, 3640, 'valid', 1);

INSERT INTO events (record_seq, event_code, previous_alert_level, message, reading_id) VALUES
    ( 1, 'node_start',   NULL,       'Nodo iniciado.', NULL),
    ( 5, 'alert_change', 'normal',   'BAJO · Reserva al 56 %. Monitorear consumo.', 2),
    ( 8, 'alert_change', 'low',      'MEDIO · Reserva al 44 %. Reducir consumos no esenciales.', 3),
    (11, 'alert_change', 'medium',   'ALTO · Reserva al 22 %. Bomba de llenado activada.', 4),
    (14, 'alert_change', 'high',     'CRÍTICO · Reserva al 11 %. Activar distribución prioritaria.', 5),
    (17, 'alert_change', 'critical', 'MEDIO · Reserva al 33 %. Recuperándose; bomba en marcha.', 6),
    (20, 'alert_change', 'medium',   'NORMAL · Reserva al 89 %. Bomba detenida.', 7);

INSERT INTO node_states (record_seq, water_level, pump_state, valve_state, motor_state) VALUES
    ( 3, 77.8, 'off', 'closed', 'off'),
    ( 6, 55.6, 'off', 'closed', 'off'),
    ( 9, 44.4, 'off', 'closed', 'off'),
    (12, 22.2, 'on',  'open',   'off'),
    (15, 11.1, 'on',  'open',   'on'),
    (18, 33.3, 'on',  'open',   'off'),
    (21, 88.9, 'off', 'closed', 'off'),
    (22, 88.9, 'on',  'closed', 'off'),
    (23, 88.9, 'off', 'closed', 'off');

INSERT INTO actuator_actions (actuator_id, ts, state, value, origin, rule_code, reason, reading_id) VALUES
    (1, '2026-10-15T13:15:00.000Z', 'on',  NULL, 'auto', 'R01', 'Nivel ≤ 25 %: llenar tanque',        4),
    (2, '2026-10-15T13:15:00.000Z', 'set', 90,   'auto', 'R01', 'Nivel ≤ 25 %: abrir ingreso',        4),
    (3, '2026-10-15T13:20:00.000Z', 'on',  NULL, 'auto', 'R03', 'Nivel ≤ 15 %: nivel crítico',        5),
    (4, '2026-10-15T13:20:00.000Z', 'on',  NULL, 'auto', 'R03', 'Nivel ≤ 15 %: alarma sonora',        5),
    (3, '2026-10-15T13:25:00.000Z', 'off', NULL, 'auto', 'R04', 'Nivel > 15 %: fin de nivel crítico', 6),
    (4, '2026-10-15T13:25:00.000Z', 'off', NULL, 'auto', 'R04', 'Nivel > 15 %: fin de alarma',        6),
    (1, '2026-10-15T13:30:00.000Z', 'off', NULL, 'auto', 'R02', 'Nivel ≥ 85 %: tanque lleno',         7),
    (2, '2026-10-15T13:30:00.000Z', 'set', 0,    'auto', 'R02', 'Nivel ≥ 85 %: cerrar ingreso',       7);

INSERT INTO actuator_actions (actuator_id, ts, state, origin, reason, requested_by) VALUES
    (1, '2026-10-15T13:40:00.000Z', 'on',  'manual_web', 'Prueba manual de la bomba', 'operador_web'),
    (1, '2026-10-15T13:41:00.000Z', 'off', 'manual_web', 'Fin de prueba manual',      'operador_web');

COMMIT;
