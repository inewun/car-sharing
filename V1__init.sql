DROP VIEW IF EXISTS cars_view;
DROP TABLE IF EXISTS audit_log, idempotency_keys, car_tech_status_history,
    booking_photos, payments, bookings, cars, users, tariffs, car_classes CASCADE;


CREATE TABLE car_classes (
    id          bigserial   PRIMARY KEY,
    car_class   varchar(20) NOT NULL
);

CREATE UNIQUE INDEX uq_car_classes_name ON car_classes (lower(car_class));


CREATE TABLE tariffs (
    id                  bigserial       PRIMARY KEY,
    car_class_id        bigint          NOT NULL REFERENCES car_classes (id),
    deposit_amount      numeric(10, 2)  NOT NULL,
    price_per_minute    numeric(10, 2)  NOT NULL,

    CONSTRAINT chk_tariffs_deposit CHECK (deposit_amount >= 0),
    CONSTRAINT chk_tariffs_price CHECK (price_per_minute > 0)
);

CREATE UNIQUE INDEX uq_tariffs_car_class_id ON tariffs (car_class_id);


CREATE TABLE users (
    id              bigserial       PRIMARY KEY,
    email           varchar(255)    NOT NULL,
    password_hash   varchar(255)    NOT NULL,
    full_name       varchar(150)    NOT NULL,
    birth_date      date            NOT NULL,
    phone           varchar(20)     NOT NULL,
    driver_license  varchar(20)     NOT NULL,
    role            varchar(20)     NOT NULL DEFAULT 'client',
    status          varchar(20)     NOT NULL DEFAULT 'active',

    CONSTRAINT chk_users_role CHECK (role IN ('client', 'support', 'admin')),
    CONSTRAINT chk_users_status CHECK (status IN ('active', 'blocked')),
    CONSTRAINT chk_users_birth_date CHECK (birth_date <= current_date - interval '18 years')
);

CREATE UNIQUE INDEX uq_users_email ON users (lower(email));
CREATE UNIQUE INDEX uq_users_phone ON users (phone);
CREATE UNIQUE INDEX uq_users_driver_license ON users (driver_license);


-- occupancy_status не хранится, он в cars_view
CREATE TABLE cars (
    id                  bigserial       PRIMARY KEY,
    registration_number varchar(9)      NOT NULL,
    brand_model         varchar(100)    NOT NULL,
    car_class_id        bigint          NOT NULL REFERENCES car_classes (id),
    tech_status         varchar(20)     NOT NULL DEFAULT 'ok',
    pending_maintenance boolean         NOT NULL DEFAULT false,
    mileage             integer         NOT NULL DEFAULT 0,
    latitude            numeric(9, 6)   NOT NULL,
    longitude           numeric(9, 6)   NOT NULL,
    location_updated_at timestamptz     NOT NULL DEFAULT now(),
    deleted_at          timestamptz,

    CONSTRAINT chk_cars_tech_status CHECK (tech_status IN ('ok', 'maintenance')),
    CONSTRAINT chk_cars_mileage CHECK (mileage >= 0),
    CONSTRAINT chk_cars_latitude CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_cars_longitude CHECK (longitude BETWEEN -180 AND 180)
);

CREATE UNIQUE INDEX uq_cars_registration_number
    ON cars (registration_number) WHERE deleted_at IS NULL;


