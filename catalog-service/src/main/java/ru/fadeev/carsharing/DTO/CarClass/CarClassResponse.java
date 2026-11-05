package ru.fadeev.carsharing.DTO.CarClass;

import lombok.Getter;
import lombok.Setter;
import com.fasterxml.jackson.annotation.JsonProperty;
import ru.fadeev.carsharing.model.CarClass;

@Getter
@Setter
public class CarClassResponse {
    private Long id;

    @JsonProperty("car_class")
    private String carClassName;

    public static CarClassResponse fromCarClass(CarClass carClass) {
        CarClassResponse response = new CarClassResponse();
        response.setId(carClass.getCarClassId());
        response.setCarClassName(carClass.getCarClassName());

        return response;
    }
}
