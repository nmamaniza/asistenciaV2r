package com.asistenciav2.biometric;

import java.io.*;
import java.net.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.logging.Logger;
import java.util.logging.Level;

public class ZKTecoProtocol {
    private static final Logger logger = Logger.getLogger(ZKTecoProtocol.class.getName());
    
    // Comandos del protocolo ZKTeco
    private static final int CMD_CONNECT = 1000;
    private static final int CMD_EXIT = 1001;
    private static final int CMD_ENABLEDEVICE = 1002;
    private static final int CMD_DISABLEDEVICE = 1003;
    private static final int CMD_ACK_OK = 2000;
    private static final int CMD_ACK_ERROR = 2001;
    private static final int CMD_ACK_DATA = 2002;
    private static final int CMD_ACK_UNAUTH = 2005;
    private static final int CMD_GET_FREE_SIZES = 50;
    private static final int CMD_ATTLOGDATA = 13;
    private static final int CMD_OPTIONS_WRQ = 2;
    
    private static final int DEFAULT_PORT = 4370;
    private static final int PACKET_SIZE = 1024;
    private static final int DEFAULT_TIMEOUT = 15000; // 15 segundos
    private static final int MAX_RETRIES = 3;

    // Aumentar timeouts si es necesario
private static final int CONNECT_TIMEOUT = 10000; // 10 segundos
private static final int READ_TIMEOUT = 15000;    // 15 segundos
    
    private Socket socket;
    private DataInputStream inputStream;
    private DataOutputStream outputStream;
    private int sessionId = 0;
    private int replyNumber = 0;
    private String deviceIp;
    private int devicePort;
    private boolean isConnected = false;
    private int devicePassword = 0; // Contraseña por defecto
    
    public ZKTecoProtocol(String deviceIp, int devicePort, int devicePassword) {
        if (deviceIp == null || deviceIp.trim().isEmpty()) {
            throw new IllegalArgumentException("La IP del dispositivo no puede estar vacía");
        }
        if (devicePort <= 0 || devicePort > 65535) {
            throw new IllegalArgumentException("El puerto debe estar entre 1 y 65535");
        }
        this.deviceIp = deviceIp.trim();
        this.devicePort = devicePort;
        this.devicePassword = devicePassword;
    }
    
    public ZKTecoProtocol(String deviceIp, int devicePort) {
        this(deviceIp, devicePort, 0);
    }
    
    public ZKTecoProtocol(String deviceIp) {
        this(deviceIp, DEFAULT_PORT, 0);
    }
    
    /**
     * Conecta al dispositivo ZKTeco con reintentos automáticos
     */
    public boolean connect() throws IOException {
        return connectWithRetries(MAX_RETRIES);
    }
    
