package ru.fadeev.carsharing.DTO.Tariff;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Getter;
import lombok.Setter;
import ru.fadeev.carsharing.model.Tariff;

import java.math.BigDecimal;

@Getter
@Setter
public class TariffResponse {

    @JsonProperty("class_id")
    private Long classId;

    @JsonProperty("price_per_minute")
    private BigDecimal pricePerMinute;

    @JsonProperty("deposit_amount")
    private BigDecimal depositAmount;

    public static TariffResponse fromTariff(Tariff tariff) {
        TariffResponse response = new TariffResponse();
        response.setClassId(tariff.getCarClass().getCarClassId());
        response.setPricePerMinute(tariff.getPricePerMinute());
        response.setDepositAmount(tariff.getDepositAmount());

        return response;
    }
}
