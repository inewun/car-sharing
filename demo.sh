#!/usr/bin/env bash
set -u

BOOKING=http://localhost:8081
CATALOG=http://localhost:8080
PSQL="docker compose exec -T postgres psql -U postgres -d carsharing"

step() { echo; echo "──────── $1"; }

psql_do() {
    if $PSQL -c "$1" > /dev/null 2>&1; then
        echo "   готово"
    else
        echo "   ОШИБКА: нет доступа к базе"
        exit 1
    fi
}

call() {
    local method=$1 url=$2 user=${3:-} data=${4:-}
    local args=(-s -w '\n   → HTTP %{http_code}\n' -X "$method" "$url")
    [ -n "$user" ] && args+=(-H "X-User-Id: $user")
    [ -n "$data" ] && args+=(-H 'Content-Type: application/json' -d "$data")
    curl "${args[@]}"
}

if ! curl -sf "$BOOKING/health" > /dev/null; then
    echo "booking-service не отвечает на 8081"
    exit 1
fi

step "Исходное состояние: чистим поездки и платежи"
psql_do "DELETE FROM payments; DELETE FROM bookings;"

step "Проверка связи с базой"
call GET "$BOOKING/health"

if curl -sf "$CATALOG/api/cars" > /dev/null 2>&1; then
    step "Каталог: регистрация клиента"
    call POST "$CATALOG/api/users" "" \
        '{"email":"demo@mail.ru","password":"demo123","full_name":"Демонстрационный Клиент Иванович","birth_date":"1995-01-01","phone":"+79990001122","driver_license":"5905999888"}'

    step "Каталог: список машин"
    call GET "$CATALOG/api/cars"
else
    echo
    echo "   catalog-service на 8080 недоступен, шаги каталога пропущены"
fi

step "Машина 1 свободна"
call GET "$BOOKING/api/cars/1/status"

step "Клиент 1 начинает поездку на машине 1"
BOOKING_ID=$(curl -s -X POST "$BOOKING/api/bookings" \
    -H 'X-User-Id: 1' -H 'Content-Type: application/json' \
    -d '{"car_id": 1}' | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
echo "   создана бронь id=$BOOKING_ID"

step "Клиент 2 пытается взять ту же машину"
call POST "$BOOKING/api/bookings" 2 '{"car_id": 1}'

step "Клиент 1 пытается взять вторую машину"
call POST "$BOOKING/api/bookings" 1 '{"car_id": 2}'

step "Клиент 3 пытается взять машину на обслуживании"
call POST "$BOOKING/api/bookings" 3 '{"car_id": 10}'

step "Машина 1 теперь занята"
call GET "$BOOKING/api/cars/1/status"

step "Отматываем старт поездки на 17 минут назад"
psql_do "UPDATE bookings SET start_time = now() - interval '17 minutes' WHERE id = $BOOKING_ID;"

step "Клиент 1 завершает поездку"
call PATCH "$BOOKING/api/bookings/$BOOKING_ID/finish"

step "Повторное завершение той же поездки"
call PATCH "$BOOKING/api/bookings/$BOOKING_ID/finish"

step "История поездок клиента 1"
call GET "$BOOKING/api/bookings?user_id=1"

step "Два клиента одновременно занимают машину 2"
curl -s -o /dev/null -w '   клиент 3 → HTTP %{http_code}\n' -X POST "$BOOKING/api/bookings" \
    -H 'X-User-Id: 3' -H 'Content-Type: application/json' -d '{"car_id": 2}' &
curl -s -o /dev/null -w '   клиент 4 → HTTP %{http_code}\n' -X POST "$BOOKING/api/bookings" \
    -H 'X-User-Id: 4' -H 'Content-Type: application/json' -d '{"car_id": 2}' &
wait

echo
echo "──────── демонстрация завершена"