    private boolean connectWithRetries(int maxRetries) throws IOException {
        IOException lastException = null;
        
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                logger.info(String.format("[INTENTO %d/%d] Conectando a %s:%d", attempt, maxRetries, deviceIp, devicePort));
                
                if (performConnection()) {
                    isConnected = true;
                    logger.info("Conexión establecida exitosamente");
                    return true;
                }
                
            } catch (IOException e) {
                lastException = e;
                logger.warning(String.format("Intento %d falló: %s", attempt, e.getMessage()));
                
                // Limpiar conexiones antes del siguiente intento
                closeConnections();
                
                if (attempt < maxRetries) {
                    try {
                        // Agregar delay entre intentos
                        Thread.sleep(5000); // 5 segundos entre reintentos
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        throw new IOException("Conexión interrumpida", ie);
                    }
                }
            }
        }
        
        isConnected = false;
        if (lastException != null) {
            throw new IOException("Falló la conexión después de " + maxRetries + " intentos", lastException);
        }
        return false;
    }
    
    private boolean performConnection() throws IOException {
        try {
            // Crear socket con timeout
            socket = new Socket();
            socket.connect(new InetSocketAddress(deviceIp, devicePort), 5000); // 5 segundos para conectar
            socket.setSoTimeout(DEFAULT_TIMEOUT);
            logger.info("Socket TCP conectado exitosamente");
            
            inputStream = new DataInputStream(socket.getInputStream());
            outputStream = new DataOutputStream(socket.getOutputStream());
            logger.info("Streams de entrada y salida creados");
            
            // Enviar comando de conexión
            byte[] connectPacket = createPacket(CMD_CONNECT, new byte[0]);
            sendPacketWithRetry(connectPacket, "CONNECT");
            
            // Leer respuesta
            byte[] response = readPacketWithTimeout();
            
            if (response == null) {
                throw new IOException("No se recibió respuesta del dispositivo");
            }
            
            int responseCmd = getCommandFromPacket(response);
            logger.info(String.format("Respuesta recibida - Comando: %d, Esperado: %d", responseCmd, CMD_ACK_OK));
            
            if (responseCmd == CMD_ACK_OK) {
                sessionId = getSessionIdFromPacket(response);
                logger.info("CMD_ACK_OK recibido, sessionId: " + sessionId);
                
                // Configurar SDKBuild=1
                return configureSDKBuild();
            } else if (responseCmd == CMD_ACK_ERROR) {
                throw new IOException("El dispositivo rechazó la conexión (CMD_ACK_ERROR)");
            } else if (responseCmd == CMD_ACK_UNAUTH) {
                throw new IOException("Acceso no autorizado al dispositivo (CMD_ACK_UNAUTH)");
            } else {
                throw new IOException("Respuesta inesperada del dispositivo: " + responseCmd);
            }
            
        } catch (IOException e) {
            closeConnections();
            throw e;
        }
    }
    
    private boolean configureSDKBuild() throws IOException {
        try {
            String sdkBuild = "SDKBuild=1\0";
            byte[] optionsPacket = createPacket(CMD_OPTIONS_WRQ, sdkBuild.getBytes("UTF-8"));
            sendPacketWithRetry(optionsPacket, "OPTIONS_WRQ");
            
            byte[] optionsResponse = readPacketWithTimeout();
            
            if (optionsResponse == null) {
                logger.warning("No se recibió respuesta para OPTIONS_WRQ");
                return false;
            }
            
            boolean success = getCommandFromPacket(optionsResponse) == CMD_ACK_OK;
            logger.info("Configuración SDKBuild: " + (success ? "EXITOSA" : "FALLIDA"));
            return success;
            
        } catch (IOException e) {
            logger.severe("Error configurando SDKBuild: " + e.getMessage());
            throw e;
        }
    }
    
    private void sendPacketWithRetry(byte[] packet, String commandName) throws IOException {
        for (int i = 0; i < 3; i++) {
            try {
                outputStream.write(packet);
                outputStream.flush();
                logger.info("Comando " + commandName + " enviado");
                return;
            } catch (IOException e) {
                if (i == 2) throw e;
                logger.warning("Reintentando envío de " + commandName);
            }
        }
    }
    
    private byte[] readPacketWithTimeout() throws IOException {
        try {
            return readPacket();
        } catch (SocketTimeoutException e) {
            logger.warning("Timeout leyendo respuesta del dispositivo");
            return null;
        }
    }
    
    /**
     * Verifica si la conexión está activa
     */
    public boolean isConnected() {
        return isConnected && socket != null && socket.isConnected() && !socket.isClosed();
    }
    
    /**
     * Desconecta del dispositivo
     */
    public void disconnect() {
        try {
            if (isConnected && outputStream != null) {
                byte[] exitPacket = createPacket(CMD_EXIT, new byte[0]);
                outputStream.write(exitPacket);
                outputStream.flush();
                logger.info("Comando EXIT enviado");
            }
        } catch (IOException e) {
            logger.warning("Error enviando comando EXIT: " + e.getMessage());
        } finally {
            isConnected = false;
            closeConnections();
        }
    }
    
    private void closeConnections() {
        try {
            if (inputStream != null) {
                inputStream.close();
                inputStream = null;
            }
        } catch (IOException e) {
            logger.warning("Error cerrando inputStream: " + e.getMessage());
        }
        
        try {
            if (outputStream != null) {
                outputStream.close();
                outputStream = null;
            }
        } catch (IOException e) {
            logger.warning("Error cerrando outputStream: " + e.getMessage());
        }
        
        try {
            if (socket != null) {
                socket.close();
                socket = null;
            }
        } catch (IOException e) {
            logger.warning("Error cerrando socket: " + e.getMessage());
        }
    }
    
    /**
     * Obtiene los registros de asistencia del dispositivo
     */
    public List<AttendanceRecord> getAttendanceRecords() throws IOException {
        if (!isConnected()) {
            throw new IOException("No hay conexión activa con el dispositivo");
        }
        
        List<AttendanceRecord> records = new ArrayList<>();
        
        // Deshabilitar dispositivo
        if (!disableDevice()) {
            throw new IOException("No se pudo deshabilitar el dispositivo");
        }
        
        try {
            // Solicitar datos de asistencia
            byte[] attLogPacket = createPacket(CMD_ATTLOGDATA, new byte[0]);
            sendPacketWithRetry(attLogPacket, "ATTLOGDATA");
            
            // Leer respuesta con datos
            byte[] response = readPacketWithTimeout();
            if (response != null && getCommandFromPacket(response) == CMD_ACK_DATA) {
                records = parseAttendanceData(getDataFromPacket(response));
                logger.info("Se obtuvieron " + records.size() + " registros de asistencia");
            } else {
                logger.warning("No se recibieron datos de asistencia válidos");
            }
            
        } finally {
            // Rehabilitar dispositivo
            if (!enableDevice()) {
                logger.warning("No se pudo rehabilitar el dispositivo");
            }
        }
        
        return records;
    }
    
    private boolean disableDevice() throws IOException {
        byte[] packet = createPacket(CMD_DISABLEDEVICE, new byte[0]);
        sendPacketWithRetry(packet, "DISABLEDEVICE");
        
        byte[] response = readPacketWithTimeout();
        boolean success = response != null && getCommandFromPacket(response) == CMD_ACK_OK;
        logger.info("Dispositivo deshabilitado: " + success);
        return success;
    }
    
    private boolean enableDevice() throws IOException {
        byte[] packet = createPacket(CMD_ENABLEDEVICE, new byte[0]);
        sendPacketWithRetry(packet, "ENABLEDEVICE");
        
        byte[] response = readPacketWithTimeout();
        boolean success = response != null && getCommandFromPacket(response) == CMD_ACK_OK;
        logger.info("Dispositivo habilitado: " + success);
        return success;
    }
    
    /**
     * Crea un paquete según el protocolo ZKTeco
     */
    private byte[] createPacket(int command, byte[] data) {
        if (data == null) {
            data = new byte[0];
        }
        
        ByteBuffer buffer = ByteBuffer.allocate(16 + data.length);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        
        buffer.putShort((short) command);     // Command ID
        buffer.putShort((short) 0);           // Checksum (se calcula después)
        buffer.putShort((short) sessionId);   // Session ID
        buffer.putShort((short) replyNumber); // Reply Number
        buffer.putInt(data.length);           // Data length
        
        // Usar la contraseña en el campo reservado para comandos de conexión
        if (command == CMD_CONNECT) {
            buffer.putInt(devicePassword);     // Password en el campo reservado
        } else {
            buffer.putInt(0);                // Reserved
        }
        
        buffer.put(data);                     // Data
        
        byte[] packet = buffer.array();
        
        // Calcular checksum
        int checksum = calculateChecksum(packet);
        buffer.putShort(2, (short) checksum);
        
        replyNumber++;
        return packet;
    }
    
    private byte[] readPacket() throws IOException {
        if (inputStream == null) {
            throw new IOException("InputStream no disponible");
        }
        
        byte[] header = new byte[16];
        inputStream.readFully(header);
        
        ByteBuffer headerBuffer = ByteBuffer.wrap(header);
        headerBuffer.order(ByteOrder.LITTLE_ENDIAN);
        
        int command = headerBuffer.getShort(0) & 0xFFFF;
        int dataLength = headerBuffer.getInt(8);
        
        // Validar longitud de datos
        if (dataLength < 0 || dataLength > 1024 * 1024) { // Máximo 1MB
            throw new IOException("Longitud de datos inválida: " + dataLength);
        }
        
        byte[] data = new byte[dataLength];
        if (dataLength > 0) {
            inputStream.readFully(data);
        }
        
        byte[] fullPacket = new byte[16 + dataLength];
        System.arraycopy(header, 0, fullPacket, 0, 16);
        if (dataLength > 0) {
            System.arraycopy(data, 0, fullPacket, 16, dataLength);
        }
        
        return fullPacket;
    }
    
    private int getCommandFromPacket(byte[] packet) {
        if (packet == null || packet.length < 16) {
            return -1;
        }
        ByteBuffer buffer = ByteBuffer.wrap(packet);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        return buffer.getShort(0) & 0xFFFF;
    }
    
    private int getSessionIdFromPacket(byte[] packet) {
        if (packet == null || packet.length < 16) {
            return -1;
        }
        ByteBuffer buffer = ByteBuffer.wrap(packet);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        return buffer.getShort(4) & 0xFFFF;
    }
    
    private byte[] getDataFromPacket(byte[] packet) {
        if (packet == null || packet.length < 16) {
            return new byte[0];
        }
        
        ByteBuffer buffer = ByteBuffer.wrap(packet);
        buffer.order(ByteOrder.LITTLE_ENDIAN);
        int dataLength = buffer.getInt(8);
        
        if (dataLength <= 0 || packet.length < 16 + dataLength) {
            return new byte[0];
        }
        
        byte[] data = new byte[dataLength];
        System.arraycopy(packet, 16, data, 0, dataLength);
        return data;
    }
    
    private int calculateChecksum(byte[] packet) {
        if (packet == null) {
            return 0;
        }
        
        int checksum = 0;
        for (int i = 0; i < packet.length; i++) {
            if (i != 2 && i != 3) { // Saltar el campo checksum
                checksum += packet[i] & 0xFF;
            }
        }
        return checksum & 0xFFFF;
    }
    
    /**
     * Parsea los datos de asistencia del dispositivo
     */
    private List<AttendanceRecord> parseAttendanceData(byte[] data) {
        List<AttendanceRecord> records = new ArrayList<>();
        
        if (data == null || data.length == 0) {
            logger.info("No hay datos de asistencia para parsear");
            return records;
        }
        
        // Cada registro tiene 40 bytes según el protocolo ZKTeco
        int recordSize = 40;
        int recordCount = data.length / recordSize;
        
        logger.info(String.format("Parseando %d registros de %d bytes cada uno", recordCount, recordSize));
        
        for (int i = 0; i < recordCount; i++) {
            int offset = i * recordSize;
            
            if (offset + recordSize > data.length) {
                logger.warning("Registro incompleto en posición " + i);
                break;
            }
            
            try {
                ByteBuffer buffer = ByteBuffer.wrap(data, offset, recordSize);
                buffer.order(ByteOrder.LITTLE_ENDIAN);
                
                int userId = buffer.getShort(0) & 0xFFFF;
                int verifyType = buffer.get(2) & 0xFF;
                int inOutMode = buffer.get(3) & 0xFF;
                int timestamp = buffer.getInt(4);
                
                // Validar datos
                if (userId == 0 || timestamp <= 0) {
                    continue; // Saltar registros inválidos
                }
                
                // Convertir timestamp Unix a LocalDateTime
                LocalDateTime dateTime = LocalDateTime.ofEpochSecond(timestamp, 0, 
                    java.time.ZoneOffset.systemDefault().getRules().getOffset(java.time.Instant.now()));
                
                AttendanceRecord record = new AttendanceRecord();
                record.setUserId(userId);
                record.setVerifyType(verifyType);
                record.setInOutMode(inOutMode);
                record.setTimestamp(dateTime);
                
                records.add(record);
                
            } catch (Exception e) {
                logger.warning("Error parseando registro " + i + ": " + e.getMessage());
                continue;
            }
        }
        
        logger.info("Se parsearon exitosamente " + records.size() + " registros");
        return records;
    }
    
    /**
     * Clase para representar un registro de asistencia
     */
    public static class AttendanceRecord {
        private int userId;
        private int verifyType; // 1=Huella, 15=Contraseña, etc.
        private int inOutMode;  // 0=Entrada, 1=Salida, etc.
        private LocalDateTime timestamp;
        
        // Getters y setters
        public int getUserId() { return userId; }
        public void setUserId(int userId) { this.userId = userId; }
        
        public int getVerifyType() { return verifyType; }
        public void setVerifyType(int verifyType) { this.verifyType = verifyType; }
        
        public int getInOutMode() { return inOutMode; }
        public void setInOutMode(int inOutMode) { this.inOutMode = inOutMode; }
        
        public LocalDateTime getTimestamp() { return timestamp; }
        public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
        
        @Override
        public String toString() {
            return String.format("AttendanceRecord{userId=%d, verifyType=%d, inOutMode=%d, timestamp=%s}",
                userId, verifyType, inOutMode, 
                timestamp != null ? timestamp.format(DateTimeFormatter.ISO_LOCAL_DATE_TIME) : "null");
        }
    }
}