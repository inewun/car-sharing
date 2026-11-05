package ru.fadeev.carsharing.model;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(name="cars")
@Setter
@Getter
public class Car {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name="id")
    private Long carId;

    // Справочник классов
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "car_class_id", nullable = false)
    private CarClass carClass;

    @Column(name = "registration_number", nullable = false)
    private String registrationNumber;

    @Column(name = "brand_model", nullable = false)
    private String brandModel;

    @Column(name = "tech_status", nullable = false)
    private String techStatus;

    @Column(name = "pending_maintenance", nullable = false)
    private Boolean pendingMaintenance;

    @Column(name = "mileage", nullable = false)
    private Integer mileage;

    @Column(name = "latitude", nullable = false)
    private BigDecimal latitude;

    @Column(name = "longitude", nullable = false)
    private BigDecimal longitude;

    @Column(name = "location_updated_at", nullable = false)
    private OffsetDateTime locationUpdatedAt;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;

}
