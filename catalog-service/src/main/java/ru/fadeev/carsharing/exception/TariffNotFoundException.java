package ru.fadeev.carsharing.exception;

public class TariffNotFoundException extends RuntimeException{
    public TariffNotFoundException(String message) { super(message); }
}
