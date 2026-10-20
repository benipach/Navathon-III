const ALTURA_TANQUE_M = 5;      // altura total del tanque en metros
const MAX_LOGS = 50;             // máximo de registros visibles

// Configuración de la API y WebSockets
const API_HOST = window.location.host || 'localhost:8000';
const HTTP_PROTOCOL = window.location.protocol === 'https:' ? 'https:' : 'http:';
const WS_PROTOCOL = window.location.protocol === 'https:' ? 'wss:' : 'ws:';

const ctx = document.getElementById('graficoNivel').getContext('2d');
const graficoNivel = new Chart(ctx, {
  type: 'line',
  data: {
    labels: [],
    datasets: [{
      label: 'Nivel (%)',
      data: [],
      borderColor: '#ff4d1a',
      backgroundColor: 'rgba(250, 31, 58, 0.14)',
      borderWidth: 2,
      fill: true,
      tension: 0.4
    }]
  },
  options: {
    responsive: true,
    maintainAspectRatio: false,
    plugins: { legend: { display: false } },
    scales: {
      y: { min: 0, max: 100, grid: { color: '#3d1a24' }, ticks: { color: '#b9a0a6' } },
      x: { grid: { display: false }, ticks: { color: '#b9a0a6' } }
    }
  }
});

let estadoValvula = "ABIERTA";
let nivelActual = 0.0;    // Arranca en 0 esperando datos reales
let caudalActual = 0.0;
let estadoPrevio = null;

// Estados del tanque: texto, color del texto y estilo de la etiqueta
function calcularEstado(nivel) {
  if (nivel >= 90) return { texto: "Nivel muy alto", badge: "badge-alert", color: "text-alert", critico: true };
  if (nivel >= 60) return { texto: "Nivel óptimo",   badge: "badge-optimo", color: "text-water", critico: false };
  if (nivel >= 30) return { texto: "Nivel medio",    badge: "badge-warn",   color: "text-warn",  critico: false };
  if (nivel >= 15) return { texto: "Nivel bajo",     badge: "badge-warn",   color: "text-warn",  critico: false };
  return { texto: "Nivel crítico", badge: "badge-alert", color: "text-alert", critico: true };
}

function agregarLog(mensaje, tipo = "sys") {
  const logContainer = document.getElementById('log-container');
  const hora = new Date().toLocaleTimeString();
  const nuevoLog = document.createElement('div');
  nuevoLog.className = `log-${tipo}`;
  nuevoLog.innerHTML = `<span class="log-time">[${hora}]</span> ${mensaje}`;
  logContainer.prepend(nuevoLog);
  while (logContainer.children.length > MAX_LOGS) {
    logContainer.removeChild(logContainer.lastChild);
  }
}

// Pinta en pantalla los valores actuales
function refrescarPantalla(caudalParam = null) {
  if (caudalParam !== null) caudalActual = caudalParam;
  
  const estado = calcularEstado(nivelActual);
  const abierta = estadoValvula === "ABIERTA";

  const kpiNivel = document.getElementById('kpi-nivel');
  kpiNivel.innerText = nivelActual.toFixed(1) + '%';
  kpiNivel.className = `kpi-value ${estado.color}`;

  // Cálculo corregido de la altura en metros respecto al total del tanque
  const alturaMetros = (nivelActual / 100) * ALTURA_TANQUE_M;
  document.getElementById('kpi-altura').innerText = `Tanque Principal (${alturaMetros.toFixed(2).replace('.', ',')} m)`;

  document.getElementById('kpi-caudal').innerText = caudalActual.toFixed(1) + ' L/s';
  document.getElementById('kpi-caudal-sub').innerText = abierta ? 'Red de distribución activa' : 'Distribución interrumpida';

  const kpiValvula = document.getElementById('kpi-valvula');
  kpiValvula.innerText = estadoValvula;
  kpiValvula.className = abierta ? "kpi-value text-ok" : "kpi-value text-alert";
  document.getElementById('kpi-valvula-sub').innerText =
    abierta ? 'Control remoto operativo' : 'Salida bloqueada por control remoto';

  const etiqueta = document.getElementById('tank-status-label');
  etiqueta.innerText = estado.texto;
  etiqueta.className = `badge ${estado.badge} mt-3`;

  document.getElementById('tank-water').style.height = nivelActual.toFixed(1) + '%';
}

