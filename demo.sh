#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"

BOOKING=http://localhost:8081
CATALOG=http://localhost:8080
PSQL="docker compose exec -T postgres psql -U postgres -d carsharing"

BOLD=$'\e[1m'; DIM=$'\e[2m'; GREEN=$'\e[32m'; RED=$'\e[31m'
CYAN=$'\e[36m'; OFF=$'\e[0m'

N=0
FAILED=0
LAST_BODY=""
command -v jq > /dev/null && HAVE_JQ=1 || HAVE_JQ=0

prep() {
    printf '\n%s%s▌ Подготовка. %s%s\n' "$BOLD" "$DIM" "$1" "$OFF"
    printf '%s   Назначение: %s%s\n' "$DIM" "$2" "$OFF"
}

check() {
    N=$((N + 1))
    printf '\n%s%s▌ %d. %s%s\n' "$BOLD" "$CYAN" "$N" "$1" "$OFF"
    printf '%s   Проверка:   %s%s\n' "$DIM" "$2" "$OFF"
    printf '%s   Где:        %s%s\n' "$DIM" "$3" "$OFF"
    printf '%s   Механика:   %s%s\n' "$DIM" "$4" "$OFF"
    printf '%s   Ожидание:   %s%s\n' "$DIM" "$5" "$OFF"
    return 0
}

psql_do() {
    printf '%s   SQL:        %s%s\n' "$DIM" "$1" "$OFF"
    if $PSQL -c "$1" > /dev/null 2>&1; then
        printf '   %s✓ Готово%s\n' "$GREEN" "$OFF"
    else
        printf '   %s✗ Нет доступа к базе%s\n' "$RED" "$OFF"
        exit 1
    fi
}

