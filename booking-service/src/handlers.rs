use axum::Json;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::PgPool;

use crate::auth::UserId;
use crate::error::{AppError, booking_conflict};

pub async fn health(State(pool): State<PgPool>) -> (StatusCode, Json<Value>) {
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

#[derive(Deserialize)]
pub struct CreateBookingRequest {
    car_id: i64,
}

#[derive(Serialize)]
pub struct BookingResponse {
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

pub async fn create_booking(
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
pub struct FinishResponse {
    id: i64,
    car_id: i64,
    start_time: DateTime<Utc>,
    end_time: DateTime<Utc>,
    duration_minutes: i64,
    total_amount: Decimal,
}

pub async fn finish_booking(
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
pub struct BookingCard {
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

pub async fn get_booking(
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
pub struct ListBookingsParams {
    user_id: i64,
}

pub async fn list_bookings(
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

#[derive(Serialize)]
pub struct CarStatusResponse {
    car_id: i64,
    occupied: bool,
    booking_id: Option<i64>,
}

pub async fn car_status(
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