// Función central para procesar cualquier nuevo dato real recibido
function procesarNuevoDato(nuevoNivel, nuevoCaudal = null) {
  nivelActual = Math.min(100, Math.max(0, Number(nuevoNivel)));
  if (nuevoCaudal !== null) caudalActual = Number(nuevoCaudal);

  refrescarPantalla();

  const horaActual = new Date().toLocaleTimeString();
  const estado = calcularEstado(nivelActual);
  
  if (estado.texto !== estadoPrevio) {
    agregarLog(`[TELEMETRÍA] ${estado.texto} (${nivelActual.toFixed(1)}%)`, estado.critico ? "alert" : "telemetry");
    estadoPrevio = estado.texto;
  } else {
    agregarLog(`[TELEMETRÍA] Nivel recibido: ${nivelActual.toFixed(1)}%`, "telemetry");
  }

  // Actualizar gráfica histórica
  if (graficoNivel.data.labels.length > 20) {
    graficoNivel.data.labels.shift();
    graficoNivel.data.datasets[0].data.shift();
  }
  graficoNivel.data.labels.push(horaActual);
  graficoNivel.data.datasets[0].data.push(Number(nivelActual.toFixed(1)));
  graficoNivel.update();
}

function controlarValvula(nuevoEstado) {
  if (nuevoEstado === estadoValvula) return;
  estadoValvula = nuevoEstado;
  caudalActual = (estadoValvula === "ABIERTA") ? 42.0 : 0.0;
  refrescarPantalla(); 
  agregarLog(`[ACTUADOR] Válvula principal cambiada a estado: ${nuevoEstado}`, "actuador");
}

// 1. Cargar el último registro guardado en la base de datos al abrir la página
async function cargarUltimoValorDB() {
  try {
    const response = await fetch(`${HTTP_PROTOCOL}//${API_HOST}/api/latest`);
    if (response.ok) {
      const data = await response.json();
      if (data.valor !== undefined) {
        procesarNuevoDato(data.valor);
        agregarLog("[SISTEMA] Último registro sincronizado desde la base de datos.", "sys");
      }
    } else {
      agregarLog("[SISTEMA] Sin datos previos. Esperando transmisión del ESP32...", "sys");
    }
  } catch (error) {
    console.error("Error al consultar la API:", error);
    agregarLog("[SISTEMA] Esperando conexión con el backend...", "alert");
  }
}

// 2. Conexión WebSocket para escuchar al ESP32 en tiempo real
function conectarWebSocket() {
  const socket = new WebSocket(`${WS_PROTOCOL}//${API_HOST}/ws`);
  const badgeEsp32 = document.getElementById('badge-esp32');

  socket.onopen = () => {
    if (badgeEsp32) {
      badgeEsp32.textContent = "ESP32 Conectado";
      badgeEsp32.className = "badge badge-online";
    }
    agregarLog("[WEBSOCKET] Canal en tiempo real activo.", "sys");
  };

  socket.onmessage = (event) => {
    try {
      const valor = parseFloat(event.data);
      if (!isNaN(valor)) {
        procesarNuevoDato(valor);
      }
    } catch (e) {
      console.error("Error al procesar mensaje WS:", e);
    }
  };

  socket.onclose = () => {
    if (badgeEsp32) {
      badgeEsp32.textContent = "ESP32 Desconectado";
      badgeEsp32.className = "badge badge-desconectado";
    }
    agregarLog("[WEBSOCKET] Conexión perdida. Reintentando en 3s...", "alert");
    setTimeout(conectarWebSocket, 3000);
  };

  socket.onerror = (error) => {
    console.error("Error en WebSocket:", error);
    socket.close();
  };
}

// Inicialización al cargar la página
window.addEventListener('DOMContentLoaded', () => {
  refrescarPantalla(); // Deja todo en 0 de forma limpia al iniciar
  cargarUltimoValorDB();
  conectarWebSocket();
});