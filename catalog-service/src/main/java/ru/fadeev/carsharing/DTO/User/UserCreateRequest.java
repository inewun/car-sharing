package ru.fadeev.carsharing.DTO.User;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.Setter;
import jakarta.validation.constraints.NotNull;
import ru.fadeev.carsharing.model.User;

import java.time.LocalDate;

@Getter
@Setter
public class UserCreateRequest {

    @Email
    @NotBlank(message="Email is required.")
    private String email;

    @Size(min=6, message="The password must be longer than 6 characters.")
    @NotBlank(message="Password is required.")
    private String password;

    @JsonProperty("full_name")
    @NotBlank(message="Name is required.")
    private String fullName;

    @JsonProperty("birth_date")
    @NotNull(message="Birth date is required.")
    private LocalDate birthDate;

    @NotBlank(message="Phone number is required.")
    private String phone;

    @JsonProperty("driver_license")
    @NotBlank(message="Driver license is required.")
    private String driverLicense;

    public User toNewUser() {
        User user = new User();
        user.setEmail(this.email);
        user.setPasswordHash(this.password);//сделать хеширование
        user.setFullName(this.fullName);
        user.setBirthDate(this.birthDate);
        user.setPhone(this.phone);
        user.setDriverLicense(this.driverLicense);
        return user;
    }
}
