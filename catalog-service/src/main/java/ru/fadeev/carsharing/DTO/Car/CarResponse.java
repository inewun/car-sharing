package ru.fadeev.carsharing.DTO.Car;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Getter;
import lombok.Setter;
import ru.fadeev.carsharing.model.Car;
import ru.fadeev.carsharing.model.Tariff;

import java.math.BigDecimal;

@Getter
@Setter
public class CarResponse {
        private Long id;

        @JsonProperty("registration_number")
        private String registrationNumber;

        @JsonProperty("brand_model")
        private String brandModel;

        @JsonProperty("car_class_id")
        private Long carClassId;

        @JsonProperty("car_class")
        private String carClass;

        @JsonProperty("tech_status")
        private String techStatus;

        private Integer mileage;

        private BigDecimal latitude;

        private BigDecimal longitude;

        @JsonProperty("price_per_minute")
        private BigDecimal pricePerMinute;

        @JsonProperty("deposit_amount")
        private BigDecimal depositAmount;

        public static CarResponse fromEntities(Car car, Tariff tariff) {
            CarResponse response = new CarResponse();
            response.setId(car.getCarId());
            response.setRegistrationNumber(car.getRegistrationNumber());
            response.setBrandModel(car.getBrandModel());
            response.setTechStatus(car.getTechStatus());
            response.setMileage(car.getMileage());
            response.setLatitude(car.getLatitude());
            response.setLongitude(car.getLongitude());

            if(car.getCarClass() != null) {
                response.setCarClassId(car.getCarClass().getCarClassId());
                response.setCarClass(car.getCarClass().getCarClassName());
            }

            if(tariff != null) {
                response.setPricePerMinute(tariff.getPricePerMinute());
                response.setDepositAmount(tariff.getDepositAmount());
            }

            return response;
        }


}
