package ru.fadeev.carsharing.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import ru.fadeev.carsharing.DTO.Car.CarResponse;
import ru.fadeev.carsharing.DTO.CarClass.CarClassResponse;
import ru.fadeev.carsharing.DTO.Tariff.TariffResponse;
import ru.fadeev.carsharing.service.CarService;


import java.util.List;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class CarController {
    private final CarService carService;

    @GetMapping("/classes")
    public List<CarClassResponse> getCarClasses() {
        return carService.getClasses();
    }

    @GetMapping("/cars")
    public List<CarResponse> getCars(@RequestParam(name="class_id", required = false) Long carClassId) {
        return carService.getCars(carClassId);
    }

    @GetMapping("/tariffs/{class_id}")
    public TariffResponse getTariffs(@PathVariable("class_id") Long carClassId) {
        return carService.getTariffs(carClassId);
    }
}
