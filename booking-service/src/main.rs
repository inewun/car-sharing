mod auth;
mod error;
mod handlers;

use std::env;

use axum::Router;
use axum::routing::{get, patch, post};
use sqlx::postgres::PgPoolOptions;

use crate::handlers::{
    car_status, create_booking, finish_booking, get_booking, health, list_bookings,
};

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
