use axum::{
    Json, Router,
    extract::{FromRequestParts, Path, Query, State},
    http::{StatusCode, request::Parts},
    response::{IntoResponse, Response},
    routing::{get, patch, post},
};
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::{PgPool, postgres::PgPoolOptions};
use std::env;

#[tokio::main]
async fn main() {
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt::init();

    let database_url = env::var("DATABASE_URL").expect("The DATABASE_URL variable is not set");
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to connect to the database");

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/bookings", post(create_booking).get(list_bookings))
        .route("/api/bookings/{id}", get(get_booking))
        .route("/api/bookings/{id}/finish", patch(finish_booking))
        .route("/api/cars/{id}/status", get(car_status))
        .with_state(pool);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8081")
        .await
        .expect("Failed to occupy port 8081");

    tracing::info!("listening on {}", listener.local_addr().unwrap());

    axum::serve(listener, app).await.unwrap();
}

async fn health(State(pool): State<PgPool>) -> (StatusCode, Json<Value>) {
    match sqlx::query_scalar!(r#"SELECT 1 AS "one""#)
        .fetch_one(&pool)
        .await
    {
        Ok(_) => (StatusCode::OK, Json(json!({"status": "ok", "db": "ok"}))),
        Err(e) => {
            tracing::error!("Database unavailable: {e}");
            (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"status": "degraded", "db": "down"})),
            )
        }
    }
}

enum AppError {
    CarNotFound,
    CarNotAvailable,
    CarAlreadyBooked,
    ActiveBookingExists,
    BookingNotFound,
    BookingNotActive,
    MissingUserId,
    Internal,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            AppError::CarNotFound => (StatusCode::NOT_FOUND, "car_not_found", "Машина не найдена"),
            AppError::CarNotAvailable => (
                StatusCode::CONFLICT,
                "car_not_available",
                "Машина на обслуживании",
            ),
            AppError::CarAlreadyBooked => (
                StatusCode::CONFLICT,
                "car_already_booked",
                "Машина уже занята",
            ),
            AppError::ActiveBookingExists => (
                StatusCode::CONFLICT,
                "active_booking_exists",
                "У клиента есть активная поездка",
            ),
            AppError::BookingNotFound => (
                StatusCode::NOT_FOUND,
                "booking_not_found",
                "Поездка не найдена",
            ),
            AppError::BookingNotActive => (
                StatusCode::CONFLICT,
                "booking_not_active",
                "Поездка уже завершена",
            ),
            AppError::MissingUserId => (
                StatusCode::BAD_REQUEST,
                "missing_user_id",
                "Не передан заголовок X-User-Id",
            ),
            AppError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal_error",
                "Внутренняя ошибка",
            ),
        };

        (status, Json(json!({"error": code, "message": message}))).into_response()
    }
}

impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        tracing::error!("database error: {err}");
        AppError::Internal
    }
}

struct UserId(i64);

impl<S: Send + Sync> FromRequestParts<S> for UserId {
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .headers
            .get("X-User-Id")
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<i64>().ok())
            .map(UserId)
            .ok_or(AppError::MissingUserId)
    }
}

#[derive(Deserialize)]
struct CreateBookingRequest {
    car_id: i64,
}

#[derive(Serialize)]
struct BookingResponse {
    id: i64,
    user_id: i64,
    car_id: i64,
    status: String,
    start_time: Option<DateTime<Utc>>,
    car_brand_model: String,
    car_registration_number: String,
    price_per_minute: Decimal,
    deposit_amount: Decimal,
}

fn booking_conflict(err: sqlx::Error) -> AppError {
    if let sqlx::Error::Database(ref db) = err {
        match db.constraint() {
            Some("uq_bookings_active_car") => return AppError::CarAlreadyBooked,
            Some("uq_bookings_active_user") => return AppError::ActiveBookingExists,
            _ => {}
        }
    }

    AppError::from(err)
}

async fn create_booking(
    State(pool): State<PgPool>,
    UserId(user_id): UserId,
    Json(body): Json<CreateBookingRequest>,
) -> Result<(StatusCode, Json<BookingResponse>), AppError> {
    let mut tx = pool.begin().await?;
    let car = sqlx::query!(
        // language=SQL
        r#"
        SELECT c.id, c.brand_model, c.registration_number, c.tech_status,
               t.price_per_minute, t.deposit_amount
        FROM cars c
        JOIN tariffs t ON t.car_class_id = c.car_class_id
        WHERE c.id = $1 AND c.deleted_at IS NULL
        FOR UPDATE OF c
        "#,
        body.car_id
    )
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::CarNotFound)?;

    if car.tech_status != "ok" {
        return Err(AppError::CarNotAvailable);
    }

    let booking = sqlx::query!(
        r#"INSERT INTO bookings (
            user_id, car_id, start_time,
            car_brand_model, car_registration_number,
            price_per_minute, deposit_amount
        )
        VALUES ($1, $2, now(), $3, $4, $5, $6)
        RETURNING id, status, start_time
        "#,
        user_id,
        car.id,
        car.brand_model,
        car.registration_number,
        car.price_per_minute,
        car.deposit_amount
    )
    .fetch_one(&mut *tx)
    .await
    .map_err(booking_conflict)?;

    tx.commit().await?;

    Ok((
        StatusCode::CREATED,
        Json(BookingResponse {
            id: booking.id,
            user_id,
            car_id: car.id,
            status: booking.status,
            start_time: booking.start_time,
            car_brand_model: car.brand_model,
            car_registration_number: car.registration_number,
            price_per_minute: car.price_per_minute,
            deposit_amount: car.deposit_amount,
        }),
    ))
}

