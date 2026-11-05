package ru.fadeev.carsharing.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import ru.fadeev.carsharing.model.Car;
import ru.fadeev.carsharing.model.CarClass;

import java.util.List;

/// Интерфейс объединяющий сущности и БД. Наследует JpaRepository, генерирующий SQL запросы
public interface CarRepository extends JpaRepository<Car, Long>{

    List<Car> findByDeletedAtIsNull();

    List<Car> findByDeletedAtIsNullAndCarClassCarClassId(Long classId);

}

