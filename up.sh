#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"

BOLD=$'\e[1m'; DIM=$'\e[2m'; GREEN=$'\e[32m'; RED=$'\e[31m'
CYAN=$'\e[36m'; OFF=$'\e[0m'

BOOKING_PID=""
CATALOG_PID=""
CLEANED=0

cleanup() {
    [ "$CLEANED" = 1 ] && return
    CLEANED=1
    echo
    printf '%sОстановка сервисов%s\n' "$BOLD" "$OFF"
    for pid in "$CATALOG_PID" "$BOOKING_PID"; do
        [ -n "$pid" ] || continue
        pkill -P "$pid" 2>/dev/null
        kill "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    printf '%sБаза продолжает работать, остановка: docker compose down%s\n' "$DIM" "$OFF"
}

trap cleanup EXIT
trap 'exit 130' INT TERM

wait_for() {
    local name=$1 url=$2 tries=$3
    for _ in $(seq "$tries"); do
        if curl -sf "$url" > /dev/null 2>&1; then
            printf '%s✓%s %s отвечает\n' "$GREEN" "$OFF" "$name"
            return 0
        fi
        sleep 1
    done
    printf '%s✗%s %s не ответил за %d с, см. лог\n' "$RED" "$OFF" "$name" "$tries"
    return 1
}

printf '%sЗапуск сервисов каршеринга%s\n' "$BOLD" "$OFF"

printf '\n%s[1/3]%s PostgreSQL в контейнере\n' "$CYAN" "$OFF"
if docker compose up -d > /dev/null 2>&1; then
    printf '%s✓%s Контейнер carsharing-db работает\n' "$GREEN" "$OFF"
else
    printf '%s✗%s Нет доступа к docker\n' "$RED" "$OFF"
    printf '%sТребуется перелогиниться или выполнить newgrp docker%s\n' "$DIM" "$OFF"
    exit 1
fi

printf '\n%s[2/3]%s booking-service, Rust, порт 8081\n' "$CYAN" "$OFF"
printf '%sСборка и запуск, вывод в booking.log%s\n' "$DIM" "$OFF"
(cd booking-service && exec cargo run > ../booking.log 2>&1) &
BOOKING_PID=$!
wait_for booking-service http://localhost:8081/health 90

printf '\n%s[3/3]%s catalog-service, Java, порт 8080\n' "$CYAN" "$OFF"
printf '%sСборка Maven и запуск, вывод в catalog.log%s\n' "$DIM" "$OFF"
(cd catalog-service && exec mvn -q spring-boot:run > ../catalog.log 2>&1) &
CATALOG_PID=$!
wait_for catalog-service http://localhost:8080/api/classes 300

printf '\n%sВсё поднято%s\n' "$BOLD" "$OFF"
printf 'booking-service   http://localhost:8081\n'
printf 'catalog-service   http://localhost:8080\n'
printf 'база              postgres://localhost:5432/carsharing\n'
printf '\n%s./demo.sh                        запуск демонстрации%s\n' "$DIM" "$OFF"
printf '%stail -f booking.log catalog.log  просмотр логов%s\n' "$DIM" "$OFF"
printf '%sCtrl+C                           остановка обоих сервисов%s\n' "$DIM" "$OFF"

[ "${1:-}" = "demo" ] && { echo; ./demo.sh; }

wait
