#include "WiFi.h"
#include "SPIFFS.h"

// Analog microphone on GPIO 35
#define MIC_PIN 35

// WiFi credentials
const char* ssid = "ESP32-Audio";
const char* password = "12345678";

// Audio settings - using stable sampling rate
#define SAMPLE_RATE 16000  // Stable and consistent rate
#define BUFFER_SIZE 1024
#define RECORD_TIME 5 // seconds

// Web server
WiFiServer server(80);

// WAV file header structure
typedef struct {
  char chunkID[4];
  uint32_t chunkSize;
  char format[4];
  char subchunk1ID[4];
  uint32_t subchunk1Size;
  uint16_t audioFormat;
  uint16_t numChannels;
  uint32_t sampleRate;
  uint32_t byteRate;
  uint16_t blockAlign;
  uint16_t bitsPerSample;
  char subchunk2ID[4];
  uint32_t subchunk2Size;
} wav_header_t;

// Global variables
bool isRecording = false;
bool audioReady = false;

void setup() {
  Serial.begin(115200);
  
  // Initialize SPIFFS
  if (!initSPIFFS()) {
    Serial.println("SPIFFS initialization failed!");
    return;
  }
  
  // Setup analog microphone pin
  analogReadResolution(12); // ESP32 ADC is 12-bit
  analogSetAttenuation(ADC_11db); // For best range 0-3.3V
  pinMode(MIC_PIN, INPUT);
  
  // Setup WiFi Access Point
  setupWiFi();
  
  Serial.println("System ready!");
  Serial.println("Connect to WiFi: ESP32-Audio");
  Serial.println("Password: 12345678");
  Serial.println("Then visit: http://192.168.4.1");
  Serial.printf("Target sample rate: %d Hz\n", SAMPLE_RATE);
}

void loop() {
  // Handle web clients
  WiFiClient client = server.available();
  if (client) {
    handleWebClient(client);
  }
  
  delay(100);
}

bool initSPIFFS() {
  if (!SPIFFS.begin(true)) {
    Serial.println("SPIFFS mount failed");
    return false;
  }
  Serial.println("SPIFFS mounted successfully");
  return true;
}

void setupWiFi() {
  WiFi.softAP(ssid, password);
  server.begin();
  Serial.print("AP IP address: ");
  Serial.println(WiFi.softAPIP());
}

void handleWebClient(WiFiClient client) {
  Serial.println("New client connected");
  
  String request = client.readStringUntil('\r');
  Serial.println("Request: " + request);
  client.flush();
  
  // Serve HTML page
  if (request.indexOf("GET / ") != -1) {
    sendHTMLPage(client);
  }
  // Start recording
  else if (request.indexOf("GET /start") != -1) {
    startRecording(client);
  }
  // Stop recording
  else if (request.indexOf("GET /stop") != -1) {
    stopRecording(client);
  }
  // Download audio
  else if (request.indexOf("GET /download") != -1) {
    downloadAudio(client);
  }
  
  delay(1);
  client.stop();
  Serial.println("Client disconnected");
}

void sendHTMLPage(WiFiClient client) {
  client.println("HTTP/1.1 200 OK");
  client.println("Content-type:text/html");
  client.println();
  
  String html = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
    <title>ESP32 Audio Recorder</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial; margin: 40px; }
        button { padding: 12px 24px; font-size: 16px; margin: 10px; }
        .recording { background-color: #ff4444; color: white; }
        .info { background-color: #e7f3ff; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>ESP32 Audio Recorder</h1>
    <div class="info">
        <p>Sample Rate: 16 kHz (consistent speed)</p>
        <p>Recording Time: 5 seconds</p>
    </div>
    <button onclick="startRecording()">Start Recording</button>
    <button onclick="stopRecording()">Stop Recording</button>
    <button onclick="downloadAudio()" id="downloadBtn" disabled>Download Audio</button>
    <div id="status">Ready</div>
    
    <script>
        function startRecording() {
            fetch('/start')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('status').innerHTML = 'Recording...';
                    document.querySelector('button').classList.add('recording');
                });
        }
        
        function stopRecording() {
            fetch('/stop')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('status').innerHTML = 'Recording stopped';
                    document.querySelector('button').classList.remove('recording');
                    document.getElementById('downloadBtn').disabled = false;
                });
        }
        
        function downloadAudio() {
            window.location.href = '/download';
        }
    </script>
</body>
</html>
  )rawliteral";
  
  client.println(html);
}

void startRecording(WiFiClient client) {
  if (!isRecording) {
    isRecording = true;
    audioReady = false;
    xTaskCreate(recordAudioTask, "Record Audio", 8192, NULL, 1, NULL);
    sendResponse(client, "Recording started");
  } else {
    sendResponse(client, "Already recording");
  }
}

void stopRecording(WiFiClient client) {
  isRecording = false;
  sendResponse(client, "Recording stopped");
}