#[derive(Serialize)]
struct FinishResponse {
    id: i64,
    car_id: i64,
    start_time: DateTime<Utc>,
    end_time: DateTime<Utc>,
    duration_minutes: i64,
    total_amount: Decimal,
}

async fn finish_booking(
    State(pool): State<PgPool>,
    Path(booking_id): Path<i64>,
) -> Result<Json<FinishResponse>, AppError> {
    let mut tx = pool.begin().await?;

    let booking = sqlx::query!(
        r#"
        SELECT id, car_id, booking_time, start_time, status,
            price_per_minute, deposit_amount
        FROM bookings
        WHERE id = $1
        FOR UPDATE
        "#,
        booking_id
    )
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::BookingNotFound)?;

    if booking.status != "active" {
        return Err(AppError::BookingNotActive);
    }

    let start_time = booking.start_time.unwrap_or(booking.booking_time);
    let end_time = Utc::now();
    let seconds = (end_time - start_time).num_seconds().max(0);
    let duration_minutes = ((seconds + 59) / 60).max(1);
    let total_amount = (booking.price_per_minute * Decimal::from(duration_minutes)).round_dp(2);

    sqlx::query!(
        r#"
        UPDATE bookings
        SET end_time = $1, status = 'finished'
        WHERE id = $2
        "#,
        end_time,
        booking_id
    )
    .execute(&mut *tx)
    .await?;

    sqlx::query!(
        r#"
        INSERT INTO payments (booking_id, deposit_amount, total_amount, status)
        VALUES ($1, $2, $3, 'paid')
        "#,
        booking_id,
        booking.deposit_amount,
        total_amount
    )
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(Json(FinishResponse {
        id: booking.id,
        car_id: booking.car_id,
        start_time,
        end_time,
        duration_minutes,
        total_amount,
    }))
}

#[derive(Serialize)]
struct CarStatusResponse {
    car_id: i64,
    occupied: bool,
    booking_id: Option<i64>,
}

async fn car_status(
    State(pool): State<PgPool>,
    Path(car_id): Path<i64>,
) -> Result<Json<CarStatusResponse>, AppError> {
    let row = sqlx::query!(
        r#"
        SELECT c.id, b.id AS "booking_id?"
        FROM cars c
        LEFT JOIN bookings b
               ON b.car_id = c.id AND b.status IN ('active', 'incident')
        WHERE c.id = $1 AND c.deleted_at IS NULL
        "#,
        car_id
    )
    .fetch_optional(&pool)
    .await?
    .ok_or(AppError::CarNotFound)?;

    Ok(Json(CarStatusResponse {
        car_id: row.id,
        occupied: row.booking_id.is_some(),
        booking_id: row.booking_id,
    }))
}

#[derive(Serialize)]
struct BookingCard {
    id: i64,
    user_id: i64,
    car_id: i64,
    status: String,
    booking_time: DateTime<Utc>,
    start_time: Option<DateTime<Utc>>,
    end_time: Option<DateTime<Utc>>,
    car_brand_model: String,
    car_registration_number: String,
    price_per_minute: Decimal,
    deposit_amount: Decimal,
    total_amount: Option<Decimal>,
}

async fn get_booking(
    State(pool): State<PgPool>,
    Path(booking_id): Path<i64>,
) -> Result<Json<BookingCard>, AppError> {
    let card = sqlx::query_as!(
        BookingCard,
        r#"
        SELECT b.id, b.user_id, b.car_id, b.status, b.booking_time,
               b.start_time, b.end_time,
               b.car_brand_model, b.car_registration_number,
               b.price_per_minute, b.deposit_amount,
               p.total_amount AS "total_amount?"
        FROM bookings b
        LEFT JOIN payments p ON p.booking_id = b.id
        WHERE b.id = $1
        "#,
        booking_id
    )
    .fetch_optional(&pool)
    .await?
    .ok_or(AppError::BookingNotFound)?;

    Ok(Json(card))
}

#[derive(Deserialize)]
struct ListBookingsParams {
    user_id: i64,
}

async fn list_bookings(
    State(pool): State<PgPool>,
    Query(params): Query<ListBookingsParams>,
) -> Result<Json<Vec<BookingCard>>, AppError> {
    let cards = sqlx::query_as!(
        BookingCard,
        r#"
        SELECT b.id, b.user_id, b.car_id, b.status, b.booking_time,
               b.start_time, b.end_time,
               b.car_brand_model, b.car_registration_number,
               b.price_per_minute, b.deposit_amount,
               p.total_amount AS "total_amount?"
        FROM bookings b
        LEFT JOIN payments p ON p.booking_id = b.id
        WHERE b.user_id = $1
        ORDER BY b.booking_time DESC
        "#,
        params.user_id
    )
    .fetch_all(&pool)
    .await?;

    Ok(Json(cards))
}
