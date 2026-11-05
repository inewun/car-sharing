package ru.fadeev.carsharing.exception;

public class TooYoungException extends RuntimeException {
    public TooYoungException(String message) { super(message); }
}