# Enhanced Library Management System

## Project Description
A sophisticated subscription-based digital library management system that handles multiple resource types including books, research papers, educational kits, and audiobooks. The system includes user tier management, subscription handling, and fine tracking.

## Features
- Multi-resource type management (books, papers, kits, audiobooks)
- Subscription-based access with tiered user plans
- Automated fine calculation for overdue items
- Digital and physical inventory tracking
- Research document peer-review status tracking
- Comprehensive payment management

## Database Setup
1. Clone this repository
2. Import the complete SQL file using your database management tool:
```sql
source complete_library_system.sql
```

## Schema Overview
The system includes the following core tables:
- Users (with tier management)
- Resources (books, papers, kits, etc.)
- Authors
- Loans
- Subscriptions
- Payments
- Categories
- Reviews

## Implementation Details
- Includes stored procedures for common operations
- Implements triggers for automated updates
- Contains views for simplified reporting
- Includes sample data for testing

## Testing
Use the provided test queries in the SQL file to verify the setup.