-- Интервалы техстатусов для отчёта о загруженности автопарка:
-- cars.tech_status хранит только текущее значение
CREATE TABLE car_tech_status_history (
    id           bigserial   PRIMARY KEY,
    car_id       bigint      NOT NULL REFERENCES cars (id),
    tech_status  varchar(20) NOT NULL,
    started_at   timestamptz NOT NULL DEFAULT now(),
    ended_at     timestamptz,

    CONSTRAINT chk_cts_history_status CHECK (tech_status IN ('ok', 'maintenance')),
    CONSTRAINT chk_cts_history_interval CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE UNIQUE INDEX uq_cts_history_open
    ON car_tech_status_history (car_id) WHERE ended_at IS NULL;
CREATE INDEX idx_cts_history_car_period ON car_tech_status_history (car_id, started_at);


CREATE TABLE bookings (
    id                      bigserial       PRIMARY KEY,
    user_id                 bigint          NOT NULL REFERENCES users (id),
    car_id                  bigint          NOT NULL REFERENCES cars (id),
    booking_time            timestamptz     NOT NULL DEFAULT now(),
    start_time              timestamptz,
    end_time                timestamptz,
    status                  varchar(20)     NOT NULL DEFAULT 'active',

    -- снапшоты на момент бронирования: изменение тарифа не меняет цену
    -- идущей поездки, завершение не требует обращения к cars и tariffs
    car_brand_model         varchar(100)    NOT NULL,
    car_registration_number varchar(9)      NOT NULL,
    price_per_minute        numeric(10, 2)  NOT NULL,
    deposit_amount          numeric(10, 2)  NOT NULL,

    cancelled_at            timestamptz,
    cancelled_by            bigint          REFERENCES users (id),
    cancel_reason           varchar(30),

    CONSTRAINT chk_bookings_status CHECK (status IN ('active', 'finished', 'cancelled', 'incident')),
    CONSTRAINT chk_bookings_cancel_reason CHECK (cancel_reason IS NULL OR cancel_reason IN ('timeout', 'by_client', 'by_admin', 'car_failure', 'payment_declined')),
    CONSTRAINT chk_bookings_time_order CHECK (end_time IS NULL OR start_time IS NULL OR end_time >= start_time)
);

-- incident тоже удерживает авто: поездка ещё не закрыта
CREATE UNIQUE INDEX uq_bookings_active_car ON bookings (car_id) WHERE status IN ('active', 'incident');
CREATE UNIQUE INDEX uq_bookings_active_user ON bookings (user_id) WHERE status IN ('active', 'incident');
CREATE INDEX idx_bookings_pending_start ON bookings (booking_time) WHERE status = 'active' AND start_time IS NULL;


CREATE TABLE payments (
    id                  bigserial       PRIMARY KEY,
    booking_id          bigint          NOT NULL REFERENCES bookings (id),
    deposit_amount      numeric(10, 2)  NOT NULL,
    total_amount        numeric(10, 2),
    status              varchar(20)     NOT NULL DEFAULT 'pending',
    external_payment_id varchar(64),
    last_error          varchar(255),
    created_at          timestamptz     NOT NULL DEFAULT now(),

    CONSTRAINT chk_payments_status CHECK (status IN ('pending', 'deposit_held', 'paid', 'refunded', 'cancelled', 'manual_review')),
    CONSTRAINT chk_payments_amount CHECK (deposit_amount >= 0 AND (total_amount IS NULL OR total_amount >= 0))
);

CREATE UNIQUE INDEX uq_payments_booking_id ON payments (booking_id);
-- отсекает повторную обработку при дубле колбэка от шины
CREATE UNIQUE INDEX uq_payments_external_id ON payments (external_payment_id);
CREATE INDEX idx_payments_pending ON payments (created_at) WHERE status = 'pending';


-- полнота набора (6 ракурсов) проверяется в коде, CHECK видит только одну строку
CREATE TABLE booking_photos (
    id          bigserial       PRIMARY KEY,
    booking_id  bigint          NOT NULL REFERENCES bookings (id) ON DELETE CASCADE,
    kind        varchar(10)     NOT NULL,
    angle       varchar(20)     NOT NULL,
    path        varchar(100)    NOT NULL,

    CONSTRAINT chk_booking_photos_kind CHECK (kind IN ('start', 'end')),
    CONSTRAINT chk_booking_photos_angle CHECK (angle IN ('front', 'rear', 'left', 'right', 'interior', 'odometer'))
);

CREATE UNIQUE INDEX uq_booking_photos_slot ON booking_photos (booking_id, kind, angle);


-- повтор с тем же ключом возвращает сохранённый ответ, не выполняя операцию
CREATE TABLE idempotency_keys (
    key              varchar(64)  PRIMARY KEY,
    user_id          bigint       NOT NULL REFERENCES users (id),
    endpoint         varchar(100) NOT NULL,
    request_hash     varchar(64)  NOT NULL,
    response_status  smallint,
    response_body    jsonb,
    created_at       timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX idx_idempotency_keys_created_at ON idempotency_keys (created_at);


-- одна строка на одно изменённое поле, actor_id пустой у действий системы
CREATE TABLE audit_log (
    id           bigserial    PRIMARY KEY,
    occurred_at  timestamptz  NOT NULL DEFAULT now(),
    actor_id     bigint       REFERENCES users (id),
    actor_role   varchar(20),
    action_type  varchar(50)  NOT NULL,
    object_type  varchar(30)  NOT NULL,
    object_id    bigint       NOT NULL,
    field_name   varchar(50),
    old_value    varchar(255),
    new_value    varchar(255)
);

CREATE INDEX idx_audit_log_occurred_at ON audit_log (occurred_at);


CREATE VIEW cars_view AS
SELECT
    c.id,
    c.registration_number,
    c.brand_model,
    c.car_class_id,
    cc.car_class,
    c.tech_status,
    c.mileage,
    c.latitude,
    c.longitude,
    c.location_updated_at,
    t.price_per_minute,
    t.deposit_amount,
    CASE
        WHEN c.tech_status = 'maintenance' THEN 'busy'
        WHEN EXISTS (
            SELECT 1 FROM bookings b
            WHERE b.car_id = c.id AND b.status IN ('active', 'incident')
        ) THEN 'busy'
        ELSE 'free'
    END AS occupancy_status
FROM cars c
JOIN car_classes cc ON cc.id = c.car_class_id
-- LEFT JOIN: машина без назначенного тарифа не должна пропадать с карты
LEFT JOIN tariffs t ON t.car_class_id = c.car_class_id
WHERE c.deleted_at IS NULL;


-- Тестовые данные. Идентификаторы выдаёт база, поэтому связи
-- между таблицами ищутся по естественным ключам.

INSERT INTO car_classes (car_class) VALUES
    ('эконом'),
    ('комфорт'),
    ('бизнес'),
    ('спорт'),
    ('автоваз');

INSERT INTO tariffs (car_class_id, deposit_amount, price_per_minute)
SELECT cc.id, v.deposit, v.price
FROM (VALUES
    ('эконом',   500.00,  8.50),
    ('комфорт',  800.00, 12.00),
    ('бизнес',  1500.00, 20.00),
    ('спорт',   2500.00, 35.00),
    ('автоваз',  300.00,  6.00)
) AS v(class_name, deposit, price)
JOIN car_classes cc ON cc.car_class = v.class_name;

INSERT INTO users (email, password_hash, full_name, birth_date, phone, driver_license, role) VALUES
    ('ivan@mail.ru',  'hash1', 'Иванов Иван Иванович',    '1998-03-14', '+79001112233', '5905123456', 'client'),
    ('petr@mail.ru',  'hash2', 'Петров Пётр Петрович',    '1995-07-22', '+79004445566', '5905654321', 'client'),
    ('maria@mail.ru', 'hash3', 'Сидорова Мария Львовна',  '2000-11-05', '+79007778899', '5905111222', 'client'),
    ('support@cs.ru', 'hash4', 'Кузнецов Олег Павлович',  '1990-01-30', '+79009990011', '5905333444', 'support'),
    ('admin@cs.ru',   'hash5', 'Смирнова Анна Сергеевна', '1988-05-17', '+79002223344', '5905555666', 'admin');

INSERT INTO cars (registration_number, brand_model, car_class_id, latitude, longitude, mileage)
SELECT v.reg, v.model, cc.id, v.lat, v.lon, v.mileage
FROM (VALUES
    ('А123АА159', 'Kia Rio',            'эконом',  58.010374, 56.229398, 45200),
    ('А456АА159', 'Hyundai Solaris',    'эконом',  58.004512, 56.237841, 38900),
    ('В789ВВ159', 'Lada Granta',        'автоваз', 58.019233, 56.215674, 72300),
    ('В012ВВ159', 'Lada Vesta',         'автоваз', 57.996845, 56.251203, 61100),
    ('С345СС159', 'Volkswagen Polo',    'комфорт', 58.013927, 56.244019, 29800),
    ('С678СС159', 'Skoda Octavia',      'комфорт', 58.025610, 56.208335, 33400),
    ('Е901ЕЕ159', 'BMW 3 series',       'бизнес',  58.007188, 56.262947, 18200),
    ('Е234ЕЕ159', 'Mercedes-Benz C200', 'бизнес',  58.016455, 56.233712, 21700),
    ('К567КК159', 'Subaru BRZ',         'спорт',   58.002901, 56.221586, 12400),
    ('К890КК159', 'Audi TT',            'спорт',   58.021374, 56.249108,  9800)
) AS v(reg, model, class_name, lat, lon, mileage)
JOIN car_classes cc ON cc.car_class = v.class_name;

UPDATE cars SET tech_status = 'maintenance' WHERE registration_number = 'В789ВВ159';

INSERT INTO car_tech_status_history (car_id, tech_status)
SELECT id, tech_status FROM cars;
