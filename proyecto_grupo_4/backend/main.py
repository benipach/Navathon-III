from fastapi import FastAPI, HTTPException, status, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, Any, Optional, List
import httpx

app = FastAPI(
    title="Grupo 4: Administración Inteligente de Agua - API Oficial (Integrada con WebSockets y Neon)",
    version="1.1.0"
)

# Configuración de CORS para permitir conexiones desde cualquier origen (incluyendo tu HTML local o web)
app.add_middleware( 
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# URL base de la REST API de Neon
NEON_REST_URL = "https://ep-autumn-salad-b6kfp0s6.apirest.c-2.sa-east-1.aws.neon.tech/neondb/rest/v1"

HEADERS = {
    "Content-Type": "application/json",
    # "apikey": "TU_TOKEN_DE_NEON_SI_LO_REQUIERE"
}

# --- GESTOR DE WEBSOCKETS (Para tiempo real en el HTML) ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: str):
        """Envía el nuevo valor del sensor a todas las pestañas/dashboards abiertos."""
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception:
                pass

manager = ConnectionManager()

# --- Modelos Pydantic (Contrato Grupo 4) ---

class MetadataModel(BaseModel):
    environment: str
    source_type: str
    alert_evaluated: bool
    clock_synced: bool
    units: Dict[str, str]
    quality: Dict[str, str]
    sources: Optional[Dict[str, str]] = None

class RegistroPayload(BaseModel):
    schema_version: str
    record_id: str
    record_type: str
    node_id: str
    group: int
    subsystem: str
    timestamp: str
    status: str
    alert_level: str
    data: Dict[str, Any]
    metadata: MetadataModel


# --- FUNCIÓN AUXILIAR PARA EXTRAER EL VALOR DEL SENSOR ---
def extraer_valor_sensor(payload_dict: dict) -> float:
    """Busca de forma inteligente el valor numérico dentro del diccionario 'data'."""
    data_dict = payload_dict.get("data", {})
    if not data_dict:
        return 0.0
    
    # Intenta buscar llaves comunes primero
    for key in ["valor", "nivel", "nivel_agua", "distancia", "lectura", "sensor"]:
        if key in data_dict:
            try:
                return float(data_dict[key])
            except (ValueError, TypeError):
                pass
                
    # Si no encuentra ninguna llave común, toma el primer valor numérico que encuentre
    for val in data_dict.values():
        try:
            return float(val)
        except (ValueError, TypeError):
            continue
            
    return 0.0


# ==========================================
# ENDPOINTS COMPATIBLES CON EL HTML
# ==========================================

@app.get("/api/latest")
async def obtener_ultimo_valor_html():
    """Endpoint que consulta el último registro en Neon y le entrega el valor formateado al HTML."""
    async with httpx.AsyncClient() as client:
        try:
            url = f"{NEON_REST_URL}/registros_tanque?order=timestamp.desc&limit=1"
            response = await client.get(url, headers=HEADERS)
            
            if response.status_code != 200 or not response.json():
                return {"valor": 0}
            
            fila = response.json()[0]
            payload = fila.get("payload", {})
            
            valor_final = extraer_valor_sensor(payload)
            return {"valor": valor_final}
        except Exception:
            return {"valor": 0}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Canal WebSocket para enviar datos en tiempo real al HTML cuando el ESP32 transmita."""
    await manager.connect(websocket)
    try:
        while True:
            # Mantiene la conexión activa escuchando latidos del cliente
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)


# ==========================================
# ENDPOINTS ORIGINALES DE TU API REST
# ==========================================

@app.get("/api/v1/status")
async def obtener_estado_actual():
    """Retorna el último registro de tipo 'state' consultando la REST API de Neon."""
    async with httpx.AsyncClient() as client:
        try:
            url = f"{NEON_REST_URL}/registros_tanque?record_type=eq.state&order=timestamp.desc&limit=1"
            response = await client.get(url, headers=HEADERS)
            
            if response.status_code != 200:
                raise HTTPException(status_code=502, detail="Error al consultar Neon REST API")
            
            data = response.json()
            if data and len(data) > 0:
                return data[0]["payload"]
            
            raise HTTPException(status_code=404, detail="No hay estados registrados todavía")
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/records")
async def obtener_registros_historicos(cursor: Optional[str] = None, limit: int = 100):
    """Entrega registros históricos paginados desde Neon REST API."""
    async with httpx.AsyncClient() as client:
        try:
            url = f"{NEON_REST_URL}/registros_tanque?order=timestamp.desc&limit={limit}"
            response = await client.get(url, headers=HEADERS)
            
            if response.status_code != 200:
                raise HTTPException(status_code=502, detail="Error al consultar registros en Neon")
            
            filas = response.json()
            items = [fila["payload"] for fila in filas if "payload" in fila]
            
            return {
                "items": items,
                "next_cursor": None,
                "has_more": False
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/records", status_code=status.HTTP_201_CREATED)
async def recibir_registro_externo(payload: RegistroPayload):
    """Recibe y persiste registros en Neon vía REST API, validando idempotencia y notificando por WebSocket."""
    payload_dict = payload.model_dump()
    
    async with httpx.AsyncClient() as client:
        try:
            # 1. Verificar si ya existe el record_id (Idempotencia)
            check_url = f"{NEON_REST_URL}/registros_tanque?record_id=eq.{payload.record_id}"
            check_resp = await client.get(check_url, headers=HEADERS)
            
            if check_resp.status_code == 200:
                existentes = check_resp.json()
                if existentes and len(existentes) > 0:
                    if existentes[0].get("payload") == payload_dict:
                        return {"status": "success", "message": "Registro idéntico ya almacenado previamente", "record_id": payload.record_id}
                    else:
                        raise HTTPException(
                            status_code=status.HTTP_409_CONFLICT,
                            detail=f"El record_id '{payload.record_id}' ya existe con contenido diferente."
                        )

            # 2. Insertar nuevo registro en la tabla de Neon
            insert_url = f"{NEON_REST_URL}/registros_tanque"
            body = {
                "record_id": payload.record_id,
                "record_type": payload.record_type,
                "timestamp": payload.timestamp,
                "payload": payload_dict
            }
            
            insert_resp = await client.post(insert_url, json=body, headers=HEADERS)
            
            if insert_resp.status_code not in [200, 201]:
                raise HTTPException(status_code=500, detail=f"Error al guardar en Neon: {insert_resp.text}")

            print(f"[NEON REST API] Registro guardado exitosamente: {payload.record_id}")
            
            # 🚀 3. TRANSMISIÓN EN VIVO: Enviar el valor extraído a todas las pantallas abiertas por WebSocket
            valor_sensor = extraer_valor_sensor(payload_dict)
            await manager.broadcast(str(valor_sensor))

            return {
                "status": "success",
                "accepted": 1,
                "duplicates": 0,
                "record_id": payload.record_id
            }
        except HTTPException as he:
            raise he
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Error de conexión con Neon REST: {str(e)}")