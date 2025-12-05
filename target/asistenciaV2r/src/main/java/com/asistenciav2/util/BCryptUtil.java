package com.asistenciav2.util;

import org.mindrot.jbcrypt.BCrypt;

public class BCryptUtil {
    
    public static String hashPassword(String plainTextPassword) {
        return BCrypt.hashpw(plainTextPassword, BCrypt.gensalt());
    }
    
    public static boolean checkPassword(String plainTextPassword, String hashedPassword) {
        try {
            // Verificar si el hash tiene el formato correcto de BCrypt (comienza con '$2a$', '$2b$' o '$2y$')
            if (hashedPassword == null || hashedPassword.isEmpty()) {
                return false;
            }
            
            // Compatibilidad con Laravel: Laravel usa el formato $2y$
            // Si el hash comienza con $2y$, convertirlo a $2a$ para compatibilidad con jBCrypt
            if (hashedPassword.startsWith("$2y$")) {
                hashedPassword = "$2a$" + hashedPassword.substring(4);
            }
            
            // Verificar si el hash tiene el formato correcto de BCrypt
            if (!hashedPassword.matches("\\$2[aby]\\$\\d+\\$.*")) {
                // Si no tiene el formato correcto, comparar directamente (para contraseñas sin hash)
                return plainTextPassword.equals(hashedPassword);
            }
            
            return BCrypt.checkpw(plainTextPassword, hashedPassword);
        } catch (IllegalArgumentException e) {
            // Si hay un error en el formato del hash, comparar directamente
            return plainTextPassword.equals(hashedPassword);
        }
    }
}