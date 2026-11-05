package ru.fadeev.carsharing.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import ru.fadeev.carsharing.model.CarClass;

/// Интерфейс объединяющий сущности и БД. Наследует JpaRepository, генерирующий SQL запросы
public interface CarClassRepository extends JpaRepository<CarClass, Long> {
}
