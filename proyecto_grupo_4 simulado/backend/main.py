from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Copahue Water Management - Simulado")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Estado global simulado inicial
current_state = "normal"

def generate_simulated_metrics(state: str):
    """Genera valores métricos simulados según el nivel de alerta/estado seleccionado."""
    states_config = {
        "low": {"level": 18.2, "flow": 2.1, "temp": 6.5, "ph": 6.0, "message": "Nivel bajo de reserva hídrica."},
        "medium": {"level": 45.0, "flow": 5.4, "temp": 9.0, "ph": 6.8, "message": "Nivel moderado, operación estable."},
        "normal": {"level": 65.0, "flow": 7.0, "temp": 10.2, "ph": 7.1, "message": "Sistema funcionando en parámetros normales."},
        "high": {"level": 88.5, "flow": 11.2, "temp": 13.5, "ph": 7.9, "message": "Precaución: Nivel elevado detectado."},
        "critical": {"level": 98.0, "flow": 15.8, "temp": 18.0, "ph": 8.8, "message": "¡ALERTA CRÍTICA! Riesgo de desborde o presión extrema."}
    }
    return states_config.get(state, states_config["normal"])

@app.get("/api/status")
def get_status():
    return {
        "state": current_state,
        "metrics": generate_simulated_metrics(current_state)
    }

@app.post("/api/set-state/{state}")
def set_state(state: str):
    global current_state
    valid_states = ["normal", "low", "medium", "high", "critical"]
    if state not in valid_states:
        raise HTTPException(status_code=400, detail="Estado no válido")
    current_state = state
    return {
        "success": True,
        "state": current_state,
        "metrics": generate_simulated_metrics(current_state)
    }