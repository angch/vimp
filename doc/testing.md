# Testing Strategy

## Broadway + Playwright Testing

Vimp supports headless UI testing using the GTK Broadway backend and Playwright. This allows running the application in a headless environment and verifying the UI via a web browser.

### Prerequisites

- **GTK4 Broadway Daemon**: `gtk4-broadwayd` (usually in `libgtk-4-bin` or `gtk-4-examples` depending on distro).
- **Playwright**: Python library.
- **Zig**: To build the application.

### Running the Test

1.  **Start the Application**: Use the helper script to start Vimp on a Broadway display (default :5).
    ```bash
    ./scripts/run_broadway.sh
    ```
    This script will:
    - Start `gtk4-broadwayd :5` if not running.
    - Set `GDK_BACKEND=broadway` and `BROADWAY_DISPLAY=:5`.
    - Run `zig build run`.

2.  **Run the Test Script**:
    In a separate terminal (while the app is running):
    ```bash
    python3 tests/broadway_test.py
    ```

    The test will:
    - Connect to `http://localhost:8085`.
    - Verify the canvas element loads.
    - Save a screenshot to `tests/vimp_broadway_screenshot.png`.

### Troubleshooting

-   **"Unable to init server"**: Ensure `gtk4-broadwayd` is installed and not blocked by firewall.
-   **Timeout**: The application might be taking too long to build/start. Ensure `run_broadway.sh` is fully up before running the python script.
