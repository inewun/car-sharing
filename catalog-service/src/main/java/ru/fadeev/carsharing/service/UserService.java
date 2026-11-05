package ru.fadeev.carsharing.service;

import org.springframework.transaction.annotation.Transactional;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import ru.fadeev.carsharing.DTO.User.UserCreateRequest;
import ru.fadeev.carsharing.DTO.User.UserResponse;
import ru.fadeev.carsharing.exception.TooYoungException;
import ru.fadeev.carsharing.model.User;
import ru.fadeev.carsharing.repository.UserRepository;

import java.time.LocalDate;
import java.time.Period;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional
    public UserResponse createUser(UserCreateRequest request) {
        int age = Period.between(request.getBirthDate(), LocalDate.now()).getYears();
        if(age < 18){
            throw new TooYoungException("Age must be at least 18 years.");
        }

        User user = request.toNewUser();

        user.setPasswordHash(passwordEncoder.encode(request.getPassword()));

        user.setRole("client");
        user.setStatus("active");

        User savedUser = userRepository.save(user);

        return UserResponse.fromUser(savedUser);
    }
}
