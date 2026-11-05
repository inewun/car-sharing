use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::json;

pub enum AppError {
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

pub fn booking_conflict(err: sqlx::Error) -> AppError {
    if let sqlx::Error::Database(ref db) = err {
        match db.constraint() {
            Some("uq_bookings_active_car") => return AppError::CarAlreadyBooked,
            Some("uq_bookings_active_user") => return AppError::ActiveBookingExists,
            _ => {}
        }
    }

    AppError::from(err)
}