req() {
    local method=$1 url=$2 expect=$3 user=${4:-} data=${5:-} filter=${6:-.}

    printf '%s   Запрос:     %s %s%s\n' "$DIM" "$method" "$url" "$OFF"
    [ -n "$user" ] && printf '%s   Заголовок:  X-User-Id: %s%s\n' "$DIM" "$user" "$OFF"
    [ -n "$data" ] && printf '%s   Тело:       %s%s\n' "$DIM" "$data" "$OFF"

    local args=(-s -w $'\n%{http_code}' -X "$method" "$url")
    [ -n "$user" ] && args+=(-H "X-User-Id: $user")
    [ -n "$data" ] && args+=(-H 'Content-Type: application/json' -d "$data")

    local raw code
    raw=$(curl "${args[@]}")
    code=${raw##*$'\n'}
    LAST_BODY=${raw%$'\n'*}

    if [ "$code" = "$expect" ]; then
        printf '   %s✓ Ответ HTTP %s, совпадает с ожидаемым%s\n' "$GREEN" "$code" "$OFF"
    else
        printf '   %s✗ Ответ HTTP %s, ожидался %s%s\n' "$RED" "$code" "$expect" "$OFF"
        FAILED=$((FAILED + 1))
    fi

    if [ -n "$LAST_BODY" ]; then
        if [ "$HAVE_JQ" = 1 ]; then
            echo "$LAST_BODY" | jq -r "$filter" 2>/dev/null | sed 's/^/     /'
        else
            echo "$LAST_BODY" | sed 's/^/     /'
        fi
    fi
    return 0
}

printf '%s╔══════════════════════════════════════════════════════════╗%s\n' "$BOLD" "$OFF"
printf '%s║  Каршеринг                                               ║%s\n' "$BOLD" "$OFF"
printf '%s║  booking-service  Rust, порт 8081, поездки и платежи     ║%s\n' "$BOLD" "$OFF"
printf '%s║  catalog-service  Java, порт 8080, клиенты и автопарк    ║%s\n' "$BOLD" "$OFF"
printf '%s║  Общая база PostgreSQL, схема в V1__init.sql             ║%s\n' "$BOLD" "$OFF"
printf '%s╚══════════════════════════════════════════════════════════╝%s\n' "$BOLD" "$OFF"

if ! curl -sf "$BOOKING/health" > /dev/null; then
    echo "booking-service не отвечает на 8081"
    exit 1
fi

CATALOG_UP=0
curl -sf "$CATALOG/api/classes" > /dev/null 2>&1 && CATALOG_UP=1

prep "Очистка данных прошлого прогона" \
     "Повторяемость результата при каждом запуске"
psql_do "DELETE FROM payments; DELETE FROM bookings; DELETE FROM users WHERE email = 'demo@mail.ru';"

check "Связь сервиса бронирования с базой" \
      "Сервис поднят, соединение с PostgreSQL живое" \
      "booking-service :8081" \
      "SELECT 1 через пул соединений sqlx" \
      "HTTP 200, статус сервиса ok и статус базы ok"
req GET "$BOOKING/health" 200 "" "" '"Сервис \(.status), база \(.db)"'

if [ "$CATALOG_UP" = 1 ]; then
    check "Справочник классов" \
          "Клиент может узнать доступные классы автомобилей" \
          "catalog-service :8080, таблица car_classes" \
          "SELECT id, car_class FROM car_classes" \
          "HTTP 200 и пять классов из схемы: эконом, комфорт, бизнес, спорт, автоваз"
    req GET "$CATALOG/api/classes" 200 "" "" '.[] | "\(.id)  \(.car_class)"'

    check "Регистрация клиента" \
          "Клиент создаётся, пароль не хранится в открытом виде" \
          "catalog-service :8080, таблица users" \
          "INSERT INTO users (email, password_hash, full_name, birth_date, phone, driver_license, role, status)" \
          "HTTP 201, присвоенный id, пароль в ответе отсутствует"
    req POST "$CATALOG/api/users" 201 "" \
        '{"email":"demo@mail.ru","password":"demo123","full_name":"Иванов Иван Иванович","birth_date":"1995-01-01","phone":"+79990001122","driver_license":"5905999888"}' \
        '"id=\(.id)  \(.full_name)  \(.email)"'

    check "Повторная регистрация на ту же почту" \
          "Дубликат клиента создать нельзя" \
          "catalog-service :8080, индекс uq_users_email по lower(email)" \
          "Тот же INSERT нарушает уникальный индекс, Postgres отклоняет вставку" \
          "HTTP 409, сообщение о занятой почте"
    req POST "$CATALOG/api/users" 409 "" \
        '{"email":"demo@mail.ru","password":"demo123","full_name":"Иванов Иван Иванович","birth_date":"1995-01-01","phone":"+79990001122","driver_license":"5905999888"}' \
        '"\(.error): \(.message)"'

    check "Регистрация клиента младше 18 лет" \
          "Возрастное ограничение соблюдается" \
          "catalog-service :8080, поле users.birth_date" \
          "Возраст считается от birth_date до вставки, в схеме дублируется CHECK-ограничением" \
          "HTTP 400, сообщение о возрасте"
    req POST "$CATALOG/api/users" 400 "" \
        '{"email":"kid@mail.ru","password":"demo123","full_name":"Петров Пётр Петрович","birth_date":"2015-01-01","phone":"+79990009988","driver_license":"5905111000"}' \
        '"\(.error): \(.message)"'

    check "Список машин с фильтром по классу" \
          "Каталог фильтрует автопарк и подставляет тариф" \
          "catalog-service :8080, таблицы cars, car_classes, tariffs" \
          "SELECT ... FROM cars JOIN car_classes JOIN tariffs ON car_class_id WHERE deleted_at IS NULL AND car_class_id = 1" \
          "HTTP 200, только класс эконом, у каждой машины цена минуты и залог"
    req GET "$CATALOG/api/cars?class_id=1" 200 "" "" \
        '.[] | "\(.registration_number)  \(.brand_model)  \(.price_per_minute) руб/мин  залог \(.deposit_amount)"'
else
    printf '\n%sКаталог на 8080 не запущен, его проверки пропущены%s\n' "$DIM" "$OFF"
fi

check "Статус свободной машины" \
      "Незанятый автомобиль определяется верно" \
      "booking-service :8081, таблицы cars и bookings" \
      "SELECT c.id, b.id FROM cars c LEFT JOIN bookings b ON b.car_id = c.id AND b.status IN ('active','incident')" \
      "HTTP 200, признак свободна"
req GET "$BOOKING/api/cars/1/status" 200 "" "" \
    'if .occupied then "Занята, бронь \(.booking_id)" else "Свободна" end'

check "Начало поездки" \
      "Бронь создаётся, цена фиксируется на момент старта" \
      "booking-service :8081, таблица bookings" \
      "SELECT ... FROM cars c JOIN tariffs t WHERE c.id = \$1 FOR UPDATE OF c, затем INSERT INTO bookings с копией тарифа" \
      "HTTP 201, номер брони и цена минуты, скопированная из тарифа"
req POST "$BOOKING/api/bookings" 201 1 '{"car_id": 1}' \
    '"Бронь \(.id)  \(.car_brand_model) \(.car_registration_number)  \(.price_per_minute) руб/мин"'

if [ "$HAVE_JQ" = 1 ]; then
    BOOKING_ID=$(echo "$LAST_BODY" | jq -r .id)
else
    BOOKING_ID=$(echo "$LAST_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
fi

check "Вторая бронь на занятую машину" \
      "Одну машину нельзя занять дважды" \
      "booking-service :8081, индекс uq_bookings_active_car" \
      "INSERT INTO bookings нарушает UNIQUE (car_id) WHERE status IN ('active','incident')" \
      "HTTP 409, ошибка car_already_booked"
req POST "$BOOKING/api/bookings" 409 2 '{"car_id": 1}' '"\(.error): \(.message)"'

check "Вторая бронь у того же клиента" \
      "У клиента не может быть двух поездок одновременно" \
      "booking-service :8081, индекс uq_bookings_active_user" \
      "INSERT INTO bookings нарушает UNIQUE (user_id) WHERE status IN ('active','incident')" \
      "HTTP 409, ошибка active_booking_exists"
req POST "$BOOKING/api/bookings" 409 1 '{"car_id": 2}' '"\(.error): \(.message)"'

check "Бронь машины на обслуживании" \
      "Неисправный автомобиль недоступен для поездки" \
      "booking-service :8081, поле cars.tech_status" \
      "SELECT вернул tech_status = 'maintenance', INSERT не выполняется" \
      "HTTP 409, ошибка car_not_available"
req POST "$BOOKING/api/bookings" 409 3 '{"car_id": 10}' '"\(.error): \(.message)"'

check "Статус занятой машины" \
      "Занятость обновилась после создания брони" \
      "booking-service :8081, таблицы cars и bookings" \
      "Тот же LEFT JOIN, что в проверке 7, активная бронь найдена" \
      "HTTP 200, признак занята и номер брони из проверки 8"
req GET "$BOOKING/api/cars/1/status" 200 "" "" \
    'if .occupied then "Занята, бронь \(.booking_id)" else "Свободна" end'

prep "Сдвиг времени старта на 17 минут назад" \
     "Реальная длительность поездки здесь секунды, счёт был бы неинформативным"
psql_do "UPDATE bookings SET start_time = now() - interval '17 minutes' WHERE id = $BOOKING_ID;"

check "Завершение поездки и расчёт стоимости" \
      "Поездка закрывается, сумма считается по зафиксированной цене" \
      "booking-service :8081, таблицы bookings и payments" \
      "SELECT ... FOR UPDATE, UPDATE bookings SET end_time, status='finished', INSERT INTO payments, одна транзакция" \
      "HTTP 200, 17 минут по 8.50 руб, итого 144.50 руб"
req PATCH "$BOOKING/api/bookings/$BOOKING_ID/finish" 200 "" "" \
    '"\(.duration_minutes) мин по цене из брони  →  \(.total_amount) руб"'

check "Повторное завершение поездки" \
      "Двойное списание невозможно" \
      "booking-service :8081, поле bookings.status" \
      "SELECT ... FOR UPDATE вернул status = 'finished', обработчик выходит до расчёта" \
      "HTTP 409, ошибка booking_not_active"
req PATCH "$BOOKING/api/bookings/$BOOKING_ID/finish" 409 "" "" '"\(.error): \(.message)"'

check "История поездок клиента" \
      "Завершённая поездка попала в историю вместе с суммой" \
      "booking-service :8081, таблицы bookings и payments" \
      "SELECT ... FROM bookings b LEFT JOIN payments p ON p.booking_id = b.id WHERE b.user_id = \$1 ORDER BY b.booking_time DESC" \
      "HTTP 200, одна поездка со статусом finished и суммой 144.50"
req GET "$BOOKING/api/bookings?user_id=1" 200 "" "" \
    '.[] | "Бронь \(.id)  \(.car_registration_number)  \(.status)  итого \(.total_amount // "не завершена")"'

N=$((N + 1))
printf '\n%s%s▌ %d. Одновременные брони на одну машину%s\n' "$BOLD" "$CYAN" "$N" "$OFF"
printf '%s   Проверка:   Защита выдерживает параллельные запросы, а не только последовательные%s\n' "$DIM" "$OFF"
printf '%s   Где:        booking-service :8081, индекс uq_bookings_active_car%s\n' "$DIM" "$OFF"
printf '%s   Механика:   Два INSERT INTO bookings уходят одновременно, уникальный индекс пропускает один%s\n' "$DIM" "$OFF"
printf '%s   Ожидание:   Один ответ 201, другой 409, победитель меняется от запуска к запуску%s\n' "$DIM" "$OFF"
curl -s -o /dev/null -w "     Клиент 3 → HTTP %{http_code}\n" -X POST "$BOOKING/api/bookings" \
    -H 'X-User-Id: 3' -H 'Content-Type: application/json' -d '{"car_id": 2}' &
curl -s -o /dev/null -w "     Клиент 4 → HTTP %{http_code}\n" -X POST "$BOOKING/api/bookings" \
    -H 'X-User-Id: 4' -H 'Content-Type: application/json' -d '{"car_id": 2}' &
wait

echo
if [ "$FAILED" = 0 ]; then
    printf '%s%s Все %d проверок дали ожидаемый результат %s\n' "$BOLD" "$GREEN" "$N" "$OFF"
else
    printf '%s%s Проверок: %d, расхождений с ожидаемым: %d %s\n' "$BOLD" "$RED" "$N" "$FAILED" "$OFF"
fi
echo
