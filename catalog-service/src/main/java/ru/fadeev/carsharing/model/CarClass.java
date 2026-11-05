package ru.fadeev.carsharing.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

// Справочник классов авто
@Entity
@Table(name="car_classes")
@Setter
@Getter
public class CarClass {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name="id")
    private Long carClassId;

    @Column(name = "car_class", nullable = false)
    private String carClassName;
}
