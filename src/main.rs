use actix_web::{web, App, HttpResponse, HttpServer, Responder};

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    HttpServer::new(|| App::new().route("/health_check", web::get().to(health_check)))
        .bind("127.0.0.1:8000")?
        .run()
        .await
}

async fn health_check() -> impl Responder {
    HttpResponse::Ok()
}
