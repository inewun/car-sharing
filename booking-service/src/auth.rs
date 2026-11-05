use axum::extract::FromRequestParts;
use axum::http::request::Parts;

use crate::error::AppError;

pub struct UserId(pub i64);

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
