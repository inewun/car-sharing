package ru.fadeev.carsharing.model;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.math.BigDecimal;

@Entity
@Table(name="tariffs")
@Setter
@Getter
public class Tariff {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name="id")
    private Long tariffId;

    // Справочник классов авто
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "car_class_id", nullable = false)
    private CarClass carClass;

    @Column(name = "deposit_amount", nullable = false)
    private BigDecimal depositAmount;

    @Column(name = "price_per_minute", nullable = false)
    private BigDecimal pricePerMinute;

}
