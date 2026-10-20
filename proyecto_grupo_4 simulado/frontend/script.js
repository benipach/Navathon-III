// Configuración de perfiles de reserva: Normal (80% - 100%) y alertas descendentes hasta Crítico
const perfilesSimulados = {
    normal: {
        nivelBase: 90.0,
        caudalBase: 8.5,
        textoSub: "Nivel Normal / Óptimo (80% - 100%)",
        alertaClass: "text-ok",
        badgeClass: "badge-optimo",
        badgeTexto: "Normal (Óptimo)",
        logMsg: "Sistema operando en rango normal y óptimo de almacenamiento.",
        colorGrafico: "#28a745" // Verde
    },
    low: {
        nivelBase: 65.0,
        caudalBase: 6.0,
        textoSub: "Alerta Baja: Descenso leve del tanque",
        alertaClass: "text-primary",
        badgeClass: "badge-primary",
        badgeTexto: "Alerta Baja",
        logMsg: "AVISO: El nivel de reserva descendió por debajo del rango normal.",
        colorGrafico: "#17a2b8" // Celeste
    },
    medium: {
        nivelBase: 45.0,
        caudalBase: 4.5,
        textoSub: "Alerta Media: Reserva Moderada",
        alertaClass: "text-muted",
        badgeClass: "badge-primary",
        badgeTexto: "Alerta Media",
        logMsg: "PRECAUCIÓN: Reserva en nivel medio, operando con restricciones.",
        colorGrafico: "#ffc107" // Amarillo
    },
    high: {
        nivelBase: 25.0,
        caudalBase: 2.5,
        textoSub: "Alerta Alta: Reserva Escasa",
        alertaClass: "text-danger",
        badgeClass: "badge-desconectado",
        badgeTexto: "Alerta Alta",
        logMsg: "ADVERTENCIA: Nivel de agua muy bajo, requiere atención.",
        colorGrafico: "#fd7e14" // Naranja
    },
    critical: {
        nivelBase: 10.0,
        caudalBase: 1.0,
        textoSub: "¡CRÍTICO: Reserva al Mínimo / Riesgo de Corte!",
        alertaClass: "text-danger",
        badgeClass: "badge-desconectado",
        badgeTexto: "¡CRÍTICO! - Nivel Mínimo",
        logMsg: "🚨 ¡ALERTA MÁXIMA Y CRÍTICA! Tanque casi vacío, peor situación operativa.",
        colorGrafico: "#dc3545" // Rojo Peligro
    }
};

let estadoActual = "normal";
let totalLogs = 0;

// Inicialización del Gráfico Chart.js
const ctx = document.getElementById('graficoNivel').getContext('2d');
const chartNivel = new Chart(ctx, {
    type: 'line',
    data: {
        labels: [],
        datasets: [{
            label: 'Nivel Tanque (%)',
            data: [],
            borderColor: '#28a745',
            backgroundColor: 'rgba(40, 167, 69, 0.15)',
            fill: true,
            tension: 0.4
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
            y: {
                min: 0,
                max: 100,
                grid: { color: 'rgba(255, 255, 255, 0.1)' },
                ticks: { color: '#94a3b8' }
            },
            x: {
                grid: { color: 'rgba(255, 255, 255, 0.05)' },
                ticks: { color: '#94a3b8' }
            }
        },
        plugins: {
            legend: { labels: { color: '#f8fafc' } }
        }
    }
});

// Función para cambiar de estado al presionar los botones
function cambiarNivelSimulacion(nivel) {
    if (!perfilesSimulados[nivel]) return;
    estadoActual = nivel;
    const perfil = perfilesSimulados[nivel];
    
    // Cambiar dinámicamente el color del gráfico según la severidad
    chartNivel.data.datasets[0].borderColor = perfil.colorGrafico;
    chartNivel.data.datasets[0].backgroundColor = perfil.colorGrafico + "26"; // 15% opacidad
    
    // Registrar evento en la consola
    agregarLog(`[ESTADO] Modo cambiado a: ${nivel.toUpperCase()} - ${perfil.logMsg}`);
    
    // Actualización inmediata
    actualizarDashboard();
}

// Actualiza los valores en pantalla con ligera fluctuación simulada
function actualizarDashboard() {
    const perfil = perfilesSimulados[estadoActual];
    
    // Variación pequeña para dar dinamismo al sensor
    const fluctuacionNivel = (Math.random() * 2.0 - 1.0);
    const fluctuacionCaudal = (Math.random() * 0.3 - 0.15);

    const nivelFinal = Math.min(100, Math.max(0, perfil.nivelBase + fluctuacionNivel)).toFixed(1);
    const caudalFinal = Math.max(0, perfil.caudalBase + fluctuacionCaudal).toFixed(1);
    const alturaMeters = (nivelFinal * 0.05).toFixed(2); // Tanque de 5 metros

    // Actualizar KPIs superiores
    document.getElementById('kpi-nivel').innerText = `${nivelFinal}%`;
    document.getElementById('kpi-altura').innerText = `Tanque Principal (${alturaMeters} m)`;
    document.getElementById('kpi-caudal').innerText = `${caudalFinal} L/s`;
    document.getElementById('kpi-caudal-sub').innerText = perfil.textoSub;
    
    const kpiAlerta = document.getElementById('kpi-alerta');
    kpiAlerta.innerText = estadoActual.toUpperCase();
    kpiAlerta.className = `kpi-value ${perfil.alertaClass}`;

    // Actualizar Tanque Animado
    document.getElementById('tank-water').style.height = `${nivelFinal}%`;
    const statusLabel = document.getElementById('tank-status-label');
    statusLabel.innerText = perfil.badgeTexto;
    statusLabel.className = `badge ${perfil.badgeClass} mt-3`;

    // Actualizar Gráfica Histórica
    const horaActual = new Date().toLocaleTimeString();
    chartNivel.data.labels.push(horaActual);
    chartNivel.data.datasets[0].data.push(nivelFinal);

    if (chartNivel.data.labels.length > 12) {
        chartNivel.data.labels.shift();
        chartNivel.data.datasets[0].data.shift();
    }
    chartNivel.update();
}

// Registro de logs en la consola inferior
function agregarLog(mensaje) {
    const container = document.getElementById('log-container');
    const logItem = document.createElement('p');
    logItem.style.margin = '4px 0';
    logItem.style.fontFamily = 'monospace';
    logItem.style.fontSize = '0.85rem';
    
    // Destacar en rojo los logs críticos
    if (estadoActual === 'critical') {
        logItem.style.color = '#ff6b6b';
        logItem.style.fontWeight = 'bold';
    }

    logItem.innerHTML = `<span style="color: #94a3b8;">[${new Date().toLocaleTimeString()}]</span> ${mensaje}`;
    
    container.prepend(logItem);
    totalLogs++;
    document.getElementById('log-count').innerText = `${totalLogs} eventos registrados`;
}

// Inicialización automática
document.addEventListener('DOMContentLoaded', () => {
    agregarLog("Sistema de gestión hídrica simulada inicializado.");
    cambiarNivelSimulacion('normal');
    
    // Bucle continuo cada 3 segundos
    setInterval(actualizarDashboard, 3000);
});