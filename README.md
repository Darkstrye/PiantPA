# PIANT Order Processing Application

Flutter desktop application for order processing and time tracking.

## Features

- User authentication
- Order management (In Progress, Completed)
- Time tracking with pause/resume functionality
- Hour registration per order
- Completed orders overview

## Quick Start

**Keyboard Shortcut:** Press `Ctrl+Alt+F` to launch the app

The app uses Excel files for data storage (test environment) located in the `data/` folder.

## Project Structure

- `lib/models/` - Data models (Order, LoginDetails, HourRegistration)
- `lib/repositories/` - Data access layer (ExcelRepository, SqlRepository placeholder)
- `lib/services/` - Business logic (AuthService, TimerService, ExcelService)
- `lib/screens/` - UI screens (LoginScreen, MainScreen, CompletedOrdersScreen)
- `lib/widgets/` - Reusable UI components
- `data/` - Excel data files (not in git)

## Development

Run the app:
- Use `Ctrl+Alt+F` keyboard shortcut (recommended)
- Or run `run_app.bat` directly
