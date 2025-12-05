package com.asistenciav2.model;

public class User {
    private int id;
    private String nombre;
    private String email;
    private String dni;
    private String password;
    private int role;
    
    // Constructores
    public User() {}
    
    public User(int id, String nombre, String email, String dni, String password, int role) {
        this.id = id;
        this.nombre = nombre;
        this.email = email;
        this.dni = dni;
        this.password = password;
        this.role = role;
    }
    
    // Getters y Setters
    public int getId() { return id; }
    public void setId(int id) { this.id = id; }
    
    public String getNombre() { return nombre; }
    public void setNombre(String nombre) { this.nombre = nombre; }
    
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    
    public String getDni() { return dni; }
    public void setDni(String dni) { this.dni = dni; }
    
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
    
    public int getRole() { return role; }
    public void setRole(int role) { this.role = role; }
    
    public String getRoleName() {
        return role == 2 ? "ADMIN" : "USER";
    }
}