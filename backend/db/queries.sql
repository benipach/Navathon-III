-- =====================================================================
--  Consultas de referencia
--  · API del contrato con el Grupo 6 (rutas /api/v1/...)
--  · Una consulta por cada exigencia de la consigna (requisito 2.4)
--  Los parámetros con ":" (:cursor, :limit, :value) los completa el backend.
-- =====================================================================

-- [API · GET /api/v1/status] Último registro de estado del nodo.
SELECT payload FROM v_api_status WHERE node_id = 'water_node_01';

-- [API · GET /api/v1/records?cursor=...&limit=...] Historial paginado.
-- El cursor es el último seq entregado (0 en la primera página). Se pide
-- limit + 1 filas: si llegan más de limit, has_more = true.
SELECT seq, payload
FROM v_contract_records
WHERE seq > :cursor
ORDER BY seq
LIMIT :limit + 1;

-- [Recuperar información histórica] Nivel del tanque en un rango de tiempo.
SELECT rec.ts, r.value AS level_pct, r.quality, rec.environment
FROM readings r
JOIN records rec ON rec.seq = r.record_seq
WHERE r.sensor_id = 1
  AND rec.ts BETWEEN '2026-10-15T13:00:00.000Z' AND '2026-10-15T14:00:00.000Z'
ORDER BY rec.ts;

-- [Analizar cambios] Promedio, mínimo y máximo por hora.
SELECT substr(rec.ts, 1, 13) || ':00Z' AS hour,
       ROUND(AVG(r.value), 1) AS avg_pct, MIN(r.value) AS min_pct, MAX(r.value) AS max_pct,
       COUNT(*) AS samples
FROM readings r
JOIN records rec ON rec.seq = r.record_seq
WHERE r.sensor_id = 1 AND r.quality = 'valid'
GROUP BY hour
ORDER BY hour;

-- [Consultar eventos] Eventos de nivel alto o crítico.
SELECT rec.ts, rec.alert_level, al.name_es, e.message
FROM events e
JOIN records rec     ON rec.seq = e.record_seq
JOIN alert_levels al ON al.code = rec.alert_level
WHERE al.severity >= 3
ORDER BY rec.ts DESC;

-- [Justificar decisiones] Por qué se movió cada actuador.
SELECT ts, actuator, state, value, origin, rule_code, reason, reading_value, requested_by
FROM v_decision_trace
ORDER BY ts, action_id;

-- [Justificar decisiones] Cuánto tiempo estuvo encendida la bomba en cada ciclo.
SELECT on_ts, off_ts,
       ROUND((julianday(off_ts) - julianday(on_ts)) * 1440, 1) AS minutes_on
FROM (SELECT ts AS on_ts, state,
             LEAD(ts) OVER (ORDER BY ts, action_id) AS off_ts
      FROM actuator_actions WHERE actuator_id = 1)
WHERE state = 'on';

-- [Web propia] Estado actual (incluye 'offline' si el nodo dejó de enviar datos).
SELECT * FROM v_node_state;

-- [Configuración] Umbrales vigentes (pantalla de parámetros de la web).
SELECT t.alert_level, al.name_es, t.comparison, t.limit_value, t.hysteresis, t.updated_by, t.updated_at
FROM alert_thresholds t
JOIN alert_levels al ON al.code = t.alert_level
WHERE t.sensor_id = 1
ORDER BY al.severity;

-- [Nivel de alerta] Qué nivel corresponde a un valor (sin histéresis).
SELECT COALESCE(
         (SELECT t.alert_level
          FROM alert_thresholds t JOIN alert_levels al ON al.code = t.alert_level
          WHERE t.sensor_id = 1
            AND ((t.comparison = '<=' AND :value <= t.limit_value)
              OR (t.comparison = '>=' AND :value >= t.limit_value))
          ORDER BY al.severity DESC
          LIMIT 1),
         'normal') AS alert_level;
