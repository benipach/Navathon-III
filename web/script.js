const ALTURA_TANQUE_M = 5;      // altura total del tanque en metros
const MAX_LOGS = 50;             // máximo de registros visibles
const INTERVALO_MS = 3000;

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
let nivelActual = 82.5;
let caudalActual = 45.2;
let estadoPrevio = null;

// Estados del tanque: texto, color del texto y estilo de la etiqueta
function calcularEstado(nivel) {
  if (nivel >= 80) return { texto: "Normal", badge: "badge-optimo", color: "text-water", critico: false };
  if (nivel >= 60) return { texto: "Low",   badge: "badge-optimo", color: "text-water", critico: false };
  if (nivel >= 40) return { texto: "Medium",    badge: "badge-warn",   color: "text-warn",  critico: false };
  if (nivel >= 20) return { texto: "High",     badge: "badge-warn",   color: "text-warn",  critico: false };
  return { texto: "CRITICAL", badge: "badge-alert", color: "text-alert", critico: true };
}

// Ventana emergente de nivel crítico
const alertaModal = document.getElementById('alerta-modal');

function mostrarAlertaCritica(estado) {
  const altura = (nivelActual / 100 * ALTURA_TANQUE_M).toFixed(2).replace('.', ',');
  document.getElementById('alerta-titulo').innerText = `⚠ ${estado.texto}`;
  document.getElementById('alerta-dato').innerText = nivelActual.toFixed(1) + '%';
  document.getElementById('alerta-mensaje').innerText =
    `El tanque está casi vacío (${altura} m).`;
  alertaModal.hidden = false;
  document.getElementById('alerta-cerrar').focus();
}

function cerrarAlertaCritica() { alertaModal.hidden = true; }
document.getElementById('alerta-cerrar').addEventListener('click', cerrarAlertaCritica);
document.addEventListener('keydown', e => { if (e.key === 'Escape') cerrarAlertaCritica(); });

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

// Pinta en pantalla los valores actuales (no modifica el nivel)
function refrescarPantalla() {
  const estado = calcularEstado(nivelActual);
  const abierta = estadoValvula === "ABIERTA";

  const kpiNivel = document.getElementById('kpi-nivel');
  kpiNivel.innerText = nivelActual.toFixed(1) + '%';
  kpiNivel.className = `kpi-value ${estado.color}`;

  document.getElementById('kpi-altura').innerText =
    `Tanque Principal (${(nivelActual / 100 * ALTURA_TANQUE_M).toFixed(2).replace('.', ',')} m)`;

  document.getElementById('kpi-caudal').innerText = caudalActual.toFixed(1) + ' L/s';
  document.getElementById('kpi-caudal-sub').innerText =
    abierta ? 'Red de distribución activa' : 'Distribución interrumpida';

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

function controlarValvula(nuevoEstado) {
  if (nuevoEstado === estadoValvula) return;
  estadoValvula = nuevoEstado;
  caudalActual = (estadoValvula === "ABIERTA") ? 42 + Math.random() * 6 : 0;
  refrescarPantalla();   // se refleja al instante
  agregarLog(`[ACTUADOR] Válvula principal cambiada a estado: ${nuevoEstado}`, "actuador");
}

function actualizarSimulacion() {
  const horaActual = new Date().toLocaleTimeString();

  // Aporte constante de agua y consumo solo si la válvula está abierta
  const aporte = 5 + Math.random() * 0.3;
  const consumo = (estadoValvula === "ABIERTA") ? 15 + Math.random() * 0.6 : 0;
  nivelActual = Math.min(100, Math.max(0, nivelActual + aporte - consumo));
  caudalActual = (estadoValvula === "ABIERTA") ? 42 + Math.random() * 6 : 0;

  refrescarPantalla();

  // Registrar solo cuando cambia el estado del tanque
  const estado = calcularEstado(nivelActual);
  if (estado.texto !== estadoPrevio) {
    agregarLog(`[TELEMETRÍA] ${estado.texto} (${nivelActual.toFixed(1)}%)`, estado.critico ? "alert" : "telemetry");
    estadoPrevio = estado.texto;
    if (estado.critico) mostrarAlertaCritica(estado);
  }

  if (graficoNivel.data.labels.length > 10) {
    graficoNivel.data.labels.shift();
    graficoNivel.data.datasets[0].data.shift();
  }
  graficoNivel.data.labels.push(horaActual);
  graficoNivel.data.datasets[0].data.push(Number(nivelActual.toFixed(1)));
  graficoNivel.update();
}

setInterval(actualizarSimulacion, INTERVALO_MS);
actualizarSimulacion();
