package ru.fadeev.carsharing.DTO.User;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.Setter;
import ru.fadeev.carsharing.model.User;

import java.time.LocalDate;

@Getter
@Setter
public class UserResponse {

    private Long id;

    private String email;

    @JsonProperty("full_name")
    private String fullName;

    @JsonProperty("birth_date")
    private LocalDate birthDate;

    private String phone;

    @JsonProperty("driver_license")
    private String driverLicense;

    ///  Получаем сущность из БД и готовим JSON ответ.
    public static UserResponse fromUser(User user) {
        UserResponse response = new UserResponse();
        response.setId(user.getUserId());
        response.setEmail(user.getEmail());
        response.setFullName(user.getFullName());
        response.setBirthDate(user.getBirthDate());
        response.setPhone(user.getPhone());
        response.setDriverLicense(user.getDriverLicense());
        return response;
    }
}