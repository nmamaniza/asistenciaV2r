package com.asistenciav2.security;

import com.asistenciav2.model.User;
import com.asistenciav2.util.DatabaseConnection;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public class CustomUserDetailsService implements UserDetailsService {
    
    @Override
    public UserDetails loadUserByUsername(String identifier) throws UsernameNotFoundException {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT id, nombre, apellidos, email, dni, password, role FROM users WHERE (email = ? OR dni = ?) AND estado = 1";
            PreparedStatement stmt = conn.prepareStatement(sql);
            stmt.setString(1, identifier);
            stmt.setString(2, identifier);
            
            ResultSet rs = stmt.executeQuery();
            
            if (rs.next()) {
                String role = rs.getString("role");
                
                List<GrantedAuthority> authorities = new ArrayList<>();
                if ("administrador".equals(role)) {
                    authorities.add(new SimpleGrantedAuthority("ROLE_ADMIN"));
                } else {
                    authorities.add(new SimpleGrantedAuthority("ROLE_USER"));
                }
                
                return new org.springframework.security.core.userdetails.User(
                    identifier,
                    rs.getString("password"),
                    authorities
                );
            } else {
                throw new UsernameNotFoundException("Usuario no encontrado: " + identifier);
            }
            
        } catch (SQLException e) {
            throw new UsernameNotFoundException("Error de base de datos", e);
        }
    }
}