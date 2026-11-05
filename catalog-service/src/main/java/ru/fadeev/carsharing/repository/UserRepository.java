package ru.fadeev.carsharing.repository;


import org.springframework.data.jpa.repository.JpaRepository;
import ru.fadeev.carsharing.model.User;

/// Интерфейс объединяющий сущности и БД. Наследует JpaRepository, генерирующий SQL запросы
public interface UserRepository extends JpaRepository<User, Long> {

}
