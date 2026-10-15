-- =====================================================================
--  Configuración inicial: refleja la MAQUETA FÍSICA.
--  (En la simulación de Wokwi la bomba y el motor se representan con LEDs;
--   ver docs/persistencia.md → "Maqueta física vs. simulación".)
--
--  El firmware mide el nivel en una escala 0–9 (dígito del display).
--  Acá se expresa en % → nivel_% = dígito × 100 / 9
--     dígito 1 ≈ 11 %   dígito 2 ≈ 22 %   dígito 8 ≈ 89 %
-- =====================================================================
PRAGMA foreign_keys = ON;

BEGIN;

-- La maqueta representa, a escala, el tanque de reserva de agua de la comunidad.
-- 100.000 L es una capacidad de referencia para un pueblo chico (no es un dato oficial).
INSERT INTO nodes (node_id, name, location, tank_capacity_l, heartbeat_timeout_s) VALUES
    ('water_node_01', 'Tanque de reserva comunitario', 'Caviahue–Copahue (maqueta a escala)', 100000, 30);

-- Sensores ------------------------------------------------------------
INSERT INTO sensors (sensor_id, node_id, code, description, hardware, unit, min_value, max_value, gpio, is_simulated) VALUES
    (1, 'water_node_01', 'water_level', 'Nivel de agua del tanque de reserva',
        'Sensor de nivel de agua resistivo', '%', 0, 100, '34', 0);

-- Actuadores ----------------------------------------------------------
INSERT INTO actuators (actuator_id, node_id, code, kind, description, hardware, gpio, is_simulated) VALUES
    (1, 'water_node_01', 'pump',          'pump',
        'Bomba de llenado del tanque',
        'Bomba de agua', '26', 0),
    (2, 'water_node_01', 'inlet_valve',   'valve',
        'Válvula de ingreso (0° cerrada / 90° abierta)',
        'Servomotor', '4', 0),
    (3, 'water_node_01', 'motor',         'motor',
        'Motor que se activa con nivel crítico (≤ 15 %), junto con el buzzer',
        'Motor', '27', 0),
    (4, 'water_node_01', 'buzzer',        'buzzer',
        'Alarma sonora de nivel crítico (~1 kHz)',
        'Buzzer', '25', 0),
    (5, 'water_node_01', 'level_display', 'display',
        'Indicador local del nivel (0–9)',
        'Display 7 segmentos, cátodo común', '13,14,18,19,21,22,23', 0);

-- Umbrales de alerta (nivel de reserva, en %) --------------------------
INSERT INTO alert_thresholds (sensor_id, alert_level, comparison, limit_value, hysteresis) VALUES
    (1, 'low',      '<=', 65, 3),
    (1, 'medium',   '<=', 45, 3),
    (1, 'high',     '<=', 25, 3),
    (1, 'critical', '<=', 15, 3);

COMMIT;
