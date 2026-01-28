use gtk4::prelude::*;
use gtk4::{Application, ApplicationWindow, DrawingArea};

fn main() {
    let app = Application::builder()
        .application_id("org.vimp.rust-prototype")
        .build();

    app.connect_activate(build_ui);

    app.run();
}

fn build_ui(app: &Application) {
    let drawing_area = DrawingArea::new();
    drawing_area.set_content_width(800);
    drawing_area.set_content_height(600);

    drawing_area.set_draw_func(|_area, cr, _width, _height| {
        // Draw background
        cr.set_source_rgb(0.2, 0.2, 0.2);
        cr.paint().expect("Invalid cairo surface state");

        // Draw a rectangle
        cr.set_source_rgb(0.9, 0.4, 0.4);
        cr.rectangle(100.0, 100.0, 200.0, 150.0);
        cr.fill().expect("Invalid cairo surface state");
    });

    let window = ApplicationWindow::builder()
        .application(app)
        .title("Vimp Rust Canvas Prototype")
        .child(&drawing_area)
        .build();

    window.present();
}
