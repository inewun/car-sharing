package ru.fadeev.carsharing.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import ru.fadeev.carsharing.model.Tariff;

import java.util.Optional;

/// Интерфейс объединяющий сущности и БД. Наследует JpaRepository, генерирующий SQL запросы
public interface TariffRepository extends JpaRepository<Tariff, Long> {
    Optional<Tariff> findByCarClassCarClassId(Long carClassId);
}
