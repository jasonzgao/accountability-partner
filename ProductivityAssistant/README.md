# Productivity Assistant

A macOS productivity tracking and accountability application that monitors user behavior, integrates with existing productivity tools, and provides intelligent coaching to help users stay focused on their goals.

## Features

- Activity tracking and categorization
- Integration with Things 3 and Notion Calendar
- Goal and habit tracking
- Accountability mechanisms
- AI coaching via OpenAI's GPT-4
- Smart, context-aware notifications

## Setup

### Requirements

- macOS 12.0+
- Xcode 14.0+
- Swift 5.8+

### Installation

1. Clone the repository
2. Open the project in Xcode
3. Build and run the application

### Permissions

The application requires the following permissions:

- Accessibility permissions (for monitoring active applications)
- Notification permissions
- Calendar access
- Network access

## Development

### Project Structure

- **App**: Main application entry point and delegates
- **Models**: Data models and core entities
- **Services**: Business logic and service implementations
- **Repositories**: Data access and persistence
- **UI**: SwiftUI views and components
- **Utils**: Utility classes and extensions
- **Database**: Database configuration and migrations

### Dependencies

- **GRDB.swift**: SQLite database access
- **Combine**: Reactive programming
- **SwiftUI**: User interface

## License

This project is licensed under the MIT License - see the LICENSE file for details. 