void downloadAudio(WiFiClient client) {
  if (SPIFFS.exists("/audio.wav")) {
    File file = SPIFFS.open("/audio.wav", FILE_READ);
    if (file) {
      client.println("HTTP/1.1 200 OK");
      client.println("Content-Type: audio/wav");
      client.println("Content-Disposition: attachment; filename=audio.wav");
      client.println("Connection: close");
      client.println();
      
      // Send file content
      uint8_t buffer[1024];
      while (file.available()) {
        size_t bytesRead = file.read(buffer, sizeof(buffer));
        client.write(buffer, bytesRead);
      }
      file.close();
      return;
    }
  }
  
  // If file doesn't exist
  sendResponse(client, "Audio file not found");
}

void sendResponse(WiFiClient client, String message) {
  client.println("HTTP/1.1 200 OK");
  client.println("Content-type:text/plain");
  client.println();
  client.println(message);
}

void recordAudioTask(void *parameter) {
  Serial.println("Starting audio recording...");
  
  File file = SPIFFS.open("/audio.wav", FILE_WRITE);
  if (!file) {
    Serial.println("Failed to create file!");
    vTaskDelete(NULL);
    return;
  }

  // Write WAV header with fixed sample rate
  wav_header_t wav_header = createWavHeader(SAMPLE_RATE, 16, 1);
  file.write((uint8_t*)&wav_header, sizeof(wav_header));
  
  uint32_t total_samples = 0;
  uint32_t max_samples = SAMPLE_RATE * RECORD_TIME;
  
  // Fixed timing for consistent sampling
  const int SAMPLE_DELAY_US = 1000000 / SAMPLE_RATE; // 125us for 8kHz
  
  Serial.printf("Target: %d samples in %d seconds\n", max_samples, RECORD_TIME);
  Serial.printf("Sample delay: %d us\n", SAMPLE_DELAY_US);
  
  unsigned long lastSampleTime = micros();
  unsigned long startTime = millis();
  
  while (isRecording && total_samples < max_samples) {
    unsigned long currentTime = micros();
    unsigned long elapsed = currentTime - lastSampleTime;
    
    // Only take a sample when it's time (fixed interval)
    if (elapsed >= SAMPLE_DELAY_US) {
      // Read analog value
      int raw_value = analogRead(MIC_PIN);
      
      // Convert to 16-bit signed audio
      // Remove DC offset (1.5V ~ 1862) and scale
      int16_t audio_sample = (raw_value - 1862) * 16;
      
      // Clamp to 16-bit range to prevent overflow
      if (audio_sample > 32767) audio_sample = 32767;
      if (audio_sample < -32768) audio_sample = -32768;
      
      // Write to file
      file.write((uint8_t*)&audio_sample, sizeof(audio_sample));
      total_samples++;
      lastSampleTime = currentTime;
      
      // Progress indicator
      if (total_samples % (SAMPLE_RATE / 4) == 0) {
        float progress = (total_samples * 100.0) / max_samples;
        unsigned long currentRecordTime = (millis() - startTime) / 1000;
        Serial.printf("Progress: %.1f%% (%ds)\n", progress, currentRecordTime);
      }
    }
    
    // Small delay to prevent overwhelming the CPU
    delayMicroseconds(10);
  }
  
  unsigned long totalTime = millis() - startTime;
  float actualSampleRate = (total_samples * 1000.0) / totalTime;
  
  // Update WAV header
  if (total_samples > 0) {
    updateWavHeader(file, total_samples * sizeof(int16_t));
    audioReady = true;
    Serial.println("Recording complete!");
    Serial.printf("Total samples: %d\n", total_samples);
    Serial.printf("Actual time: %lu ms\n", totalTime);
    Serial.printf("Actual sample rate: %.1f Hz\n", actualSampleRate);
    Serial.printf("Target sample rate: %d Hz\n", SAMPLE_RATE);
  } else {
    Serial.println("Recording failed - no data");
  }
  
  file.close();
  isRecording = false;
  vTaskDelete(NULL);
}

wav_header_t createWavHeader(uint32_t sampleRate, uint16_t bitDepth, uint16_t channels) {
  wav_header_t wav_header;
  
  strcpy(wav_header.chunkID, "RIFF");
  wav_header.chunkSize = 36;
  strcpy(wav_header.format, "WAVE");
  
  strcpy(wav_header.subchunk1ID, "fmt ");
  wav_header.subchunk1Size = 16;
  wav_header.audioFormat = 1;
  wav_header.numChannels = channels;
  wav_header.sampleRate = sampleRate;
  wav_header.byteRate = sampleRate * channels * bitDepth / 8;
  wav_header.blockAlign = channels * bitDepth / 8;
  wav_header.bitsPerSample = bitDepth;
  
  strcpy(wav_header.subchunk2ID, "data");
  wav_header.subchunk2Size = 0;
  
  return wav_header;
}

void updateWavHeader(File &file, uint32_t dataSize) {
  file.seek(0);
  
  wav_header_t wav_header = createWavHeader(SAMPLE_RATE, 16, 1);
  wav_header.chunkSize = 36 + dataSize;
  wav_header.subchunk2Size = dataSize;
  
  file.write((uint8_t*)&wav_header, sizeof(wav_header));
  file.close();
}
