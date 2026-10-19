#include <ESP32Servo.h>

const int pinA = 13;
const int pinB = 14;
const int pinC = 26;
const int pinD = 19;
const int pinE = 21;
const int pinF = 22;
const int pinG = 23;

const int pinServo = 18;
const int pinBuzzer = 25;
const int pinSensor = 4;     
const int pinRelayBomba = 27;    

Servo miServo;

byte numeros[10][7] = {
  {1, 1, 1, 1, 1, 1, 0}, 
  {0, 1, 1, 0, 0, 0, 0}, 
  {1, 1, 0, 1, 1, 0, 1}, 
  {1, 1, 1, 1, 0, 0, 1}, 
  {0, 1, 1, 0, 0, 1, 1}, 
  {1, 0, 1, 1, 0, 1, 1}, 
  {1, 0, 1, 1, 1, 1, 1}, 
  {1, 1, 1, 0, 0, 0, 0}, 
  {1, 1, 1, 1, 1, 1, 1}, 
  {1, 1, 1, 1, 0, 1, 1}  
};

void tocarAlarmaMolesta() {
  tone(pinBuzzer, 2500); 
  delay(120);
  tone(pinBuzzer, 1500); 
  delay(120);
  tone(pinBuzzer, 3000); 
  delay(120);
  noTone(pinBuzzer);  
  delay(30);
}

void setup() {
  Serial.begin(115200); // Velocidad de comunicación por USB

  pinMode(pinA, OUTPUT);
  pinMode(pinB, OUTPUT);
  pinMode(pinC, OUTPUT);
  pinMode(pinD, OUTPUT);
  pinMode(pinE, OUTPUT);
  pinMode(pinF, OUTPUT);
  pinMode(pinG, OUTPUT);

  pinMode(pinBuzzer, OUTPUT);
  pinMode(pinSensor, INPUT);
  pinMode(pinRelayBomba, OUTPUT);
  
  digitalWrite(pinRelayBomba, LOW);

  miServo.attach(pinServo);
  miServo.write(0);
}

void mostrarNumero(int num) {
  if (num >= 0 && num <= 9) {
    digitalWrite(pinA, numeros[num][0]);
    digitalWrite(pinB, numeros[num][1]);
    digitalWrite(pinC, numeros[num][2]);
    digitalWrite(pinD, numeros[num][3]);
    digitalWrite(pinE, numeros[num][4]);
    digitalWrite(pinF, numeros[num][5]);
    digitalWrite(pinG, numeros[num][6]);
  }
}

void loop() {
  int nivelAguaRaw = analogRead(pinSensor);

  // Mapeamos directo del 1 al 5
  int nivelAgua = map(nivelAguaRaw, 100, 2500, 1, 5);
  nivelAgua = constrain(nivelAgua, 1, 5);

  // Niveles de alerta según el nivel del agua
  String alertLevel = "normal";
  if (nivelAgua == 1) {
    alertLevel = "critical";
  } else if (nivelAgua == 2) {
    alertLevel = "high";
  } else if (nivelAgua == 3) {
    alertLevel = "medium";
  } else if (nivelAgua == 4) {
    alertLevel = "low";
  } else if (nivelAgua == 5) {
    alertLevel = "normal";
  }

  String estadoBuzzer = "APAGADO";
  String estadoMotores = "APAGADOS";
  int gradosServo = 0;

  switch (nivelAgua) {
    case 1: 
      gradosServo = 90;
      digitalWrite(pinRelayBomba, HIGH);
      estadoMotores = "ENCENDIDOS";
      estadoBuzzer = "SIRENA MOLESTA";
      miServo.write(gradosServo);
      mostrarNumero(nivelAgua);
      tocarAlarmaMolesta();
      break;

    case 2: 
      gradosServo = 60;
      digitalWrite(pinRelayBomba, HIGH);
      estadoMotores = "ENCENDIDOS";
      noTone(pinBuzzer);
      estadoBuzzer = "APAGADO";
      miServo.write(gradosServo);
      mostrarNumero(nivelAgua);
      break;

    case 3: 
      gradosServo = 45;
      digitalWrite(pinRelayBomba, LOW);
      estadoMotores = "APAGADOS";
      noTone(pinBuzzer);
      estadoBuzzer = "APAGADO";
      miServo.write(gradosServo);
      mostrarNumero(nivelAgua);
      break;

    case 4: 
      gradosServo = 20;
      digitalWrite(pinRelayBomba, LOW);
      estadoMotores = "APAGADOS";
      noTone(pinBuzzer);
      estadoBuzzer = "APAGADO";
      miServo.write(gradosServo);
      mostrarNumero(nivelAgua);
      break;

    case 5:
      gradosServo = 0;
      digitalWrite(pinRelayBomba, LOW);
      estadoMotores = "APAGADOS";
      noTone(pinBuzzer);
      estadoBuzzer = "APAGADO";
      miServo.write(gradosServo);
      mostrarNumero(nivelAgua);
      break;
  }

  // ARMAMOS EL JSON MANDANDO EL NIVEL REAL (1 al 5) DIRECTO A LA BDD
  String jsonPayload = "{";
  jsonPayload += "\"schema_version\":\"1.0.0\",";
  jsonPayload += "\"record_id\":\"water-node-" + String(millis()) + "\",";
  jsonPayload += "\"record_type\":\"reading\",";
  jsonPayload += "\"node_id\":\"water_node_01\",";
  jsonPayload += "\"group\":4,";
  jsonPayload += "\"subsystem\":\"Administracion inteligente de agua\",";
  jsonPayload += "\"timestamp\":\"2026-10-19T10:30:00-03:00\",";
  jsonPayload += "\"status\":\"active\",";
  jsonPayload += "\"alert_level\":\"" + alertLevel + "\",";
  jsonPayload += "\"data\":{\"water_level\":" + String(porcentajeAgua) + "},";
  jsonPayload += "\"metadata\":{\"environment\":\"test\",\"source_type\":\"real\",\"alert_evaluated\":true,\"units\":{\"water_level\":\"level\"},\"quality\":{\"water_level\":\"valid\"}}";
  jsonPayload += "}";

  // Imprime la línea por USB para que Node.js la atrape
  Serial.println(jsonPayload);

  delay(5000); // Pausa de 5 segundos
}
