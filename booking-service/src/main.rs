use std::env;

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::get;
use axum::{Json, Router};

use serde_json::{Value, json};

use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;

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

    let app = Router::new().route("/health", get(health)).with_state(pool);

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
