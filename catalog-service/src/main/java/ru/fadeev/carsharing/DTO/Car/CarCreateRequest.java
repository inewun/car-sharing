package ru.fadeev.carsharing.DTO.Car;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Getter;
import lombok.Setter;
import ru.fadeev.carsharing.model.Car;
import ru.fadeev.carsharing.model.CarClass;

import java.math.BigDecimal;

@Getter
@Setter
public class CarCreateRequest {

    @NotBlank(message="Registration number is required.")
    @JsonProperty("registration_number")
    private String registrationNumber;

    @NotBlank(message="Brand model is required.")
    @JsonProperty("brand_model")
    private String brandModel;

    @NotNull(message="Car class id is required.")
    @JsonProperty("car_class_id")
    private Long carClassId;

    @NotBlank(message="Tech status is required.")
    @JsonProperty("tech_status")
    private String techStatus;

    @NotNull(message="Mileage is required.")
    private Integer mileage;

    @NotNull(message="Latitude is required.")
    private BigDecimal latitude;

    @NotNull(message="Longitude is required.")
    private BigDecimal longitude;

    public Car toNewCar() {
        Car car = new Car();
        car.setRegistrationNumber(this.registrationNumber);
        car.setBrandModel(this.brandModel);
        car.setTechStatus(this.techStatus);
        car.setMileage(this.mileage);
        car.setLatitude(this.latitude);
        car.setLongitude(this.longitude);

        return car;
    }
}
