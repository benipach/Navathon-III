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

function calcularEstado(nivel) {
if (nivel >= 80) return "normal";
if (nivel >= 60) return "low";
if (nivel >= 40) return "medium";
if (nivel >= 20) return "high";
return "critical";
}

function controlarValvula(nuevoEstado) {
estadoValvula = nuevoEstado;
const elem = document.getElementById('kpi-valvula');
elem.innerText = estadoValvula;
elem.className = estadoValvula === "ABIERTA" 
? "kpi-value text-ok" 
: "kpi-value text-alert";
agregarLog(`[ACTUADOR] Válvula principal cambiada a estado: ${nuevoEstado}`);
}

function agregarLog(mensaje) {
const logContainer = document.getElementById('log-container');
const hora = new Date().toLocaleTimeString();
const nuevoLog = document.createElement('div');
nuevoLog.innerHTML = `<span class="log-time">[${hora}]</span> ${mensaje}`;
logContainer.prepend(nuevoLog);
}

function actualizarSimulacion() {
const horaActual = new Date().toLocaleTimeString();

if (estadoValvula === "ABIERTA") {
nivelActual = Math.max(0, nivelActual - 10);
}

const nivelRedondeado = nivelActual.toFixed(1);
const caudalAleatorio = (estadoValvula === "ABIERTA") ? (42 + Math.random() * 6).toFixed(1) : (0.0).toFixed(1);

document.getElementById('kpi-nivel').innerText = nivelRedondeado + '%';
document.getElementById('kpi-caudal').innerText = caudalAleatorio + ' L/s';

const estadoActual = calcularEstado(Number(nivelRedondeado));
const statusLabel = document.getElementById('tank-status-label');
if (statusLabel) {
statusLabel.innerText = `Estado: ${estadoActual}`;
}

const tankWater = document.getElementById('tank-water');
tankWater.style.height = nivelRedondeado + '%';

if (graficoNivel.data.labels.length > 10) {
graficoNivel.data.labels.shift();
graficoNivel.data.datasets[0].data.shift();
}
graficoNivel.data.labels.push(horaActual);
graficoNivel.data.datasets[0].data.push(nivelRedondeado);
graficoNivel.update();
}

setInterval(actualizarSimulacion, 3000);
actualizarSimulacion();
