const { SerialPort } = require('serialport');
const { ReadlineParser } = require('@serialport/parser-readline');
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: 'postgresql://neondb_owner:npg_DPU58KcZzqHd@ep-autumn-salad-b6kfp0s6-pooler.c-2.sa-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require',
  ssl: { rejectUnauthorized: false }
});

const puertoSerial = new SerialPort({ path: '/dev/ttyUSB0', baudRate: 115200 });
const parser = puertoSerial.pipe(new ReadlineParser({ delimiter: '\r\n' }));

console.log('Escuchando el puerto USB... Esquema Relacional con number_node (DEFAULT 1).');

parser.on('data', async (linea) => {
  const lineaLimpiada = linea.trim();

  if (!lineaLimpiada.startsWith('{') || !lineaLimpiada.endsWith('}')) {
    return; 
  }

  try {
    const registro = JSON.parse(lineaLimpiada);
    
    if (registro.data && registro.data.water_level !== undefined) {
      const waterLevel = registro.data.water_level;
      const statusNode = registro.status || 'active';
      const alertLevelName = registro.alert_level || 'normal';
      const timestamp = registro.timestamp || new Date().toISOString();

      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // 1. Buscamos si ya existe el recipiente para el nodo 1 (number_node = 1)
        let recipienteRes = await client.query('SELECT node_id FROM recipiente WHERE number_node = 1');
        let nodeId;

        if (recipienteRes.rows.length > 0) {
          // Si ya existe, actualizamos water_level y status
          nodeId = recipienteRes.rows[0].node_id;
          await client.query(
            'UPDATE recipiente SET water_level = $1, status = $2 WHERE node_id = $3',
            [waterLevel, statusNode, nodeId]
          );
        } else {
          // Si no existe, insertamos dejando que node_id se genere solo y number_node use su DEFAULT (1)
          const insertRecipiente = await client.query(
            'INSERT INTO recipiente (water_level, status) VALUES ($1, $2) RETURNING node_id',
            [waterLevel, statusNode]
          );
          nodeId = insertRecipiente.rows[0].node_id;
        }

        // 2. Buscamos o creamos la alerta para obtener su id_alert_level (entero)
        let alertRes = await client.query('SELECT id_alert_level FROM alerta WHERE name_alert = $1', [alertLevelName]);
        let idAlertLevel;
        
        if (alertRes.rows.length > 0) {
          idAlertLevel = alertRes.rows[0].id_alert_level;
        } else {
          const insertAlert = await client.query(
            'INSERT INTO alerta (name_alert) VALUES ($1) RETURNING id_alert_level', 
            [alertLevelName]
          );
          idAlertLevel = insertAlert.rows[0].id_alert_level;
        }

        // 3. Insertamos el evento relacionando el node_id e id_alert_level
        const queryEvento = `
          INSERT INTO evento (id_alert_level, timestamp, node_id) 
          VALUES ($1, $2, $3)
          RETURNING record_id;
        `;
        const eventoRes = await client.query(queryEvento, [idAlertLevel, timestamp, nodeId]);
        const recordId = eventoRes.rows[0].record_id;

        await client.query('COMMIT');
        console.log(`[BDD OK] Evento #${recordId} | Recipiente PK (node_id): ${nodeId} (Nodo #1) | Agua: ${waterLevel}% | Alerta ID: ${idAlertLevel} (${alertLevelName})`);
      } catch (errTx) {
        await client.query('ROLLBACK');
        console.error("-> [ERROR EN TRANSACCIÓN BDD]:", errTx.message);
      } finally {
        client.release();
      }
    }
  } catch (err) {
    console.error("-> [ERROR DE PARSEO]", err.message);
  }
});
