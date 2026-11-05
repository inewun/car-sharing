package ru.fadeev.carsharing.service;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import ru.fadeev.carsharing.DTO.Car.CarResponse;
import ru.fadeev.carsharing.DTO.CarClass.CarClassResponse;
import ru.fadeev.carsharing.DTO.Tariff.TariffResponse;
import ru.fadeev.carsharing.exception.TariffNotFoundException;
import ru.fadeev.carsharing.model.Car;
import ru.fadeev.carsharing.model.CarClass;
import ru.fadeev.carsharing.model.Tariff;
import ru.fadeev.carsharing.repository.CarClassRepository;
import ru.fadeev.carsharing.repository.CarRepository;
import ru.fadeev.carsharing.repository.TariffRepository;

import java.util.List;

@Service
@RequiredArgsConstructor
public class CarService {

    private final CarRepository carRepository;
    private final CarClassRepository carClassRepository;
    private final TariffRepository tariffRepository;

    @Transactional(readOnly = true)
    public List<CarClassResponse> getClasses(){
        List<CarClass> carClasses = carClassRepository.findAll();

        return carClasses.stream().map(CarClassResponse::fromCarClass).toList();
    }

    @Transactional(readOnly = true)
    public TariffResponse getTariffs(Long carClassId){
        Tariff tariff = tariffRepository.findByCarClassCarClassId(carClassId)
                .orElseThrow(() -> new TariffNotFoundException("Tariff not found!"));

        return TariffResponse.fromTariff(tariff);
    }

    @Transactional(readOnly = true)
    public List<CarResponse> getCars(Long carClassId){
        List<Tariff> tariffs = tariffRepository.findAll();
        List<Car> cars;
        if (carClassId == null) {
            cars =  carRepository.findByDeletedAtIsNull();
        } else{
            cars = carRepository.findByDeletedAtIsNullAndCarClassCarClassId(carClassId);
        }

        return cars.stream().map(
               car ->  {
                    Tariff matchingTariff = tariffs.stream()
                            .filter(t -> t.getCarClass().getCarClassId().
                                    equals(car.getCarClass().getCarClassId()))
                            .findFirst()
                            .orElse(null);

                    return CarResponse.fromEntities(car, matchingTariff);
               }
        ).toList();

    }

}
