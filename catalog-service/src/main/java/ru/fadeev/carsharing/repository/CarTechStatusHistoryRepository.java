package ru.fadeev.carsharing.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import ru.fadeev.carsharing.model.CarTechStatusHistory;

/// Интерфейс объединяющий сущности и БД. Наследует JpaRepository, генерирующий SQL запросы
public interface CarTechStatusHistoryRepository extends JpaRepository<CarTechStatusHistory, Long> {
}
